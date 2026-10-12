package main

import (
	"crypto/subtle"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"path"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

//go:embed static/*
var staticFS embed.FS

// 认证相关状态
var (
	authMu        sync.Mutex
	invalidTokens = map[string]int64{} // token -> 过期时间(ms)
)

// 登录 Token 有效期：2 个月（60 天）
const tokenExpireDuration = 60 * 24 * time.Hour

// API 服务
type API struct {
	app *App
	cfg *Config
}

func (api *API) routes() http.Handler {
	mux := http.NewServeMux()

	// REST API
	mux.HandleFunc("/api/login", api.handleLogin)
	mux.HandleFunc("/api/logout", api.authenticate(api.handleLogout))
	mux.HandleFunc("/api/change-user-info", api.authenticate(api.handleChangeUserInfo))
	mux.HandleFunc("/api/userPool", api.authenticate(api.handleUserPool))
	mux.HandleFunc("/api/device/remark", api.authenticate(api.handleUpdateDeviceRemark))
	mux.HandleFunc("/api/device/delete", api.authenticate(api.handleDeleteDevice))
	mux.HandleFunc("/api/device/overview", api.authenticate(api.handleDeviceOverview))
	mux.HandleFunc("/api/device/overview/config", api.authenticate(api.handleSaveOverviewConfig))
	mux.HandleFunc("/api/executeTask", api.authenticate(api.handleExecuteTask))
	mux.HandleFunc("/api/tasks", api.authenticate(api.handleTasks))
	mux.HandleFunc("/api/tasks/clear", api.authenticate(api.handleClearTasks))
	mux.HandleFunc("/api/schedules", api.authenticate(api.handleSchedules))
	mux.HandleFunc("/api/schedules/add", api.authenticate(api.handleAddSchedule))
	mux.HandleFunc("/api/schedules/update", api.authenticate(api.handleUpdateSchedule))
	mux.HandleFunc("/api/schedules/toggle", api.authenticate(api.handleToggleSchedule))
	mux.HandleFunc("/api/schedules/delete", api.authenticate(api.handleDeleteSchedule))
	mux.HandleFunc("/api/schedules/run", api.authenticate(api.handleRunSchedule))
	mux.HandleFunc("/api/settings", api.authenticate(api.handleGetSettings))
	mux.HandleFunc("/api/settings/save", api.authenticate(api.handleSaveSettings))
	mux.HandleFunc("/api/notify/channels", api.authenticate(api.handleNotifyChannels))
	mux.HandleFunc("/api/notify/test", api.authenticate(api.handleTestNotify))
	mux.HandleFunc("/api/calls", api.authenticate(api.handleCallRecords))
	mux.HandleFunc("/api/calls/clear", api.authenticate(api.handleClearCallRecords))
	mux.HandleFunc("/api/calls/delete", api.authenticate(api.handleDeleteCallRecord))
	mux.HandleFunc("/api/sms", api.authenticate(api.handleSmsRecords))
	mux.HandleFunc("/api/sms/clear", api.authenticate(api.handleClearSmsRecords))
	mux.HandleFunc("/api/sms/delete", api.authenticate(api.handleDeleteSmsRecord))
	mux.HandleFunc("/api/logs", api.authenticate(api.handleLogs))
	mux.HandleFunc("/api/logs/clear", api.authenticate(api.handleClearLogs))
	mux.HandleFunc("/api/block-rules", api.authenticate(api.handleBlockRules))
	mux.HandleFunc("/api/block-rules/add", api.authenticate(api.handleAddBlockRule))
	mux.HandleFunc("/api/block-rules/update", api.authenticate(api.handleUpdateBlockRule))
	mux.HandleFunc("/api/block-rules/delete", api.authenticate(api.handleDeleteBlockRule))
	mux.HandleFunc("/api/block-rules/reset", api.authenticate(api.handleResetBlockRules))
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})

	// MQTT over WebSocket：与面板共享同一端口（nginx 把 /websocket 反代到本端口）
	mux.Handle("/websocket", api.app.MQTTWebSocketHandler())

	// 静态资源 + SPA 回退
	mux.HandleFunc("/", api.handleStatic)

	return mux
}

// ---------------- 认证 ----------------

// authenticate 校验 Bearer Token
func (api *API) authenticate(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		token := ""
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
		if token == "" {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"message": "未提供认证令牌"})
			return
		}

		authMu.Lock()
		if exp, ok := invalidTokens[token]; ok && exp > time.Now().UnixMilli() {
			authMu.Unlock()
			writeJSON(w, http.StatusForbidden, map[string]any{"message": "token已失效"})
			return
		}
		authMu.Unlock()

		claims := jwt.MapClaims{}
		parsed, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (any, error) {
			return []byte(api.cfg.JWTSecret), nil
		})
		if err != nil || !parsed.Valid {
			writeJSON(w, http.StatusForbidden, map[string]any{"message": "无效的认证令牌"})
			return
		}
		if v, ok := claims["version"]; ok {
			ver, _ := v.(float64)
			if int(ver) != api.cfg.TokenVersion {
				writeJSON(w, http.StatusForbidden, map[string]any{"message": "token已过期，请重新登录"})
				return
			}
		}
		next(w, r)
	}
}

// ---------------- 接口实现 ----------------

func (api *API) handleLogin(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	cfg := api.cfg
	s := api.app.getSettings()
	if subtle.ConstantTimeCompare([]byte(body.Username), []byte(s.Username)) != 1 ||
		bcrypt.CompareHashAndPassword([]byte(s.Password), []byte(body.Password)) != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"message": "用户名或密码错误"})
		return
	}

	claims := jwt.MapClaims{
		"username": body.Username,
		"version":  cfg.TokenVersion,
		"exp":      time.Now().Add(tokenExpireDuration).Unix(),
	}
	tk := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, err := tk.SignedString([]byte(cfg.JWTSecret))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "生成令牌失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"token": tokenStr})
}

func (api *API) handleLogout(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if token != "" {
		authMu.Lock()
		invalidTokens[token] = time.Now().Add(tokenExpireDuration).UnixMilli()
		authMu.Unlock()
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "退出登录成功"})
}

func (api *API) handleChangeUserInfo(w http.ResponseWriter, r *http.Request) {
	var body struct {
		OldPassword string `json:"oldPassword"`
		NewUsername string `json:"newUsername"`
		NewPassword string `json:"newPassword"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	// 账号信息存储在数据库 settings 表
	s := api.app.getSettings()
	cfg := api.cfg
	if bcrypt.CompareHashAndPassword([]byte(s.Password), []byte(body.OldPassword)) != nil {
		writeJSON(w, http.StatusOK, map[string]any{"message": "原密码错误"})
		return
	}

	hasChanges := false
	if body.NewUsername != "" && body.NewUsername != s.Username {
		s.Username = strings.TrimSpace(body.NewUsername)
		hasChanges = true
	}
	if body.NewPassword != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(body.NewPassword), 10)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "加密失败"})
			return
		}
		s.Password = string(hash)
		hasChanges = true
	}
	if hasChanges {
		cfg.TokenVersion++
		if err := api.app.saveSettings(s); err != nil {
			log.Printf("保存用户信息失败: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "保存失败"})
			return
		}
	}
	if err := api.cfg.Save(); err != nil {
		log.Printf("保存配置失败: %v", err)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"message":     "用户信息修改成功",
		"username":    s.Username,
		"needRelogin": hasChanges,
	})
}

// ---------------- 设置（通知 / 离线判定） ----------------

// handleGetSettings 返回面板设置（密码哈希不回传）
func (api *API) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, api.app.getSettings())
}

// handleSaveSettings 保存设置：离线通知配置
// 账号（用户名/密码）走 /api/change-user-info（带原密码校验）
func (api *API) handleSaveSettings(w http.ResponseWriter, r *http.Request) {
	var body struct {
		NotifyEnabled  bool                         `json:"notifyEnabled"`
		NotifyChannels []string                     `json:"notifyChannels"`
		NotifyConfig   map[string]map[string]string `json:"notifyConfig"`
		SMSEventLED    EventLED                     `json:"smsLed"`
		CallEventLED   EventLED                     `json:"callLed"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	s := api.app.getSettings()
	s.NotifyEnabled = body.NotifyEnabled
	if body.NotifyChannels == nil {
		body.NotifyChannels = []string{}
	}
	s.NotifyChannels = body.NotifyChannels
	if body.NotifyConfig == nil {
		body.NotifyConfig = map[string]map[string]string{}
	}
	s.NotifyConfig = body.NotifyConfig
	s.SMSEventLED = body.SMSEventLED
	s.CallEventLED = body.CallEventLED

	if err := api.app.saveSettings(s); err != nil {
		log.Printf("保存设置失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "保存设置失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "设置已保存"})
}

// handleTestNotify 发送测试通知：用表单中当前填写的渠道与配置立即推送一条测试消息
func (api *API) handleTestNotify(w http.ResponseWriter, r *http.Request) {
	var body struct {
		NotifyChannels []string                     `json:"channels"`
		NotifyConfig   map[string]map[string]string `json:"config"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if len(body.NotifyChannels) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "请先选择至少一个通知渠道"})
		return
	}
	if body.NotifyConfig == nil {
		body.NotifyConfig = map[string]map[string]string{}
	}
	msg := "【测试通知】Air724UG 设备面板离线通知配置正常"
	var failed []string
	for _, ch := range body.NotifyChannels {
		if err := sendNotify(msg, ch, body.NotifyConfig[ch]); err != nil {
			log.Printf("测试通知发送失败 channel=%s: %v", ch, err)
			failed = append(failed, ch+": "+err.Error())
		} else {
			log.Printf("测试通知已发送 channel=%s", ch)
		}
	}
	if len(failed) > 0 {
		writeJSON(w, http.StatusOK, map[string]any{"success": false, "message": "部分渠道发送失败: " + strings.Join(failed, "；")})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "测试通知已发送"})
}

// handleNotifyChannels 返回支持的通知渠道定义（供前端渲染配置表单）
func (api *API) handleNotifyChannels(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, notifyChannelDefs())
}

func (api *API) handleUserPool(w http.ResponseWriter, r *http.Request) {
	devices, err := api.app.deviceList()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询设备失败"})
		return
	}
	writeJSON(w, http.StatusOK, devices)
}

func (api *API) handleUpdateDeviceRemark(w http.ResponseWriter, r *http.Request) {
	var body struct {
		IMEI string `json:"imei"`
		Name string `json:"name"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	if body.IMEI == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少设备 IMEI"})
		return
	}
	if err := api.app.updateDeviceName(body.IMEI, body.Name); err != nil {
		log.Printf("保存设备备注失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "保存备注失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "备注已保存"})
}

func (api *API) handleDeleteDevice(w http.ResponseWriter, r *http.Request) {
	var body struct {
		IMEI string `json:"imei"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.IMEI == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少设备 IMEI"})
		return
	}
	if err := api.app.deleteDevice(body.IMEI); err != nil {
		log.Printf("删除设备失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除设备失败"})
		return
	}
	log.Printf("设备已删除 - IMEI: %s", body.IMEI)
	writeJSON(w, http.StatusOK, map[string]any{"message": "设备已删除"})
}

func (api *API) handleExecuteTask(w http.ResponseWriter, r *http.Request) {
	raw := map[string]any{}
	if err := decodeJSON(r, &raw); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "请求体格式错误"})
		return
	}
	imei, _ := raw["imei"].(string)
	task, _ := raw["task"].(string)
	if imei == "" || task == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "缺少必要参数"})
		return
	}
	// 其余字段作为任务附加参数转发给设备
	delete(raw, "imei")
	delete(raw, "task")

	result, err := api.app.ExecuteTask(imei, task, raw)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "result": result})
}

// handleTasks 分页返回任务记录。查询参数 page 从 1 开始，每页 10 条；同时返回总数供前端分页。
func (api *API) handleTasks(w http.ResponseWriter, r *http.Request) {
	page := 1
	if v, err := strconv.Atoi(r.URL.Query().Get("page")); err == nil && v > 0 {
		page = v
	}
	const pageSize = 10

	tasks, err := api.app.db.recentTasks(page, pageSize)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询任务失败"})
		return
	}
	total, err := api.app.db.countTasks()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询任务失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"tasks":    tasks,
		"total":    total,
		"page":     page,
		"pageSize": pageSize,
	})
}

// handleClearTasks 删除任务记录。body: {"days": 7} 表示删除 7 天前的旧日志（保留近 7 天）；days <= 0 或缺省表示删除全部。
func (api *API) handleClearTasks(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Days int `json:"days"`
	}
	// 允许空请求体（视为删除全部）
	if err := decodeJSON(r, &body); err != nil && err.Error() != "EOF" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	n, err := api.app.db.deleteTasks(body.Days)
	if err != nil {
		log.Printf("删除任务记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "删除成功", "deleted": n})
}

// ---------------- 定时任务 ----------------

// scheduleBody 定时任务接口的请求体
type scheduleBody struct {
	ID      int64           `json:"id"`
	Name    string          `json:"name"`
	IMEI    string          `json:"imei"`
	Task    string          `json:"task"`
	Params  json.RawMessage `json:"params"`
	Spec    json.RawMessage `json:"spec"`
	Enabled *bool           `json:"enabled"`
}

// normalizeScheduleParams 任务参数：空 / null / {} 归一化为 "{}"，必须是 JSON 对象
func normalizeScheduleParams(raw json.RawMessage) (string, error) {
	s := strings.TrimSpace(string(raw))
	if s == "" || s == "null" || s == "{}" {
		return "{}", nil
	}
	var obj map[string]any
	if err := json.Unmarshal(raw, &obj); err != nil {
		return "", errors.New("任务参数必须是 JSON 对象")
	}
	return s, nil
}

// parseScheduleBody 解析并校验定时任务请求体（新增/编辑共用）
func parseScheduleBody(r *http.Request) (*scheduleBody, string, error) {
	var body scheduleBody
	if err := decodeJSON(r, &body); err != nil {
		return nil, "", errors.New("请求体格式错误")
	}
	body.Name = strings.TrimSpace(body.Name)
	if body.IMEI == "" {
		return nil, "", errors.New("缺少设备 IMEI")
	}
	if body.Task == "" {
		return nil, "", errors.New("缺少任务类型")
	}
	if err := validateSpec(body.Spec); err != nil {
		return nil, "", err
	}
	params, err := normalizeScheduleParams(body.Params)
	if err != nil {
		return nil, "", err
	}
	return &body, params, nil
}

// handleSchedules GET 分页返回定时任务列表，每页 5 条（查询参数 page 从 1 开始）
func (api *API) handleSchedules(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	page := 1
	if v, err := strconv.Atoi(r.URL.Query().Get("page")); err == nil && v > 0 {
		page = v
	}
	const pageSize = 5

	list, err := api.app.db.listSchedulesPage(page, pageSize)
	if err != nil {
		log.Printf("查询定时任务失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询定时任务失败"})
		return
	}
	total, err := api.app.db.countSchedules()
	if err != nil {
		log.Printf("查询定时任务失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询定时任务失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"schedules": list,
		"total":     total,
		"page":      page,
		"pageSize":  pageSize,
	})
}

// handleAddSchedule 新增定时任务
func (api *API) handleAddSchedule(w http.ResponseWriter, r *http.Request) {
	body, params, err := parseScheduleBody(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": err.Error()})
		return
	}
	enabled := body.Enabled == nil || *body.Enabled
	sc := Schedule{
		Name: body.Name, IMEI: body.IMEI, Task: body.Task,
		Params: params, Spec: body.Spec, Enabled: enabled,
	}
	if _, err := api.app.db.addSchedule(sc); err != nil {
		log.Printf("添加定时任务失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "添加定时任务失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "定时任务添加成功"})
}

// handleUpdateSchedule 编辑定时任务（整体更新）
func (api *API) handleUpdateSchedule(w http.ResponseWriter, r *http.Request) {
	body, params, err := parseScheduleBody(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": err.Error()})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少任务 ID"})
		return
	}
	if _, err := api.app.db.getSchedule(body.ID); err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"message": "定时任务不存在"})
		return
	}
	enabled := body.Enabled == nil || *body.Enabled
	sc := Schedule{
		ID: body.ID, Name: body.Name, IMEI: body.IMEI, Task: body.Task,
		Params: params, Spec: body.Spec, Enabled: enabled,
	}
	if err := api.app.db.updateSchedule(sc); err != nil {
		log.Printf("更新定时任务失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "更新定时任务失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "定时任务已更新"})
}

// handleToggleSchedule 启用/停用定时任务
func (api *API) handleToggleSchedule(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID      int64 `json:"id"`
		Enabled bool  `json:"enabled"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少任务 ID"})
		return
	}
	if err := api.app.db.setScheduleEnabled(body.ID, body.Enabled); err != nil {
		log.Printf("切换定时任务状态失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "操作失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "状态已更新"})
}

// handleDeleteSchedule 删除定时任务
func (api *API) handleDeleteSchedule(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID int64 `json:"id"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少任务 ID"})
		return
	}
	if err := api.app.db.deleteSchedule(body.ID); err != nil {
		log.Printf("删除定时任务失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "删除成功"})
}

// handleRunSchedule 立即执行一次定时任务（不等周期，直接下发）
func (api *API) handleRunSchedule(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID int64 `json:"id"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少任务 ID"})
		return
	}
	sc, err := api.app.db.getSchedule(body.ID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"message": "定时任务不存在"})
		return
	}
	if !api.app.isDeviceOnline(sc.IMEI) {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "设备当前离线"})
		return
	}
	var extra map[string]any
	if sc.Params != "" && sc.Params != "{}" {
		_ = json.Unmarshal([]byte(sc.Params), &extra)
	}
	if extra == nil {
		extra = map[string]any{}
	}
	result, err := api.app.ExecuteTask(sc.IMEI, sc.Task, extra)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "result": result})
}

// ---------------- 通话记录 / 短信记录 ----------------

// parseRecordFilter 解析记录列表共用的分页与筛选参数（page/from/to/imei）
func parseRecordFilter(r *http.Request) (page, pageSize int, from, to int64, imei string) {
	page = 1
	pageSize = 10
	if v, err := strconv.Atoi(r.URL.Query().Get("page")); err == nil && v > 0 {
		page = v
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("pageSize")); err == nil && v > 0 {
		pageSize = v
	}
	if v, err := strconv.ParseInt(r.URL.Query().Get("from"), 10, 64); err == nil && v > 0 {
		from = v
	}
	if v, err := strconv.ParseInt(r.URL.Query().Get("to"), 10, 64); err == nil && v > 0 {
		to = v
	}
	imei = r.URL.Query().Get("imei")
	return
}

// handleCallRecords GET 分页返回通话记录，支持时间范围与设备筛选
func (api *API) handleCallRecords(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	page, pageSize, from, to, imei := parseRecordFilter(r)
	list, err := api.app.db.callRecords(page, pageSize, from, to, imei)
	if err != nil {
		log.Printf("查询通话记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询通话记录失败"})
		return
	}
	total, err := api.app.db.countCallRecords(from, to, imei)
	if err != nil {
		log.Printf("统计通话记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询通话记录失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"calls":    list,
		"total":    total,
		"page":     page,
		"pageSize": pageSize,
	})
}

// handleClearCallRecords POST 清理通话记录。body: {"days": 7} 删除 7 天前的；days<=0 删除全部。
func (api *API) handleClearCallRecords(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Days int `json:"days"`
	}
	if err := decodeJSON(r, &body); err != nil && err.Error() != "EOF" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	n, err := api.app.db.clearCallRecords(body.Days)
	if err != nil {
		log.Printf("清理通话记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "清理失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "清理成功", "deleted": n})
}

// handleDeleteCallRecord POST 删除单条通话记录。body: {"id": 1}
func (api *API) handleDeleteCallRecord(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID int64 `json:"id"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少记录 id"})
		return
	}
	n, err := api.app.db.deleteCallRecord(body.ID)
	if err != nil {
		log.Printf("删除通话记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "删除成功", "deleted": n})
}
func (api *API) handleSmsRecords(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	page, pageSize, from, to, imei := parseRecordFilter(r)
	list, err := api.app.db.smsRecords(page, pageSize, from, to, imei)
	if err != nil {
		log.Printf("查询短信记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询短信记录失败"})
		return
	}
	total, err := api.app.db.countSmsRecords(from, to, imei)
	if err != nil {
		log.Printf("统计短信记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询短信记录失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"sms":      list,
		"total":    total,
		"page":     page,
		"pageSize": pageSize,
	})
}

// handleClearSmsRecords POST 清理短信记录。body: {"days": 7} 删除 7 天前的；days<=0 删除全部。
func (api *API) handleClearSmsRecords(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Days int `json:"days"`
	}
	if err := decodeJSON(r, &body); err != nil && err.Error() != "EOF" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	n, err := api.app.db.clearSmsRecords(body.Days)
	if err != nil {
		log.Printf("清理短信记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "清理失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "清理成功", "deleted": n})
}

// handleDeleteSmsRecord POST 删除单条短信记录。body: {"id": 1}
func (api *API) handleDeleteSmsRecord(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID int64 `json:"id"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少记录 id"})
		return
	}
	n, err := api.app.db.deleteSmsRecord(body.ID)
	if err != nil {
		log.Printf("删除短信记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "删除成功", "deleted": n})
}

// handleLogs GET 分页返回设备上报日志。query: page/pageSize/from/to/imei/type/keyword
func (api *API) handleLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	page, pageSize, from, to, imei := parseRecordFilter(r)
	logType := r.URL.Query().Get("type")
	keyword := r.URL.Query().Get("keyword")
	list, err := api.app.db.deviceLogs(page, pageSize, from, to, imei, logType, keyword)
	if err != nil {
		log.Printf("查询设备日志失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询设备日志失败"})
		return
	}
	total, err := api.app.db.countDeviceLogs(from, to, imei, logType, keyword)
	if err != nil {
		log.Printf("统计设备日志失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询设备日志失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"logs":     list,
		"total":    total,
		"page":     page,
		"pageSize": pageSize,
	})
}

// handleClearLogs POST 清理设备日志。body: {"days": 7} 删除 7 天前的；days<=0 删除全部。
func (api *API) handleClearLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	var body struct {
		Days int `json:"days"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	n, err := api.app.db.clearDeviceLogs(body.Days)
	if err != nil {
		log.Printf("清理设备日志失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "清理失败"})
		return
	}
	msg := "已删除全部设备日志"
	if body.Days > 0 {
		msg = fmt.Sprintf("已清理 %d 条 %d 天前的设备日志", n, body.Days)
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": msg, "deleted": n})
}
func (api *API) handleBlockRules(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	q := r.URL.Query()
	ruleType := q.Get("type")
	if q.Get("page") == "" && q.Get("size") == "" {
		// 未携带分页参数：返回全部规则（兼容旧客户端）
		rules, err := api.app.db.blockRules(ruleType)
		if err != nil {
			log.Printf("查询屏蔽规则失败: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询屏蔽规则失败"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"rules": rules})
		return
	}
	page, _ := strconv.Atoi(q.Get("page"))
	size, _ := strconv.Atoi(q.Get("size"))
	rules, total, err := api.app.db.blockRulesPage(ruleType, page, size)
	if err != nil {
		log.Printf("查询屏蔽规则失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询屏蔽规则失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"rules": rules, "total": total})
}

// handleAddBlockRule POST 新增屏蔽规则。body: {"ruleType":"keyword|number","value":"...","matchMode":"contains|prefix|exact","note":"..."}
func (api *API) handleAddBlockRule(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RuleType  string `json:"ruleType"`
		Value     string `json:"value"`
		MatchMode string `json:"matchMode"`
		Note      string `json:"note"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	body.RuleType = strings.TrimSpace(body.RuleType)
	body.Value = strings.TrimSpace(body.Value)
	if body.RuleType != "keyword" && body.RuleType != "number" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "ruleType 必须为 keyword 或 number"})
		return
	}
	if body.Value == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "规则内容不能为空"})
		return
	}
	if body.MatchMode == "" {
		body.MatchMode = "contains"
	}
	if body.RuleType == "number" && body.MatchMode != "exact" && body.MatchMode != "contains" {
		body.MatchMode = "prefix"
	}
	ok, err := api.app.db.addBlockRule(BlockRule{
		RuleType: body.RuleType, Value: body.Value, MatchMode: body.MatchMode, Note: body.Note, Source: "user",
	})
	if err != nil {
		log.Printf("新增屏蔽规则失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "新增失败"})
		return
	}
	if !ok {
		writeJSON(w, http.StatusOK, map[string]any{"message": "该规则已存在，未重复添加", "duplicated": true})
		return
	}
	// 刷新缓存并广播给在线设备
	api.app.refreshBlockRules()
	api.app.publishBlockRulesAll()
	writeJSON(w, http.StatusOK, map[string]any{"message": "新增成功"})
}

// handleUpdateBlockRule POST 更新屏蔽规则。body: {"id":1,"value":"...","matchMode":"...","enabled":1,"note":"..."}
func (api *API) handleUpdateBlockRule(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID        int64  `json:"id"`
		Value     string `json:"value"`
		MatchMode string `json:"matchMode"`
		Enabled   int    `json:"enabled"`
		Note      string `json:"note"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少规则 id"})
		return
	}
	if strings.TrimSpace(body.Value) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "规则内容不能为空"})
		return
	}
	if err := api.app.db.updateBlockRule(body.ID, strings.TrimSpace(body.Value), body.MatchMode, body.Enabled, body.Note); err != nil {
		log.Printf("更新屏蔽规则失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "更新失败"})
		return
	}
	api.app.refreshBlockRules()
	api.app.publishBlockRulesAll()
	writeJSON(w, http.StatusOK, map[string]any{"message": "更新成功"})
}

// handleDeleteBlockRule POST 删除屏蔽规则。body: {"id":1}
func (api *API) handleDeleteBlockRule(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID int64 `json:"id"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少规则 id"})
		return
	}
	if err := api.app.db.deleteBlockRule(body.ID); err != nil {
		log.Printf("删除屏蔽规则失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	api.app.refreshBlockRules()
	api.app.publishBlockRulesAll()
	writeJSON(w, http.StatusOK, map[string]any{"message": "删除成功"})
}

// handleResetBlockRules POST 重置内置默认库（删除全部 builtin 规则并重新写入默认数据）
func (api *API) handleResetBlockRules(w http.ResponseWriter, r *http.Request) {
	if err := api.app.db.resetBuiltinRules(); err != nil {
		log.Printf("重置内置屏蔽库失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "重置失败"})
		return
	}
	api.app.refreshBlockRules()
	api.app.publishBlockRulesAll()
	writeJSON(w, http.StatusOK, map[string]any{"message": "已恢复内置默认库"})
}

// ---------------- 静态资源 ----------------

func (api *API) handleStatic(w http.ResponseWriter, r *http.Request) {
	// 只处理 GET/HEAD
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	p := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if p == "." || p == "" {
		p = "index.html"
	}

	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		http.Error(w, "静态资源不可用", http.StatusInternalServerError)
		return
	}

	// 前端页面/脚本为 go:embed 内嵌资源，禁止浏览器缓存，避免改动后仍显示旧版本
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")

	// 尝试真实文件
	if f, err := sub.Open(p); err == nil {
		f.Close()
		http.ServeFileFS(w, r, sub, p)
		return
	}
	// SPA 回退到 index.html
	http.ServeFileFS(w, r, sub, "index.html")
}

// ---------------- 工具 ----------------

func decodeJSON(r *http.Request, v any) error {
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(v)
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// ---------------- 设备概览 ----------------

// voltageToPercent 锂电池电压（mV）→ 估算电量百分比（分段线性近似）
func voltageToPercent(mv int) int {
	v := float64(mv) / 1000.0
	switch {
	case mv <= 0:
		return 0
	case v <= 3.30:
		return 0
	case v >= 4.20:
		return 100
	case v <= 3.60:
		return int((v-3.30)/(3.60-3.30)*30 + 0.5)
	case v <= 3.80:
		return int((v-3.60)/(3.80-3.60)*(60-30) + 30 + 0.5)
	case v <= 4.05:
		return int((v-3.80)/(4.05-3.80)*(85-60) + 60 + 0.5)
	default:
		return int((v-4.05)/(4.20-4.05)*(100-85) + 85 + 0.5)
	}
}

// estimateCurrentMa 估算当前电流（mA）。
// Air724UG 模块无电流采样，此为基于充电状态/信号强度的功耗估算；
// 用户可在概览页配置 avg_current_ma 用实测值覆盖（>0 时优先返回该值）。
func estimateCurrentMa(charging bool, rssi int, avgConfigured int) int {
	if avgConfigured > 0 {
		return avgConfigured
	}
	if charging {
		return 30 // 充电状态：模块自身功耗较低（电池在充电）
	}
	base := 60 // 联网待机典型功耗
	switch {
	case rssi == 0:
		return base
	case rssi < -105:
		return base + 40 // 极弱信号，发射功率高
	case rssi < -95:
		return base + 25
	case rssi < -85:
		return base + 10
	}
	return base
}

// settingOr 读取面板设置键，缺省返回默认值
func (api *API) settingOr(key, def string) string {
	v, err := api.app.db.getSetting(key)
	if err != nil || v == "" {
		return def
	}
	return v
}

// handleDeviceOverview 返回指定设备的概览数据（设备信息+在线时长+最新遥测+历史趋势+电量/电流/续航估算）
func (api *API) handleDeviceOverview(w http.ResponseWriter, r *http.Request) {
	imei := strings.TrimSpace(r.URL.Query().Get("imei"))
	if imei == "" {
		writeJSON(w, 400, map[string]string{"message": "缺少参数: imei"})
		return
	}
	now := time.Now().Unix()

	// 设备信息
	var dev *Device
	if devs, err := api.app.deviceList(); err == nil {
		for i := range devs {
			if devs[i].IMEI == imei {
				d := devs[i]
				dev = &d
				break
			}
		}
	}

	// 本次在线时长
	var connectedAt, onlineSeconds int64
	api.app.mu.RLock()
	if st, ok := api.app.devices[imei]; ok && st.Connected {
		connectedAt = st.ConnectedAt
		if onlineSeconds = now - st.ConnectedAt; onlineSeconds < 0 {
			onlineSeconds = 0
		}
	}
	api.app.mu.RUnlock()

	latest, _ := api.app.db.latestTelemetry(imei)
	history, _ := api.app.db.recentTelemetry(imei, 30)

	batteryMah, _ := strconv.Atoi(api.settingOr("battery_mah", "1800"))
	if batteryMah < 100 {
		batteryMah = 1800
	}
	avgCurrentMa, _ := strconv.Atoi(api.settingOr("avg_current_ma", "0"))

	batteryPercent := 0
	charging := false
	var latestVoltage, latestRssi int
	if latest != nil {
		batteryPercent = voltageToPercent(latest.Voltage)
		charging = latest.VBUS
		latestVoltage = latest.Voltage
		latestRssi = latest.RSSI
	}

	estCurrentMa := estimateCurrentMa(charging, latestRssi, avgCurrentMa)
	var estHours float64
	if estCurrentMa > 0 && batteryPercent > 0 {
		remainingMah := float64(batteryMah) * float64(batteryPercent) / 100.0
		estHours = remainingMah / float64(estCurrentMa)
	}

	writeJSON(w, 200, map[string]any{
		"device":        dev,
		"connectedAt":   connectedAt,
		"onlineSeconds": onlineSeconds,
		"latest":        latest,
		"history":       history,
		"battery": map[string]any{
			"mah": batteryMah, "percent": batteryPercent,
			"voltage": latestVoltage, "charging": charging,
		},
		"power": map[string]any{
			"currentMa": estCurrentMa, "estHours": estHours, "avgCurrentMa": avgCurrentMa,
		},
	})
}

// handleSaveOverviewConfig 保存概览页的电池容量与平均电流配置
func (api *API) handleSaveOverviewConfig(w http.ResponseWriter, r *http.Request) {
	var req struct {
		BatteryMah   int `json:"batteryMah"`
		AvgCurrentMa int `json:"avgCurrentMa"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeJSON(w, 400, map[string]string{"message": "参数格式错误"})
		return
	}
	if req.BatteryMah < 100 {
		req.BatteryMah = 1800
	}
	if req.AvgCurrentMa < 0 {
		req.AvgCurrentMa = 0
	}
	if err := api.app.db.setSetting("battery_mah", strconv.Itoa(req.BatteryMah)); err != nil {
		writeJSON(w, 500, map[string]string{"message": "保存失败: " + err.Error()})
		return
	}
	if err := api.app.db.setSetting("avg_current_ma", strconv.Itoa(req.AvgCurrentMa)); err != nil {
		writeJSON(w, 500, map[string]string{"message": "保存失败: " + err.Error()})
		return
	}
	writeJSON(w, 200, map[string]string{"message": "保存成功"})
}

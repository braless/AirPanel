package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"embed"
	"encoding/hex"
	"encoding/json"
	"io/fs"
	"net/http"
	"os"
	"path"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

//go:embed static
var staticFS embed.FS

// assetVersion 前端资源的内容指纹：static/ 下所有文件内容的 sha256 前 10 位。
// 每次改动前端重新编译，版本号就会变，index.html 里的 ?v= 与模块 import 的 ?v=
// 随之变化，CDN（Cloudflare 等）缓存必然失效，不会再出现「部署了但没生效」。
var assetVersion = computeAssetVersion()

func computeAssetVersion() string {
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		return "0"
	}
	var files []string
	_ = fs.WalkDir(sub, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		files = append(files, p)
		return nil
	})
	sort.Strings(files)
	h := sha256.New()
	for _, p := range files {
		b, err := fs.ReadFile(sub, p)
		if err != nil {
			continue
		}
		h.Write([]byte(p))
		h.Write(b)
	}
	return hex.EncodeToString(h.Sum(nil))[:10]
}

// ES 模块的相对导入：from './ui.js' / from "../ui.js"
var jsImportRe = regexp.MustCompile(`(from\s*["'])(\.{1,2}/[^"'\s?]+\.js)(["'])`)

// rewriteJSImports 给模块导入路径追加版本号，避免 CDN 缓存旧的子模块
func rewriteJSImports(src []byte, ver string) []byte {
	return jsImportRe.ReplaceAllFunc(src, func(m []byte) []byte {
		s := jsImportRe.FindSubmatch(m)
		if len(s) != 4 {
			return m
		}
		return []byte(string(s[1]) + string(s[2]) + "?v=" + ver + string(s[3]))
	})
}

// 认证相关状态
var (
	authMu        sync.Mutex
	invalidTokens = map[string]int64{} // token -> 过期时间(ms)
)

// 登录 Token 有效期：60 天
const tokenExpireDuration = 60 * 24 * time.Hour

// 进程启动时间，用于计算服务运行时长
var serverStartTime = time.Now()

// API 服务
type API struct {
	app  *App
	cfg  *Config
	logs *ServerLogBuffer
}

func (api *API) routes() http.Handler {
	mux := http.NewServeMux()

	// 认证
	mux.HandleFunc("/api/login", api.handleLogin)
	mux.HandleFunc("/api/logout", api.authenticate(api.handleLogout))
	mux.HandleFunc("/api/change-user-info", api.authenticate(api.handleChangeUserInfo))

	// 设备
	mux.HandleFunc("/api/userPool", api.authenticate(api.handleUserPool))
	mux.HandleFunc("/api/device/remark", api.authenticate(api.handleUpdateDeviceRemark))
	mux.HandleFunc("/api/device/delete", api.authenticate(api.handleDeleteDevice))
	mux.HandleFunc("/api/device/overview", api.authenticate(api.handleDeviceOverview))
	mux.HandleFunc("/api/device/overview/config", api.authenticate(api.handleSaveOverviewConfig))
	mux.HandleFunc("/api/stats/summary", api.authenticate(api.handleStatsSummary))

	// 任务
	mux.HandleFunc("/api/executeTask", api.authenticate(api.handleExecuteTask))
	mux.HandleFunc("/api/tasks", api.authenticate(api.handleTasks))
	mux.HandleFunc("/api/tasks/clear", api.authenticate(api.handleClearTasks))

	// 定时任务
	mux.HandleFunc("/api/schedules", api.authenticate(api.handleSchedules))
	mux.HandleFunc("/api/schedules/add", api.authenticate(api.handleAddSchedule))
	mux.HandleFunc("/api/schedules/update", api.authenticate(api.handleUpdateSchedule))
	mux.HandleFunc("/api/schedules/toggle", api.authenticate(api.handleToggleSchedule))
	mux.HandleFunc("/api/schedules/delete", api.authenticate(api.handleDeleteSchedule))
	mux.HandleFunc("/api/schedules/run", api.authenticate(api.handleRunSchedule))

	// 设置 / 通知
	mux.HandleFunc("/api/settings", api.authenticate(api.handleGetSettings))
	mux.HandleFunc("/api/settings/save", api.authenticate(api.handleSaveSettings))
	mux.HandleFunc("/api/notify/channels", api.authenticate(api.handleNotifyChannels))
	mux.HandleFunc("/api/notify/test", api.authenticate(api.handleTestNotify))

	// 记录
	mux.HandleFunc("/api/calls", api.authenticate(api.handleCallRecords))
	mux.HandleFunc("/api/calls/clear", api.authenticate(api.handleClearCallRecords))
	mux.HandleFunc("/api/calls/delete", api.authenticate(api.handleDeleteCallRecord))
	mux.HandleFunc("/api/sms", api.authenticate(api.handleSmsRecords))
	mux.HandleFunc("/api/sms/clear", api.authenticate(api.handleClearSmsRecords))
	mux.HandleFunc("/api/sms/delete", api.authenticate(api.handleDeleteSmsRecord))

	// 日志
	mux.HandleFunc("/api/logs", api.authenticate(api.handleLogs))
	mux.HandleFunc("/api/logs/clear", api.authenticate(api.handleClearLogs))
	mux.HandleFunc("/api/server-logs", api.authenticate(api.handleServerLogs))
	mux.HandleFunc("/api/server-logs/clear", api.authenticate(api.handleClearServerLogs))
	mux.HandleFunc("/api/login-logs", api.authenticate(api.handleLoginLogs))
	mux.HandleFunc("/api/login-logs/clear", api.authenticate(api.handleClearLoginLogs))

	// 屏蔽规则
	mux.HandleFunc("/api/block-rules", api.authenticate(api.handleBlockRules))
	mux.HandleFunc("/api/block-rules/add", api.authenticate(api.handleAddBlockRule))
	mux.HandleFunc("/api/block-rules/update", api.authenticate(api.handleUpdateBlockRule))
	mux.HandleFunc("/api/block-rules/delete", api.authenticate(api.handleDeleteBlockRule))
	mux.HandleFunc("/api/block-rules/reset", api.authenticate(api.handleResetBlockRules))

	// 通话录音（WebDAV）
	mux.HandleFunc("/api/recordings", api.authenticate(api.handleRecordings))
	mux.HandleFunc("/api/recordings/play", api.authenticate(api.handleRecordingPlay))
	mux.HandleFunc("/api/recordings/download", api.authenticate(api.handleRecordingDownload))
	mux.HandleFunc("/api/recordings/delete", api.authenticate(api.handleRecordingDelete))

	// 运维
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":        true,
			"version":   "v2",
			"uptimeSec": int64(time.Since(serverStartTime).Seconds()),
		})
	})
	mux.HandleFunc("/api/restart", api.authenticate(api.handleRestart))

	// MQTT over WebSocket：与面板共享同一端口
	mux.Handle("/websocket", api.app.MQTTWebSocketHandler())

	// 静态资源 + SPA 回退
	mux.HandleFunc("/", api.handleStatic)

	return mux
}

// handleRestart 重启服务端（Linux 调用部署脚本；Windows 不支持）
func (api *API) handleRestart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	cmd := newRestartCmd()
	if cmd == nil {
		writeJSON(w, http.StatusNotImplemented, map[string]any{
			"success": false, "message": "当前平台不支持远程重启，请手动重启进程",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "正在重启服务端，请稍候…"})
	go func() {
		time.Sleep(800 * time.Millisecond)
		if err := cmd.Start(); err != nil {
			return
		}
		time.Sleep(300 * time.Millisecond)
		os.Exit(0)
	}()
}

// ---------------- 认证 ----------------

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
			// 令牌失效统一用 401：前端据此清除本地 token 并回到登录页
			writeJSON(w, http.StatusUnauthorized, map[string]any{"message": "token 已失效"})
			return
		}
		authMu.Unlock()

		claims := jwt.MapClaims{}
		parsed, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (any, error) {
			return []byte(api.cfg.JWTSecret), nil
		})
		if err != nil || !parsed.Valid {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"message": "无效的认证令牌"})
			return
		}
		if v, ok := claims["version"]; ok {
			ver, _ := v.(float64)
			if int(ver) != api.cfg.TokenVersion {
				writeJSON(w, http.StatusUnauthorized, map[string]any{"message": "token 已过期，请重新登录"})
				return
			}
		}
		next(w, r)
	}
}

func (api *API) handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	s := api.app.getSettings()
	if subtle.ConstantTimeCompare([]byte(body.Username), []byte(s.Username)) != 1 ||
		bcrypt.CompareHashAndPassword([]byte(s.Password), []byte(body.Password)) != nil {
		// 记录登录失败：IP + 客户端信息 + 失败原因
		_ = api.app.db.addLoginLog(body.Username, clientIP(r), r.Header.Get("User-Agent"), false, "用户名或密码错误")
		writeJSON(w, http.StatusUnauthorized, map[string]any{"message": "用户名或密码错误"})
		return
	}

	// 记录登录成功：IP + 客户端信息
	_ = api.app.db.addLoginLog(s.Username, clientIP(r), r.Header.Get("User-Agent"), true, "")

	claims := jwt.MapClaims{
		"username": body.Username,
		"version":  api.cfg.TokenVersion,
		"exp":      time.Now().Add(tokenExpireDuration).Unix(),
	}
	tk := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, err := tk.SignedString([]byte(api.cfg.JWTSecret))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "生成令牌失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"token": tokenStr, "username": s.Username})
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
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	var body struct {
		OldPassword string `json:"oldPassword"`
		NewUsername string `json:"newUsername"`
		NewPassword string `json:"newPassword"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	s := api.app.getSettings()
	if bcrypt.CompareHashAndPassword([]byte(s.Password), []byte(body.OldPassword)) != nil {
		writeJSON(w, http.StatusOK, map[string]any{"success": false, "message": "原密码错误"})
		return
	}

	hasChanges := false
	if body.NewUsername != "" && body.NewUsername != s.Username {
		s.Username = strings.TrimSpace(body.NewUsername)
		hasChanges = true
	}
	if body.NewPassword != "" {
		if len(body.NewPassword) < 6 {
			writeJSON(w, http.StatusOK, map[string]any{"success": false, "message": "新密码至少 6 位"})
			return
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(body.NewPassword), 10)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "加密失败"})
			return
		}
		s.Password = string(hash)
		hasChanges = true
	}
	if hasChanges {
		api.cfg.TokenVersion++
		if err := api.app.saveSettings(s); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "保存失败"})
			return
		}
		_ = api.cfg.Save()
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"success":     true,
		"message":     "用户信息修改成功",
		"username":    s.Username,
		"needRelogin": hasChanges,
	})
}

// ---------------- 静态资源 ----------------

func (api *API) handleStatic(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return
	}
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		http.Error(w, "静态资源不可用", http.StatusInternalServerError)
		return
	}

	p := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if p == "." || p == "" {
		p = "index.html"
	}

	// 前端资源不缓存，避免升级后仍加载旧版本
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	// 明确告诉 CDN 不要缓存：CF 等会改写上面的 Cache-Control，但认这两个头
	w.Header().Set("CDN-Cache-Control", "no-store")
	w.Header().Set("Cloudflare-CDN-Cache-Control", "no-store")

	data, err := fs.ReadFile(sub, p)
	if err != nil {
		// SPA 回退
		data, err = fs.ReadFile(sub, "index.html")
		if err != nil {
			http.Error(w, "静态资源不可用", http.StatusInternalServerError)
			return
		}
		p = "index.html"
	}

	switch {
	case p == "index.html":
		// 把资源引用里的占位符换成当前版本号
		data = []byte(strings.ReplaceAll(string(data), "__VER__", assetVersion))
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
	case strings.HasSuffix(p, ".js"):
		data = rewriteJSImports(data, assetVersion)
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	case strings.HasSuffix(p, ".css"):
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	default:
		// 图片 / 字体 / manifest 等交给 ServeFileFS（保留 Range 与 MIME 推断）
		http.ServeFileFS(w, r, sub, p)
		return
	}

	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	_, _ = w.Write(data)
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

// requireMethod 统一方法校验
func requireMethod(w http.ResponseWriter, r *http.Request, method string) bool {
	if r.Method != method {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"message": "方法不允许"})
		return false
	}
	return true
}

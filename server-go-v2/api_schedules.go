package main

// 定时任务 CRUD 与立即执行

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
)

// scheduleBody 定时任务请求体
type scheduleBody struct {
	ID      int64           `json:"id"`
	Name    string          `json:"name"`
	IMEI    string          `json:"imei"`
	Task    string          `json:"task"`
	Params  json.RawMessage `json:"params"`
	Spec    json.RawMessage `json:"spec"`
	Enabled *bool           `json:"enabled"`
}

// normalizeScheduleParams 参数归一化：空 / null / {} → "{}"
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

// handleSchedules GET 分页返回定时任务（每页 5 条）
func (api *API) handleSchedules(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
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

func (api *API) handleAddSchedule(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	body, params, err := parseScheduleBody(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": err.Error()})
		return
	}
	enabled := body.Enabled == nil || *body.Enabled
	sc := Schedule{
		Name: body.Name, IMEI: body.IMEI, Task: body.Task,
		Params: params, Spec: body.Spec, Enabled: enabled,
	}
	id, err := api.app.db.addSchedule(sc)
	if err != nil {
		log.Printf("添加定时任务失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "添加定时任务失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "定时任务添加成功", "id": id})
}

func (api *API) handleUpdateSchedule(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	body, params, err := parseScheduleBody(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": err.Error()})
		return
	}
	if body.ID <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "缺少任务 ID"})
		return
	}
	if _, err := api.app.db.getSchedule(body.ID); err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"success": false, "message": "定时任务不存在"})
		return
	}
	enabled := body.Enabled == nil || *body.Enabled
	sc := Schedule{
		ID: body.ID, Name: body.Name, IMEI: body.IMEI, Task: body.Task,
		Params: params, Spec: body.Spec, Enabled: enabled,
	}
	if err := api.app.db.updateSchedule(sc); err != nil {
		log.Printf("更新定时任务失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "更新定时任务失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "定时任务已更新"})
}

func (api *API) handleToggleSchedule(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "状态已更新"})
}

func (api *API) handleDeleteSchedule(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "删除成功"})
}

// handleRunSchedule 立即执行一次（设备离线时明确报错）
func (api *API) handleRunSchedule(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
		writeJSON(w, http.StatusOK, map[string]any{"success": false, "message": "设备当前离线"})
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
		writeJSON(w, http.StatusOK, map[string]any{"success": false, "message": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "result": result})
}

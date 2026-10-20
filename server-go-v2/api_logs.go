package main

// 日志：设备上报日志 + 服务端运行日志

import (
	"log"
	"net/http"
	"strconv"
)

// handleLogs 设备上报日志（online / telemetry / call_record / sms_record / result …）
func (api *API) handleLogs(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
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

// handleClearLogs 清理设备日志：days>0 删除 days 天前，days<=0 删除全部
func (api *API) handleClearLogs(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var body struct {
		Days int `json:"days"`
	}
	if err := decodeJSON(r, &body); err != nil && err.Error() != "EOF" {
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
		msg = "已清理旧设备日志"
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": msg, "deleted": n})
}

// ---------------- 服务端运行日志 ----------------

// handleServerLogs 返回内存环形缓冲中的服务端日志
func (api *API) handleServerLogs(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	if api.logs == nil {
		writeJSON(w, http.StatusOK, map[string]any{"lines": []ServerLogEntry{}, "total": 0})
		return
	}
	level := r.URL.Query().Get("level")
	keyword := r.URL.Query().Get("keyword")
	limit := 300
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 {
		limit = v
	}
	lines := api.logs.Snapshot(level, keyword, limit)
	writeJSON(w, http.StatusOK, map[string]any{"lines": lines, "total": api.logs.Len()})
}

// handleClearServerLogs 清空服务端日志缓冲
func (api *API) handleClearServerLogs(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	if api.logs != nil {
		api.logs.Clear()
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "日志已清空"})
}

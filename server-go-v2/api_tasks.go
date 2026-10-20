package main

// 任务执行与任务记录

import (
	"log"
	"net/http"
	"strconv"
)

// handleExecuteTask 下发任务：imei + task + 其余字段作为参数透传
func (api *API) handleExecuteTask(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
	delete(raw, "imei")
	delete(raw, "task")

	result, err := api.app.ExecuteTask(imei, task, raw)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"success": false, "message": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "result": result})
}

// handleTasks 分页返回任务记录（每页 10 条）
func (api *API) handleTasks(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
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

// handleClearTasks 清理任务记录：days>0 删除 days 天前，days<=0 删除全部
func (api *API) handleClearTasks(w http.ResponseWriter, r *http.Request) {
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
	n, err := api.app.db.deleteTasks(body.Days)
	if err != nil {
		log.Printf("删除任务记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "删除成功", "deleted": n})
}

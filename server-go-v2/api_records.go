package main

// 通话记录 / 短信记录

import (
	"log"
	"net/http"
	"strconv"
)

// parseRecordFilter 解析分页与筛选参数（page/pageSize/from/to/imei）
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

// ---------------- 通话记录 ----------------

func (api *API) handleCallRecords(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	page, pageSize, from, to, imei := parseRecordFilter(r)
	f := RecordFilter{
		Page: page, PageSize: pageSize, From: from, To: to, IMEI: imei,
		Direction: r.URL.Query().Get("direction"),
		Keyword:   r.URL.Query().Get("keyword"),
	}
	list, err := api.app.db.callRecords(f)
	if err != nil {
		log.Printf("查询通话记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询通话记录失败"})
		return
	}
	total, err := api.app.db.countCallRecords(f)
	if err != nil {
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

func (api *API) handleClearCallRecords(w http.ResponseWriter, r *http.Request) {
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
	n, err := api.app.db.clearCallRecords(body.Days)
	if err != nil {
		log.Printf("清理通话记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "清理失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "清理成功", "deleted": n})
}

func (api *API) handleDeleteCallRecord(w http.ResponseWriter, r *http.Request) {
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
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少记录 id"})
		return
	}
	n, err := api.app.db.deleteCallRecord(body.ID)
	if err != nil {
		log.Printf("删除通话记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "删除成功", "deleted": n})
}

// ---------------- 短信记录 ----------------

func (api *API) handleSmsRecords(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	page, pageSize, from, to, imei := parseRecordFilter(r)
	f := RecordFilter{
		Page: page, PageSize: pageSize, From: from, To: to, IMEI: imei,
		Direction: r.URL.Query().Get("direction"),
		Keyword:   r.URL.Query().Get("keyword"),
	}
	list, err := api.app.db.smsRecords(f)
	if err != nil {
		log.Printf("查询短信记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询短信记录失败"})
		return
	}
	total, err := api.app.db.countSmsRecords(f)
	if err != nil {
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

func (api *API) handleClearSmsRecords(w http.ResponseWriter, r *http.Request) {
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
	n, err := api.app.db.clearSmsRecords(body.Days)
	if err != nil {
		log.Printf("清理短信记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "清理失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "清理成功", "deleted": n})
}

func (api *API) handleDeleteSmsRecord(w http.ResponseWriter, r *http.Request) {
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
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少记录 id"})
		return
	}
	n, err := api.app.db.deleteSmsRecord(body.ID)
	if err != nil {
		log.Printf("删除短信记录失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "删除失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "删除成功", "deleted": n})
}

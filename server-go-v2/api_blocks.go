package main

// 屏蔽规则：关键字屏蔽（短信）/ 号码屏蔽（来电）

import (
	"log"
	"net/http"
	"strconv"
	"strings"
)

// handleBlockRules 查询规则：不带分页参数时返回全部；带 page/size 时返回分页结果
func (api *API) handleBlockRules(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	q := r.URL.Query()
	ruleType := q.Get("type")
	if ruleType != "" && ruleType != "keyword" && ruleType != "number" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "type 必须为 keyword 或 number"})
		return
	}

	hits := api.app.db.blockRuleHitCounts(ruleType)
	fill := func(rules []BlockRule) []BlockRule {
		for i := range rules {
			rules[i].Hits = hits[rules[i].Value]
		}
		return rules
	}

	if q.Get("page") == "" && q.Get("size") == "" {
		rules, err := api.app.db.blockRules(ruleType)
		if err != nil {
			log.Printf("查询屏蔽规则失败: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询屏蔽规则失败"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"rules": fill(rules), "total": len(rules)})
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
	writeJSON(w, http.StatusOK, map[string]any{"rules": fill(rules), "total": total})
}

// handleAddBlockRule 新增规则
func (api *API) handleAddBlockRule(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
		writeJSON(w, http.StatusOK, map[string]any{"success": false, "duplicated": true, "message": "该规则已存在"})
		return
	}
	api.app.refreshBlockRules()
	api.app.publishBlockRulesAll()
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "新增成功"})
}

// handleUpdateBlockRule 更新规则（值 / 匹配方式 / 启用状态 / 备注）
func (api *API) handleUpdateBlockRule(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "更新成功"})
}

// handleDeleteBlockRule 删除规则
func (api *API) handleDeleteBlockRule(w http.ResponseWriter, r *http.Request) {
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
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "删除成功"})
}

// handleResetBlockRules 重置内置默认库
func (api *API) handleResetBlockRules(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	if err := api.app.db.resetBuiltinRules(); err != nil {
		log.Printf("重置内置屏蔽库失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "重置失败"})
		return
	}
	api.app.refreshBlockRules()
	api.app.publishBlockRulesAll()
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "已恢复内置默认库"})
}

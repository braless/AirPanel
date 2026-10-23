package main

import (
	"log"
	"net/http"
	"strconv"
	"strings"
)

// clientIP 获取客户端真实 IP（优先代理头 X-Forwarded-For / X-Real-IP，回退 RemoteAddr）
func clientIP(r *http.Request) string {
	if xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); xff != "" {
		if i := strings.IndexByte(xff, ','); i >= 0 {
			return strings.TrimSpace(xff[:i])
		}
		return xff
	}
	if xri := strings.TrimSpace(r.Header.Get("X-Real-IP")); xri != "" {
		return xri
	}
	host := r.RemoteAddr
	if i := strings.LastIndexByte(host, ':'); i >= 0 {
		// 仅当冒号后是端口（host:port IPv4 形式）时截取
		if strings.Count(host, ":") == 1 {
			return host[:i]
		}
		// IPv6 [addr]:port 形式
		if strings.HasPrefix(host, "[") {
			if j := strings.IndexByte(host, ']'); j >= 0 {
				return host[1:j]
			}
		}
	}
	return host
}

// handleLoginLogs 分页返回登录日志（支持按 IP / 用户名 / 客户端关键字过滤）
func (api *API) handleLoginLogs(w http.ResponseWriter, r *http.Request) {
	page := atoi(r.URL.Query().Get("page"), 1)
	pageSize := atoi(r.URL.Query().Get("pageSize"), 15)
	keyword := strings.TrimSpace(r.URL.Query().Get("keyword"))

	list, err := api.app.db.listLoginLogs(page, pageSize)
	if err != nil {
		log.Printf("查询登录日志失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询登录日志失败"})
		return
	}
	total, err := api.app.db.countLoginLogs()
	if err != nil {
		log.Printf("统计登录日志失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询登录日志失败"})
		return
	}
	if keyword != "" {
		filtered := make([]LoginLog, 0, len(list))
		for _, l := range list {
			if strings.Contains(l.IP, keyword) || strings.Contains(l.Username, keyword) || strings.Contains(l.UserAgent, keyword) || strings.Contains(l.Reason, keyword) {
				filtered = append(filtered, l)
			}
		}
		list = filtered
	}
	writeJSON(w, http.StatusOK, map[string]any{"logs": list, "total": total, "pageSize": pageSize})
}

// handleClearLoginLogs 清空登录日志
func (api *API) handleClearLoginLogs(w http.ResponseWriter, r *http.Request) {
	if err := api.app.db.clearLoginLogs(); err != nil {
		log.Printf("清空登录日志失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "清空登录日志失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "登录日志已清空"})
}

// atoi 字符串转整数，解析失败返回默认值
func atoi(s string, def int) int {
	if s == "" {
		return def
	}
	if n, err := strconv.Atoi(s); err == nil {
		return n
	}
	return def
}

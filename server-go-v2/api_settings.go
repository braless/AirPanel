package main

// 面板设置与通知

import (
	"log"
	"net/http"
	"strings"
)

// handleGetSettings 返回面板设置（密码哈希不回传）
func (api *API) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	writeJSON(w, http.StatusOK, api.app.getSettings())
}

// handleSaveSettings 保存通知 / 灯光 / WebDAV 设置（账号走 change-user-info）
func (api *API) handleSaveSettings(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var body struct {
		NotifyEnabled  bool                         `json:"notifyEnabled"`
		NotifyChannels []string                     `json:"notifyChannels"`
		NotifyConfig   map[string]map[string]string `json:"notifyConfig"`
		SMSEventLED    EventLED                     `json:"smsLed"`
		CallEventLED   EventLED                     `json:"callLed"`
		WebDAV         *WebDAVConfig                `json:"webdav"`
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
	if body.WebDAV != nil {
		s.WebDAV = *body.WebDAV
	}

	if err := api.app.saveSettings(s); err != nil {
		log.Printf("保存设置失败: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "保存设置失败"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "设置已保存"})
}

// handleNotifyChannels 返回支持的渠道定义（前端据此渲染配置表单）
func (api *API) handleNotifyChannels(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	writeJSON(w, http.StatusOK, notifyChannelDefs())
}

// handleTestNotify 用当前表单中的渠道与配置发送测试通知
func (api *API) handleTestNotify(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var body struct {
		NotifyChannels []string                     `json:"channels"`
		NotifyConfig   map[string]map[string]string `json:"config"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "请求体格式错误"})
		return
	}
	if len(body.NotifyChannels) == 0 {
		writeJSON(w, http.StatusOK, map[string]any{"success": false, "message": "请先选择至少一个通知渠道"})
		return
	}
	if body.NotifyConfig == nil {
		body.NotifyConfig = map[string]map[string]string{}
	}
	msg := "【测试通知】AirPanel v2 通知配置正常"
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
		writeJSON(w, http.StatusOK, map[string]any{
			"success": false,
			"message": "部分渠道发送失败: " + strings.Join(failed, "；"),
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "测试通知已发送"})
}

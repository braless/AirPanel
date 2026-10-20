package main

// 设备相关 API：列表、备注、删除、概览、续航配置、全局统计

import (
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// handleUserPool 返回全部设备
func (api *API) handleUserPool(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	devices, err := api.app.deviceList()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "查询设备失败"})
		return
	}
	writeJSON(w, http.StatusOK, devices)
}

// handleUpdateDeviceRemark 修改设备备注名
func (api *API) handleUpdateDeviceRemark(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "备注已保存"})
}

// handleDeleteDevice 删除设备（同时清理关联记录）
func (api *API) handleDeleteDevice(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
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
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "设备已删除"})
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

// estimateCurrentMa 估算当前电流（mA）：模块无电流采样，按充电状态与信号强度估算
func estimateCurrentMa(charging bool, rssi int, avgConfigured int) int {
	if avgConfigured > 0 {
		return avgConfigured
	}
	if charging {
		return 30
	}
	base := 60
	switch {
	case rssi == 0:
		return base
	case rssi < -105:
		return base + 40
	case rssi < -95:
		return base + 25
	case rssi < -85:
		return base + 10
	}
	return base
}

func (api *API) settingOr(key, def string) string {
	v, err := api.app.db.getSetting(key)
	if err != nil || v == "" {
		return def
	}
	return v
}

// handleDeviceOverview 设备概览：设备信息 + 在线时长 + 最新遥测 + 历史趋势 + 电量/续航
func (api *API) handleDeviceOverview(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	imei := strings.TrimSpace(r.URL.Query().Get("imei"))
	if imei == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "缺少参数: imei"})
		return
	}
	now := time.Now().Unix()

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

	writeJSON(w, http.StatusOK, map[string]any{
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

// handleSaveOverviewConfig 保存续航估算配置（电池容量 / 平均电流）
func (api *API) handleSaveOverviewConfig(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		BatteryMah   int `json:"batteryMah"`
		AvgCurrentMa int `json:"avgCurrentMa"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "参数格式错误"})
		return
	}
	if req.BatteryMah < 100 {
		req.BatteryMah = 1800
	}
	if req.AvgCurrentMa < 0 {
		req.AvgCurrentMa = 0
	}
	if err := api.app.db.setSetting("battery_mah", strconv.Itoa(req.BatteryMah)); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "保存失败: " + err.Error()})
		return
	}
	if err := api.app.db.setSetting("avg_current_ma", strconv.Itoa(req.AvgCurrentMa)); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"message": "保存失败: " + err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "message": "保存成功"})
}

// handleStatsSummary 概览页顶部统计：设备在线数、今日通话/短信/任务
func (api *API) handleStatsSummary(w http.ResponseWriter, r *http.Request) {
	if !requireMethod(w, r, http.MethodGet) {
		return
	}
	devices, _ := api.app.deviceList()
	online := 0
	for _, d := range devices {
		if d.Connected {
			online++
		}
	}

	now := time.Now()
	dayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).Unix()
	calls, _ := api.app.db.countCallRecords(RecordFilter{From: dayStart})
	sms, _ := api.app.db.countSmsRecords(RecordFilter{From: dayStart})
	tasks, okTasks, failTasks, _ := api.app.db.countTasksSince(dayStart)
	callIn, callOut, callMissed := api.app.db.countCallsSince(dayStart)
	smsIn, smsOut := api.app.db.countSmsSince(dayStart)

	writeJSON(w, http.StatusOK, map[string]any{
		"devices":     len(devices),
		"online":      online,
		"callsToday":  calls,
		"callIn":      callIn,
		"callOut":     callOut,
		"callMissed":  callMissed,
		"smsToday":    sms,
		"smsIn":       smsIn,
		"smsOut":      smsOut,
		"tasksToday":  tasks,
		"tasksOK":     okTasks,
		"tasksFailed": failTasks,
		"uptimeSec":   int64(time.Since(serverStartTime).Seconds()),
	})
}

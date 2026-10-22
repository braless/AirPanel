package main

// 面板设置：登录账号 / 离线通知，全部存储于 SQLite settings 表
// 账号信息从 config.json 迁移至数据库，后续登录/改密均走数据库

import (
	"encoding/json"
	"log"

	"golang.org/x/crypto/bcrypt"
)

// EventLED 事件灯光配置（来短信/来电话时设备灯光反馈）
type EventLED struct {
	Enabled  bool   `json:"enabled"`
	Color    string `json:"color"`    // off/red/green/blue/yellow/purple/cyan/white
	Blink    bool   `json:"blink"`    // 是否闪烁
	Duration int    `json:"duration"` // 持续毫秒，默认 5000
}

// WebDAVConfig WebDAV 存储配置（通话录音上传/浏览/播放）
type WebDAVConfig struct {
	URL      string `json:"url"`      // WebDAV 服务器根地址，如 https://dav.example.com
	Username string `json:"username"` // 账号
	Password string `json:"password"` // 密码
	Dir      string `json:"dir"`      // 录音目录（设备上传 + 列表浏览），如 通话录音
}

// BrandConfig 品牌配置（站点标题 / Logo URL / 管理员头像 URL）
type BrandConfig struct {
	Title  string `json:"title"`  // 站点标题，空表示使用默认 AirPanel
	Logo   string `json:"logo"`   // Logo 图片 URL：侧栏左上角、登录页 Logo、浏览器标签页图标共用
	Avatar string `json:"avatar"` // 管理员头像 URL：右上角与侧栏左下角头像共用
}

// Settings 面板设置（账号 / 离线通知 / 事件灯光 / WebDAV / 品牌）
type Settings struct {
	Username       string                       `json:"username"`
	Password       string                       `json:"-"` // bcrypt 哈希，不返回给前端
	NotifyEnabled  bool                         `json:"notifyEnabled"`  // 是否启用离线通知
	NotifyChannels []string                     `json:"notifyChannels"` // 启用的通知渠道
	NotifyConfig   map[string]map[string]string `json:"notifyConfig"`   // 各渠道配置项
	SMSEventLED    EventLED                     `json:"smsLed"`         // 来短信灯光
	CallEventLED   EventLED                     `json:"callLed"`        // 来电话灯光
	WebDAV         WebDAVConfig                 `json:"webdav"`         // WebDAV 存储
	Brand          BrandConfig                  `json:"brand"`          // 品牌（标题 / Logo）
}

// settings 表的键名
const (
	settingUsername       = "username"
	settingPassword       = "password"
	settingNotifyEnabled  = "notify_enabled"
	settingNotifyChannels = "notify_channels"
	settingNotifyConfig   = "notify_config"
	settingSMSEventLED    = "sms_led"
	settingCallEventLED   = "call_led"
	settingWebDAV         = "webdav"
	settingBrand          = "brand"
)

// defaultOfflineTimeout 固定离线判定超时（秒）= 5 分钟，不支持远程修改。
// 设备心跳默认 2 分钟，允许连续漏 2 次心跳才判离线，避免网络抖动误报。
const defaultOfflineTimeout = 300

// powersaveOfflineTimeout 省电模式（半在线）下应用心跳已拉长（默认 10 分钟），
// 离线判定阈值相应放宽（秒）= 30 分钟，避免省电期间被误判离线
const powersaveOfflineTimeout = 1800

func boolToStr(b bool) string {
	if b {
		return "1"
	}
	return "0"
}

// ---------------- DB 存取 ----------------

// loadSettings 从数据库读取设置（不存在则返回默认值）
func (d *DB) loadSettings() (*Settings, error) {
	all, err := d.allSettings()
	if err != nil {
		return nil, err
	}
	s := &Settings{
		Username:      all[settingUsername],
		Password:      all[settingPassword],
		NotifyEnabled: all[settingNotifyEnabled] == "1",
		NotifyConfig:  map[string]map[string]string{},
	}
	if s.Username == "" {
		s.Username = "admin"
	}
	if v := all[settingNotifyChannels]; v != "" {
		_ = json.Unmarshal([]byte(v), &s.NotifyChannels)
	}
	if v := all[settingNotifyConfig]; v != "" {
		_ = json.Unmarshal([]byte(v), &s.NotifyConfig)
	}
	if s.NotifyConfig == nil {
		s.NotifyConfig = map[string]map[string]string{}
	}
	if v := all[settingSMSEventLED]; v != "" {
		_ = json.Unmarshal([]byte(v), &s.SMSEventLED)
	}
	if v := all[settingCallEventLED]; v != "" {
		_ = json.Unmarshal([]byte(v), &s.CallEventLED)
	}
	if s.SMSEventLED.Duration == 0 {
		s.SMSEventLED.Duration = 5000
	}
	if s.CallEventLED.Duration == 0 {
		s.CallEventLED.Duration = 5000
	}
	if v := all[settingWebDAV]; v != "" {
		_ = json.Unmarshal([]byte(v), &s.WebDAV)
	}
	if s.WebDAV.Dir == "" {
		s.WebDAV.Dir = "通话录音"
	}
	if v := all[settingBrand]; v != "" {
		_ = json.Unmarshal([]byte(v), &s.Brand)
	}
	return s, nil
}

// saveSettings 将设置整体写入数据库
func (d *DB) saveSettings(s *Settings) error {
	if s.Username == "" {
		s.Username = "admin"
	}
	if s.NotifyConfig == nil {
		s.NotifyConfig = map[string]map[string]string{}
	}
	ch, _ := json.Marshal(s.NotifyChannels)
	if len(ch) == 0 {
		ch = []byte("[]")
	}
	cf, _ := json.Marshal(s.NotifyConfig)
	if len(cf) == 0 {
		cf = []byte("{}")
	}
	sled, _ := json.Marshal(s.SMSEventLED)
	cled, _ := json.Marshal(s.CallEventLED)
	wd, _ := json.Marshal(s.WebDAV)
	br, _ := json.Marshal(s.Brand)
	pairs := [][2]string{
		{settingUsername, s.Username},
		{settingPassword, s.Password},
		{settingNotifyEnabled, boolToStr(s.NotifyEnabled)},
		{settingNotifyChannels, string(ch)},
		{settingNotifyConfig, string(cf)},
		{settingSMSEventLED, string(sled)},
		{settingCallEventLED, string(cled)},
		{settingWebDAV, string(wd)},
		{settingBrand, string(br)},
	}
	for _, kv := range pairs {
		if err := d.setSetting(kv[0], kv[1]); err != nil {
			return err
		}
	}
	return nil
}

// ---------------- App 缓存与辅助 ----------------

// initSettings 启动时加载设置；若数据库尚无账号（首次升级），从 config.json 迁移账号并写入默认值
func (a *App) initSettings() {
	s, err := a.db.loadSettings()
	if err != nil {
		log.Printf("读取设置失败: %v", err)
		s, _ = a.db.loadSettings()
	}
	if s.Password == "" {
		s.Username = a.cfg.User.Username
		if s.Username == "" {
			s.Username = "admin"
		}
		s.Password = a.cfg.User.Password
		if s.Password == "" {
			// 兜底：生成默认密码（admin123）哈希，保证可登录
			if h, herr := bcrypt.GenerateFromPassword([]byte("admin123"), 10); herr == nil {
				s.Password = string(h)
			}
		}
		s.NotifyEnabled = false
		s.NotifyChannels = []string{}
		if err := a.db.saveSettings(s); err != nil {
			log.Printf("初始化设置失败: %v", err)
		}
		log.Printf("已将账号信息迁移至数据库（后续账号/通知设置均存储于数据库）")
	}
	a.settingsMu.Lock()
	a.settings = s
	a.settingsMu.Unlock()
}

// getSettings 返回设置的深拷贝（含密码哈希，仅供服务端使用）
func (a *App) getSettings() *Settings {
	a.settingsMu.RLock()
	defer a.settingsMu.RUnlock()
	if a.settings == nil {
		return &Settings{
			Username: "admin", NotifyEnabled: false,
			NotifyConfig: map[string]map[string]string{},
		}
	}
	s := *a.settings
	s.NotifyChannels = append([]string{}, a.settings.NotifyChannels...)
	nc := make(map[string]map[string]string, len(a.settings.NotifyConfig))
	for k, v := range a.settings.NotifyConfig {
		mv := make(map[string]string, len(v))
		for kk, vv := range v {
			mv[kk] = vv
		}
		nc[k] = mv
	}
	s.NotifyConfig = nc
	return &s
}

// saveSettings 保存设置并更新内存缓存
func (a *App) saveSettings(s *Settings) error {
	if err := a.db.saveSettings(s); err != nil {
		return err
	}
	a.settingsMu.Lock()
	a.settings = s
	a.settingsMu.Unlock()
	return nil
}

// offlineTimeout 返回固定离线判定超时（秒），供巡检协程使用
func (a *App) offlineTimeout() int {
	return defaultOfflineTimeout
}

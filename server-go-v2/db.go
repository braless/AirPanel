package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

// DB 封装 SQLite 数据访问（设备、任务记录）
type DB struct {
	sql *sql.DB
}

func openDB(path string) (*DB, error) {
	sqlDB, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	sqlDB.SetMaxOpenConns(1) // SQLite 单写者
	if err := sqlDB.Ping(); err != nil {
		return nil, err
	}
	db := &DB{sql: sqlDB}
	if err := db.init(); err != nil {
		return nil, err
	}
	return db, nil
}

func (d *DB) init() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS devices (
			imei       TEXT PRIMARY KEY,
			phone      TEXT DEFAULT '',
			name       TEXT DEFAULT '',
			connected  INTEGER DEFAULT 0,
			last_seen  INTEGER DEFAULT 0,
			first_seen INTEGER DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS tasks (
			id          INTEGER PRIMARY KEY AUTOINCREMENT,
			task_id     TEXT DEFAULT '',
			imei        TEXT DEFAULT '',
			task        TEXT DEFAULT '',
			params      TEXT DEFAULT '',
			result      TEXT DEFAULT '',
			error       TEXT DEFAULT '',
			status      TEXT DEFAULT 'pending',
			created_at  INTEGER DEFAULT 0,
			finished_at INTEGER DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS schedules (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			name          TEXT DEFAULT '',
			imei          TEXT NOT NULL,
			task          TEXT NOT NULL,
			params        TEXT DEFAULT '{}',
			spec          TEXT NOT NULL,
			enabled       INTEGER DEFAULT 1,
			created_at    INTEGER DEFAULT 0,
			last_executed INTEGER DEFAULT 0,
			last_check    INTEGER DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS settings (
			key        TEXT PRIMARY KEY,
			value      TEXT NOT NULL DEFAULT '',
			updated_at INTEGER DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS call_records (
			id          INTEGER PRIMARY KEY AUTOINCREMENT,
			imei        TEXT DEFAULT '',
			number      TEXT DEFAULT '',
			direction   TEXT DEFAULT 'incoming',  -- incoming 来电 / outgoing 去电
			status      TEXT DEFAULT '',          -- connected 接通 / missed 未接 / rejected 拒接 / no_answer 未应答 / cancelled 取消
			duration    INTEGER DEFAULT 0,        -- 通话时长（秒）
			started_at  INTEGER DEFAULT 0,        -- 来电/拨出时间（Unix 秒）
			connected_at INTEGER DEFAULT 0,       -- 接通时间（Unix 秒）
			ended_at    INTEGER DEFAULT 0,        -- 挂断时间（Unix 秒）
			reason      TEXT DEFAULT '',          -- 挂断原因（NO CARRIER / BUSY / CHUP 等）
			notify_status TEXT DEFAULT '',        -- 设备端通知状态: '' 未通知 / queued 排队 / sent 已发送 / failed 失败 / blocked 被屏蔽
			spam        INTEGER DEFAULT 0,        -- 0 正常 / 1 疑似垃圾电话
			spam_rule   TEXT DEFAULT ''           -- 命中屏蔽规则内容（如命中号码/关键字）
		)`,
		`CREATE TABLE IF NOT EXISTS sms_records (
			id         INTEGER PRIMARY KEY AUTOINCREMENT,
			imei       TEXT DEFAULT '',
			number     TEXT DEFAULT '',           -- 对端号码
			direction  TEXT DEFAULT 'in',         -- in 接收 / out 发送
			content    TEXT DEFAULT '',
			created_at INTEGER DEFAULT 0,         -- 接收/发送时间（Unix 秒）
			notify_status TEXT DEFAULT '',        -- 设备端通知状态: '' 未通知 / queued 排队 / sent 已发送 / failed 失败 / blocked 被屏蔽
			spam       INTEGER DEFAULT 0,         -- 0 正常 / 1 疑似垃圾短信
			spam_rule  TEXT DEFAULT ''            -- 命中屏蔽规则内容（如命中号码/关键字）
		)`,
		`CREATE TABLE IF NOT EXISTS block_rules (
			id         INTEGER PRIMARY KEY AUTOINCREMENT,
			rule_type  TEXT NOT NULL,             -- keyword 关键字屏蔽 / number 号码屏蔽
			value      TEXT NOT NULL,             -- 关键字或号码（号码支持前缀，如 1068 / 95）
			match_mode TEXT DEFAULT 'contains',   -- keyword: contains; number: prefix / exact
			source     TEXT DEFAULT 'user',       -- user 用户自定义 / builtin 内置默认库
			enabled    INTEGER DEFAULT 1,
			note       TEXT DEFAULT '',
			created_at INTEGER DEFAULT 0,
			updated_at INTEGER DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS device_logs (
			id          INTEGER PRIMARY KEY AUTOINCREMENT,
			imei        TEXT DEFAULT '',             -- 设备 IMEI
			topic       TEXT DEFAULT '',             -- 上报主题（device/{imei}/{type}）
			log_type    TEXT DEFAULT '',             -- 上报类型: online / telemetry / call_record / sms_record / result / powersave / notify_result
			payload     TEXT DEFAULT '',             -- 原始上报 JSON
			created_at  INTEGER DEFAULT 0            -- 服务端接收时间（Unix 秒）
		)`,
		`CREATE TABLE IF NOT EXISTS telemetry (
			id          INTEGER PRIMARY KEY AUTOINCREMENT,
			imei        TEXT DEFAULT '',
			voltage     INTEGER DEFAULT 0,          -- 电池电压 mV
			temperature REAL DEFAULT 0,             -- 温度 ℃
			rssi        INTEGER DEFAULT 0,          -- 信号强度 dBm
			rsrp        INTEGER DEFAULT 0,          -- 参考信号接收功率 dBm
			csq         INTEGER DEFAULT 0,          -- 信号格 0-31
			net_mode    TEXT DEFAULT '',            -- LTE / GSM
			operator    TEXT DEFAULT '',            -- 运营商
			number      TEXT DEFAULT '',            -- 本机号码
			imsi        TEXT DEFAULT '',
			sim_slot    TEXT DEFAULT '',
			iccid       TEXT DEFAULT '',
			version     TEXT DEFAULT '',            -- 固件版本
			model       TEXT DEFAULT '',            -- 模块型号
			sn          TEXT DEFAULT '',
			vbus        INTEGER DEFAULT 0,          -- 是否充电
			work_time   INTEGER DEFAULT 0,          -- 设备开机时长（秒）
			created_at  INTEGER DEFAULT 0
		)`,
	}
	for _, s := range stmts {
		if _, err := d.sql.Exec(s); err != nil {
			return err
		}
	}
	// 旧库平滑迁移：为已有表补充新列（SQLite 不支持 IF NOT EXISTS 加列，逐列检测）
	migrations := []struct{ table, column, ddl string }{
		{"call_records", "notify_status", `ALTER TABLE call_records ADD COLUMN notify_status TEXT DEFAULT ''`},
		{"call_records", "spam", `ALTER TABLE call_records ADD COLUMN spam INTEGER DEFAULT 0`},
		{"call_records", "spam_rule", `ALTER TABLE call_records ADD COLUMN spam_rule TEXT DEFAULT ''`},
		{"sms_records", "notify_status", `ALTER TABLE sms_records ADD COLUMN notify_status TEXT DEFAULT ''`},
		{"sms_records", "spam", `ALTER TABLE sms_records ADD COLUMN spam INTEGER DEFAULT 0`},
		{"sms_records", "spam_rule", `ALTER TABLE sms_records ADD COLUMN spam_rule TEXT DEFAULT ''`},
	}
	for _, m := range migrations {
		if !d.hasColumn(m.table, m.column) {
			if _, err := d.sql.Exec(m.ddl); err != nil {
				return fmt.Errorf("迁移 %s.%s 失败: %w", m.table, m.column, err)
			}
		}
	}
	return nil
}

// hasColumn 检测表是否已存在指定列
func (d *DB) hasColumn(table, column string) bool {
	rows, err := d.sql.Query(`PRAGMA table_info(` + table + `)`)
	if err != nil {
		return false
	}
	defer rows.Close()
	for rows.Next() {
		var cid int
		var name, ctype string
		var notnull, pk int
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notnull, &dflt, &pk); err != nil {
			return false
		}
		if name == column {
			return true
		}
	}
	return false
}

// resetAllOffline 服务启动时将全部设备标记为离线，
// 清理上次运行残留的在线状态（服务异常退出/升级重启时不会触发 OnDisconnect）
func (d *DB) resetAllOffline() error {
	_, err := d.sql.Exec(`UPDATE devices SET connected = 0`)
	return err
}

// ---------------- 设置（settings 表，键值对） ----------------

// getSetting 读取设置项，不存在时返回空串
func (d *DB) getSetting(key string) (string, error) {
	var value string
	err := d.sql.QueryRow(`SELECT value FROM settings WHERE key = ?`, key).Scan(&value)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return value, err
}

// setSetting 写入设置项（存在则覆盖）
func (d *DB) setSetting(key, value string) error {
	now := time.Now().Unix()
	_, err := d.sql.Exec(
		`INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
		 ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?`,
		key, value, now, value, now,
	)
	return err
}

// allSettings 读取全部设置项
func (d *DB) allSettings() (map[string]string, error) {
	rows, err := d.sql.Query(`SELECT key, value FROM settings`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		out[k] = v
	}
	return out, rows.Err()
}

// getDeviceName 查询设备备注名（可能为空串）
func (d *DB) getDeviceName(imei string) string {
	var name string
	_ = d.sql.QueryRow(`SELECT name FROM devices WHERE imei = ?`, imei).Scan(&name)
	return name
}

// upsertDevice 写入或更新设备记录（在线状态 + 最近活跃时间）
func (d *DB) upsertDevice(imei, phone string, connected bool, lastSeen int64) error {
	_, err := d.sql.Exec(
		`INSERT INTO devices (imei, phone, connected, last_seen, first_seen)
		 VALUES (?, ?, ?, ?, ?)
		 ON CONFLICT(imei) DO UPDATE SET
		   phone = CASE WHEN ? <> '' THEN ? ELSE phone END,
		   connected = ?,
		   last_seen = ?`,
		imei, phone, b2i(connected), lastSeen, lastSeen,
		phone, phone, b2i(connected), lastSeen,
	)
	return err
}

// listDevices 返回设备列表
func (d *DB) listDevices() ([]Device, error) {
	rows, err := d.sql.Query(`SELECT imei, phone, name, connected, last_seen, first_seen FROM devices`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out = make([]Device, 0)
	for rows.Next() {
		var dev Device
		var connected int
		if err := rows.Scan(&dev.IMEI, &dev.Phone, &dev.Name, &connected, &dev.LastSeen, &dev.FirstSeen); err != nil {
			return nil, err
		}
		dev.Connected = connected != 0
		out = append(out, dev)
	}
	return out, rows.Err()
}

// updateDeviceName 设置设备备注（name，空串表示清除）
func (d *DB) updateDeviceName(imei, name string) error {
	_, err := d.sql.Exec(`UPDATE devices SET name = ? WHERE imei = ?`, name, imei)
	return err
}

// deleteDevice 删除设备记录
func (d *DB) deleteDevice(imei string) error {
	_, err := d.sql.Exec(`DELETE FROM devices WHERE imei = ?`, imei)
	return err
}

// markDeviceOfflineExisting 仅将已存在的设备更新为离线（不新增记录）
// 用于设备被删除后的断开回调：避免 upsert 把已删除的设备重新写回数据库
func (d *DB) markDeviceOfflineExisting(imei string, lastSeen int64) error {
	_, err := d.sql.Exec(`UPDATE devices SET connected = 0, last_seen = ? WHERE imei = ?`, lastSeen, imei)
	return err
}

// recordTask 记录任务执行记录
func (d *DB) recordTask(rec TaskRecord) error {
	_, err := d.sql.Exec(
		`INSERT INTO tasks (task_id, imei, task, params, result, error, status, created_at, finished_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		rec.TaskID, rec.IMEI, rec.Task, rec.Params, rec.Result, rec.Error, rec.Status,
		rec.CreatedAt, rec.FinishedAt,
	)
	return err
}

// recentTasks 返回最近任务记录（关联设备备注名，用于展示），按 id 倒序分页
func (d *DB) recentTasks(page, pageSize int) ([]TaskRecord, error) {
	if page < 1 {
		page = 1
	}
	rows, err := d.sql.Query(
		`SELECT t.task_id, t.imei, t.task, t.params, t.result, t.error, t.status, t.created_at, t.finished_at, COALESCE(d.name, '')
		 FROM tasks t LEFT JOIN devices d ON d.imei = t.imei
		 ORDER BY t.id DESC LIMIT ? OFFSET ?`, pageSize, (page-1)*pageSize)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out = make([]TaskRecord, 0)
	for rows.Next() {
		var rec TaskRecord
		if err := rows.Scan(&rec.TaskID, &rec.IMEI, &rec.Task, &rec.Params, &rec.Result,
			&rec.Error, &rec.Status, &rec.CreatedAt, &rec.FinishedAt, &rec.DeviceName); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}

// countTasks 统计任务记录总数
func (d *DB) countTasks() (int64, error) {
	var n int64
	err := d.sql.QueryRow(`SELECT COUNT(*) FROM tasks`).Scan(&n)
	return n, err
}

// countTasksSince 统计某时刻之后的任务数，并按状态拆分（done / 其他视为失败）
func (d *DB) countTasksSince(since int64) (total, ok, failed int64, err error) {
	err = d.sql.QueryRow(
		`SELECT COUNT(*),
		        COALESCE(SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END), 0)
		 FROM tasks WHERE created_at >= ?`, since).Scan(&total, &ok)
	if err != nil {
		return
	}
	failed = total - ok
	return
}

// countCallsSince 统计某时刻之后的通话分布：呼入 / 呼出 / 未接类
func (d *DB) countCallsSince(since int64) (in, out, missed int64) {
	_ = d.sql.QueryRow(
		`SELECT
		   COALESCE(SUM(CASE WHEN direction = 'incoming' THEN 1 ELSE 0 END), 0),
		   COALESCE(SUM(CASE WHEN direction = 'outgoing' THEN 1 ELSE 0 END), 0),
		   COALESCE(SUM(CASE WHEN status IN ('missed','rejected','no_answer','cancelled') THEN 1 ELSE 0 END), 0)
		 FROM call_records WHERE started_at >= ?`, since).Scan(&in, &out, &missed)
	return
}

// countSmsSince 统计某时刻之后的短信分布：接收 / 发送
func (d *DB) countSmsSince(since int64) (in, out int64) {
	_ = d.sql.QueryRow(
		`SELECT
		   COALESCE(SUM(CASE WHEN direction = 'in' THEN 1 ELSE 0 END), 0),
		   COALESCE(SUM(CASE WHEN direction = 'out' THEN 1 ELSE 0 END), 0)
		 FROM sms_records WHERE created_at >= ?`, since).Scan(&in, &out)
	return
}

// deleteTasks 删除任务记录。days > 0 时只删除距今超过 days 天的旧日志（保留近 days 天）；days <= 0 时删除全部。
// 返回被删除的记录条数。
func (d *DB) deleteTasks(days int) (int64, error) {
	if days > 0 {
		cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).Unix()
		res, err := d.sql.Exec(`DELETE FROM tasks WHERE created_at < ?`, cutoff)
		if err != nil {
			return 0, err
		}
		return res.RowsAffected()
	}
	res, err := d.sql.Exec(`DELETE FROM tasks`)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

// ---------------- 定时任务 ----------------

// addSchedule 新增定时任务，返回任务 ID
func (d *DB) addSchedule(sc Schedule) (int64, error) {
	now := time.Now().Unix()
	res, err := d.sql.Exec(
		`INSERT INTO schedules (name, imei, task, params, spec, enabled, created_at, last_executed, last_check)
		 VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)`,
		sc.Name, sc.IMEI, sc.Task, sc.Params, sc.Spec, b2i(sc.Enabled), now, now,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// updateSchedule 编辑定时任务（保留执行历史字段）
func (d *DB) updateSchedule(sc Schedule) error {
	_, err := d.sql.Exec(
		`UPDATE schedules SET name = ?, imei = ?, task = ?, params = ?, spec = ?, enabled = ? WHERE id = ?`,
		sc.Name, sc.IMEI, sc.Task, sc.Params, sc.Spec, b2i(sc.Enabled), sc.ID,
	)
	return err
}

// setScheduleEnabled 启用/停用定时任务
func (d *DB) setScheduleEnabled(id int64, enabled bool) error {
	_, err := d.sql.Exec(`UPDATE schedules SET enabled = ? WHERE id = ?`, b2i(enabled), id)
	return err
}

// deleteSchedule 删除定时任务
func (d *DB) deleteSchedule(id int64) error {
	_, err := d.sql.Exec(`DELETE FROM schedules WHERE id = ?`, id)
	return err
}

// getSchedule 按 ID 查询单个定时任务
func (d *DB) getSchedule(id int64) (*Schedule, error) {
	row := d.sql.QueryRow(
		`SELECT id, name, imei, task, params, spec, enabled, created_at, last_executed, last_check FROM schedules WHERE id = ?`, id)
	var sc Schedule
	var enabled int
	var spec string
	if err := row.Scan(&sc.ID, &sc.Name, &sc.IMEI, &sc.Task, &sc.Params, &spec, &enabled, &sc.CreatedAt, &sc.LastExecuted, &sc.LastCheck); err != nil {
		return nil, err
	}
	sc.Spec = json.RawMessage(spec)
	sc.Enabled = enabled != 0
	return &sc, nil
}

// listSchedules 返回全部定时任务（关联设备备注名，按 id 倒序），调度器全量扫描使用
func (d *DB) listSchedules() ([]Schedule, error) {
	rows, err := d.sql.Query(
		`SELECT s.id, s.name, s.imei, s.task, s.params, s.spec, s.enabled, s.created_at, s.last_executed, s.last_check, COALESCE(d.name, '')
		 FROM schedules s LEFT JOIN devices d ON d.imei = s.imei
		 ORDER BY s.id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out = make([]Schedule, 0)
	for rows.Next() {
		var sc Schedule
		var enabled int
		var spec string
		if err := rows.Scan(&sc.ID, &sc.Name, &sc.IMEI, &sc.Task, &sc.Params, &spec,
			&enabled, &sc.CreatedAt, &sc.LastExecuted, &sc.LastCheck, &sc.DeviceName); err != nil {
			return nil, err
		}
		sc.Spec = json.RawMessage(spec)
		sc.Enabled = enabled != 0
		out = append(out, sc)
	}
	return out, rows.Err()
}

// listSchedulesPage 分页返回定时任务（每页默认 5 条）
func (d *DB) listSchedulesPage(page, pageSize int) ([]Schedule, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 5
	}
	rows, err := d.sql.Query(
		`SELECT s.id, s.name, s.imei, s.task, s.params, s.spec, s.enabled, s.created_at, s.last_executed, s.last_check, COALESCE(d.name, '')
		 FROM schedules s LEFT JOIN devices d ON d.imei = s.imei
		 ORDER BY s.id DESC LIMIT ? OFFSET ?`, pageSize, (page-1)*pageSize)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out = make([]Schedule, 0)
	for rows.Next() {
		var sc Schedule
		var enabled int
		var spec string
		if err := rows.Scan(&sc.ID, &sc.Name, &sc.IMEI, &sc.Task, &sc.Params, &spec,
			&enabled, &sc.CreatedAt, &sc.LastExecuted, &sc.LastCheck, &sc.DeviceName); err != nil {
			return nil, err
		}
		sc.Spec = json.RawMessage(spec)
		sc.Enabled = enabled != 0
		out = append(out, sc)
	}
	return out, rows.Err()
}

// countSchedules 统计定时任务总数
func (d *DB) countSchedules() (int64, error) {
	var n int64
	err := d.sql.QueryRow(`SELECT COUNT(*) FROM schedules`).Scan(&n)
	return n, err
}

// markScheduleProcessed 记录一次周期判定：executed=true 表示已下发（同时推进 last_executed），
// false 表示设备离线被跳过（仅推进 last_check，防止同一周期重复判定）
func (d *DB) markScheduleProcessed(id int64, executed bool) error {
	now := time.Now().Unix()
	if executed {
		_, err := d.sql.Exec(`UPDATE schedules SET last_check = ?, last_executed = ? WHERE id = ?`, now, now, id)
		return err
	}
	_, err := d.sql.Exec(`UPDATE schedules SET last_check = ? WHERE id = ?`, now, id)
	return err
}

// jsonBytes 用于日志/持久化的辅助
func jsonBytes(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

// ---------------- 通话记录 ----------------

// CallRecord 通话记录
type CallRecord struct {
	ID           int64  `json:"id"`
	IMEI         string `json:"imei"`
	DeviceName   string `json:"deviceName,omitempty"` // 关联设备备注名
	Number       string `json:"number"`
	Direction    string `json:"direction"`
	Status       string `json:"status"`
	Duration     int64  `json:"duration"`
	StartedAt    int64  `json:"startedAt"`
	ConnectedAt  int64  `json:"connectedAt"`
	EndedAt      int64  `json:"endedAt"`
	Reason       string `json:"reason"`
	NotifyStatus string `json:"notifyStatus"` // '' 未通知 / queued / sent / failed / blocked
	Spam         int    `json:"spam"`         // 0 正常 / 1 疑似垃圾电话
	SpamRule     string `json:"spamRule"`     // 命中屏蔽规则内容
}

// SmsRecord 短信记录
type SmsRecord struct {
	ID           int64  `json:"id"`
	IMEI         string `json:"imei"`
	DeviceName   string `json:"deviceName,omitempty"`
	Number       string `json:"number"`
	Direction    string `json:"direction"`
	Content      string `json:"content"`
	CreatedAt    int64  `json:"createdAt"`
	NotifyStatus string `json:"notifyStatus"` // '' 未通知 / queued / sent / failed / blocked
	Spam         int    `json:"spam"`         // 0 正常 / 1 疑似垃圾短信
	SpamRule     string `json:"spamRule"`     // 命中屏蔽规则内容
}

// ---------------- 遥测（概览） ----------------

// Telemetry 设备遥测（周期上报，用于概览页）
type Telemetry struct {
	ID          int64   `json:"id"`
	IMEI        string  `json:"imei"`
	Voltage     int     `json:"voltage"`     // 电池电压 mV
	Temperature float64 `json:"temperature"` // 温度 ℃
	RSSI        int     `json:"rssi"`        // 信号强度 dBm
	RSRP        int     `json:"rsrp"`        // 参考信号接收功率 dBm
	CSQ         int     `json:"csq"`         // 信号格 0-31
	NetMode     string  `json:"netMode"`
	Operator    string  `json:"operator"`
	Number      string  `json:"number"`
	IMSI        string  `json:"imsi"`
	SimSlot     string  `json:"simSlot"`
	ICCID       string  `json:"iccid"`
	Version     string  `json:"version"`
	Model       string  `json:"model"`
	SN          string  `json:"sn"`
	VBUS        bool    `json:"vbus"`     // 是否充电
	WorkTime    int64   `json:"workTime"` // 设备开机时长（秒）
	CreatedAt   int64   `json:"createdAt"`
}

// addTelemetry 写入一条遥测
func (d *DB) addTelemetry(rec Telemetry) error {
	_, err := d.sql.Exec(
		`INSERT INTO telemetry (imei, voltage, temperature, rssi, rsrp, csq, net_mode, operator, number, imsi, sim_slot, iccid, version, model, sn, vbus, work_time, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		rec.IMEI, rec.Voltage, rec.Temperature, rec.RSSI, rec.RSRP, rec.CSQ,
		rec.NetMode, rec.Operator, rec.Number, rec.IMSI, rec.SimSlot, rec.ICCID,
		rec.Version, rec.Model, rec.SN, b2i(rec.VBUS), rec.WorkTime, rec.CreatedAt,
	)
	return err
}

// latestTelemetry 返回指定设备最新一条遥测
func (d *DB) latestTelemetry(imei string) (*Telemetry, error) {
	row := d.sql.QueryRow(
		`SELECT id, imei, voltage, temperature, rssi, rsrp, csq, net_mode, operator, number, imsi, sim_slot, iccid, version, model, sn, vbus, work_time, created_at
		 FROM telemetry WHERE imei = ? ORDER BY id DESC LIMIT 1`, imei)
	var t Telemetry
	var vbus int
	if err := row.Scan(&t.ID, &t.IMEI, &t.Voltage, &t.Temperature, &t.RSSI, &t.RSRP, &t.CSQ,
		&t.NetMode, &t.Operator, &t.Number, &t.IMSI, &t.SimSlot, &t.ICCID, &t.Version,
		&t.Model, &t.SN, &vbus, &t.WorkTime, &t.CreatedAt); err != nil {
		return nil, err
	}
	t.VBUS = vbus != 0
	return &t, nil
}

// recentTelemetry 返回指定设备最近 limit 条遥测（时间正序，供趋势图）
func (d *DB) recentTelemetry(imei string, limit int) ([]Telemetry, error) {
	rows, err := d.sql.Query(
		`SELECT id, imei, voltage, temperature, rssi, rsrp, csq, net_mode, operator, number, imsi, sim_slot, iccid, version, model, sn, vbus, work_time, created_at
		 FROM telemetry WHERE imei = ? ORDER BY id DESC LIMIT ?`, imei, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out = make([]Telemetry, 0, limit)
	for rows.Next() {
		var t Telemetry
		var vbus int
		if err := rows.Scan(&t.ID, &t.IMEI, &t.Voltage, &t.Temperature, &t.RSSI, &t.RSRP, &t.CSQ,
			&t.NetMode, &t.Operator, &t.Number, &t.IMSI, &t.SimSlot, &t.ICCID, &t.Version,
			&t.Model, &t.SN, &vbus, &t.WorkTime, &t.CreatedAt); err != nil {
			return nil, err
		}
		t.VBUS = vbus != 0
		out = append(out, t)
	}
	// 倒序转为正序
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out, rows.Err()
}

// addCallRecord 写入一条通话记录
func (d *DB) addCallRecord(rec CallRecord) error {
	_, err := d.sql.Exec(
		`INSERT INTO call_records (imei, number, direction, status, duration, started_at, connected_at, ended_at, reason, notify_status, spam, spam_rule)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		rec.IMEI, rec.Number, rec.Direction, rec.Status, rec.Duration,
		rec.StartedAt, rec.ConnectedAt, rec.EndedAt, rec.Reason,
		rec.NotifyStatus, rec.Spam, rec.SpamRule,
	)
	return err
}

// addSmsRecord 写入一条短信记录
func (d *DB) addSmsRecord(rec SmsRecord) error {
	_, err := d.sql.Exec(
		`INSERT INTO sms_records (imei, number, direction, content, created_at, notify_status, spam, spam_rule)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		rec.IMEI, rec.Number, rec.Direction, rec.Content, rec.CreatedAt,
		rec.NotifyStatus, rec.Spam, rec.SpamRule,
	)
	return err
}

// updateCallNotifyStatus 更新通话记录的通知发送状态（按 imei+number+started_at 精确匹配，
// 未命中则回退到该 imei+number 最近一条 queued 记录，兼容设备端秒级时间漂移）
func (d *DB) updateCallNotifyStatus(imei, number string, startedAt int64, status string) error {
	res, err := d.sql.Exec(
		`UPDATE call_records SET notify_status = ? WHERE imei = ? AND number = ? AND started_at = ?`,
		status, imei, number, startedAt)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		return nil
	}
	_, err = d.sql.Exec(
		`UPDATE call_records SET notify_status = ?
		 WHERE id = (SELECT id FROM call_records WHERE imei = ? AND number = ? AND notify_status = 'queued' ORDER BY id DESC LIMIT 1)`,
		status, imei, number)
	return err
}

// updateSmsNotifyStatus 更新短信记录的通知发送状态（按 imei+number+created_at 精确匹配，
// 未命中则回退到该 imei+number 最近一条 queued 记录，兼容设备端秒级时间漂移）
func (d *DB) updateSmsNotifyStatus(imei, number string, createdAt int64, status string) error {
	res, err := d.sql.Exec(
		`UPDATE sms_records SET notify_status = ? WHERE imei = ? AND number = ? AND created_at = ?`,
		status, imei, number, createdAt)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		return nil
	}
	_, err = d.sql.Exec(
		`UPDATE sms_records SET notify_status = ?
		 WHERE id = (SELECT id FROM sms_records WHERE imei = ? AND number = ? AND notify_status = 'queued' ORDER BY id DESC LIMIT 1)`,
		status, imei, number)
	return err
}

// RecordFilter 通话/短信记录查询条件
type RecordFilter struct {
	Page      int
	PageSize  int
	From      int64
	To        int64
	IMEI      string
	Direction string // 通话: incoming/outgoing；短信: in/out
	Keyword   string // 号码或内容模糊匹配
}

func (f *RecordFilter) normalize() {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.PageSize < 1 {
		f.PageSize = 20
	}
	if f.PageSize > 200 {
		f.PageSize = 200
	}
}

// callRecords 分页查询通话记录
func (d *DB) callRecords(f RecordFilter) ([]CallRecord, error) {
	f.normalize()
	where, args := f.callWhere("c")
	rows, err := d.sql.Query(
		`SELECT c.id, c.imei, c.number, c.direction, c.status, c.duration,
		        c.started_at, c.connected_at, c.ended_at, c.reason,
		        c.notify_status, c.spam, c.spam_rule, COALESCE(d.name, '')
		 FROM call_records c LEFT JOIN devices d ON d.imei = c.imei
		 WHERE 1=1`+where+`
		 ORDER BY c.id DESC LIMIT ? OFFSET ?`,
		append(args, f.PageSize, (f.Page-1)*f.PageSize)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out = make([]CallRecord, 0)
	for rows.Next() {
		var rec CallRecord
		if err := rows.Scan(&rec.ID, &rec.IMEI, &rec.Number, &rec.Direction, &rec.Status,
			&rec.Duration, &rec.StartedAt, &rec.ConnectedAt, &rec.EndedAt, &rec.Reason,
			&rec.NotifyStatus, &rec.Spam, &rec.SpamRule, &rec.DeviceName); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}

func (f RecordFilter) callWhere(alias string) (string, []any) {
	where := ""
	args := []any{}
	if f.From > 0 {
		where += " AND " + alias + ".started_at >= ?"
		args = append(args, f.From)
	}
	if f.To > 0 {
		where += " AND " + alias + ".started_at <= ?"
		args = append(args, f.To)
	}
	if f.IMEI != "" {
		where += " AND " + alias + ".imei = ?"
		args = append(args, f.IMEI)
	}
	if f.Direction != "" {
		where += " AND " + alias + ".direction = ?"
		args = append(args, f.Direction)
	}
	if f.Keyword != "" {
		where += " AND (" + alias + ".number LIKE ? OR " + alias + ".reason LIKE ?)"
		kw := "%" + f.Keyword + "%"
		args = append(args, kw, kw)
	}
	return where, args
}

// countCallRecords 统计通话记录总数
func (d *DB) countCallRecords(f RecordFilter) (int64, error) {
	where, args := f.callWhere("call_records")
	var n int64
	err := d.sql.QueryRow(`SELECT COUNT(*) FROM call_records WHERE 1=1`+where, args...).Scan(&n)
	return n, err
}

// smsRecords 分页查询短信记录
func (d *DB) smsRecords(f RecordFilter) ([]SmsRecord, error) {
	f.normalize()
	where, args := f.smsWhere("s")
	rows, err := d.sql.Query(
		`SELECT s.id, s.imei, s.number, s.direction, s.content, s.created_at,
		        s.notify_status, s.spam, s.spam_rule, COALESCE(d.name, '')
		 FROM sms_records s LEFT JOIN devices d ON d.imei = s.imei
		 WHERE 1=1`+where+`
		 ORDER BY s.id DESC LIMIT ? OFFSET ?`,
		append(args, f.PageSize, (f.Page-1)*f.PageSize)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out = make([]SmsRecord, 0)
	for rows.Next() {
		var rec SmsRecord
		if err := rows.Scan(&rec.ID, &rec.IMEI, &rec.Number, &rec.Direction, &rec.Content,
			&rec.CreatedAt, &rec.NotifyStatus, &rec.Spam, &rec.SpamRule, &rec.DeviceName); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}

func (f RecordFilter) smsWhere(alias string) (string, []any) {
	where := ""
	args := []any{}
	if f.From > 0 {
		where += " AND " + alias + ".created_at >= ?"
		args = append(args, f.From)
	}
	if f.To > 0 {
		where += " AND " + alias + ".created_at <= ?"
		args = append(args, f.To)
	}
	if f.IMEI != "" {
		where += " AND " + alias + ".imei = ?"
		args = append(args, f.IMEI)
	}
	if f.Direction != "" {
		where += " AND " + alias + ".direction = ?"
		args = append(args, f.Direction)
	}
	if f.Keyword != "" {
		where += " AND (" + alias + ".number LIKE ? OR " + alias + ".content LIKE ?)"
		kw := "%" + f.Keyword + "%"
		args = append(args, kw, kw)
	}
	return where, args
}

// countSmsRecords 统计短信记录总数
func (d *DB) countSmsRecords(f RecordFilter) (int64, error) {
	where, args := f.smsWhere("sms_records")
	var n int64
	err := d.sql.QueryRow(`SELECT COUNT(*) FROM sms_records WHERE 1=1`+where, args...).Scan(&n)
	return n, err
}

// clearCallRecords 清理通话记录。days>0 删除距今超过 days 天的记录；days<=0 删除全部。
func (d *DB) clearCallRecords(days int) (int64, error) {
	if days > 0 {
		cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).Unix()
		res, err := d.sql.Exec(`DELETE FROM call_records WHERE started_at < ?`, cutoff)
		if err != nil {
			return 0, err
		}
		return res.RowsAffected()
	}
	res, err := d.sql.Exec(`DELETE FROM call_records`)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// deleteCallRecord 删除单条通话记录
func (d *DB) deleteCallRecord(id int64) (int64, error) {
	res, err := d.sql.Exec(`DELETE FROM call_records WHERE id = ?`, id)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// deleteSmsRecord 删除单条短信记录
func (d *DB) deleteSmsRecord(id int64) (int64, error) {
	res, err := d.sql.Exec(`DELETE FROM sms_records WHERE id = ?`, id)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// clearSmsRecords 清理短信记录。days>0 删除距今超过 days 天的记录；days<=0 删除全部。
func (d *DB) clearSmsRecords(days int) (int64, error) {
	if days > 0 {
		cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).Unix()
		res, err := d.sql.Exec(`DELETE FROM sms_records WHERE created_at < ?`, cutoff)
		if err != nil {
			return 0, err
		}
		return res.RowsAffected()
	}
	res, err := d.sql.Exec(`DELETE FROM sms_records`)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// ---------------- 屏蔽规则（block_rules） ----------------

// BlockRule 屏蔽规则：关键字屏蔽 / 号码屏蔽
type BlockRule struct {
	ID        int64  `json:"id"`
	RuleType  string `json:"ruleType"`  // keyword / number
	Value     string `json:"value"`     // 关键字或号码（号码支持前缀匹配）
	MatchMode string `json:"matchMode"` // keyword: contains; number: prefix / exact
	Source    string `json:"source"`    // user / builtin
	Enabled   int    `json:"enabled"`   // 1 启用 / 0 停用
	Note      string `json:"note"`
	CreatedAt int64  `json:"createdAt"`
	UpdatedAt int64  `json:"updatedAt"`
	Hits      int64  `json:"hits"` // 命中次数（按记录表的 spam_rule 聚合，只读）
}

// blockRuleHitCounts 统计规则命中次数：号码规则看通话记录，关键字规则看短信记录
func (d *DB) blockRuleHitCounts(ruleType string) map[string]int64 {
	q := `SELECT spam_rule, COUNT(*) FROM sms_records WHERE spam = 1 AND spam_rule <> '' GROUP BY spam_rule`
	if ruleType == "number" {
		q = `SELECT spam_rule, COUNT(*) FROM call_records WHERE spam = 1 AND spam_rule <> '' GROUP BY spam_rule`
	}
	out := map[string]int64{}
	rows, err := d.sql.Query(q)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var v string
		var n int64
		if err := rows.Scan(&v, &n); err == nil {
			out[v] = n
		}
	}
	return out
}

// blockRules 返回全部屏蔽规则（默认内置库在前，可按类型过滤）
func (d *DB) blockRules(ruleType string) ([]BlockRule, error) {
	where := ""
	args := []any{}
	if ruleType != "" {
		where = " WHERE rule_type = ?"
		args = append(args, ruleType)
	}
	rows, err := d.sql.Query(
		`SELECT id, rule_type, value, match_mode, source, enabled, note, created_at, updated_at
		 FROM block_rules`+where+`
		 ORDER BY source DESC, id ASC`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out = make([]BlockRule, 0)
	for rows.Next() {
		var r BlockRule
		if err := rows.Scan(&r.ID, &r.RuleType, &r.Value, &r.MatchMode, &r.Source,
			&r.Enabled, &r.Note, &r.CreatedAt, &r.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// blockRulesPage 分页查询屏蔽规则（默认内置库在前），返回规则列表与总数
func (d *DB) blockRulesPage(ruleType string, page, pageSize int) ([]BlockRule, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	where := ""
	args := []any{}
	if ruleType != "" {
		where = " WHERE rule_type = ?"
		args = append(args, ruleType)
	}
	var total int64
	if err := d.sql.QueryRow(`SELECT COUNT(*) FROM block_rules`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := d.sql.Query(
		`SELECT id, rule_type, value, match_mode, source, enabled, note, created_at, updated_at
		 FROM block_rules`+where+`
		 ORDER BY source DESC, id ASC LIMIT ? OFFSET ?`,
		append(args, pageSize, (page-1)*pageSize)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var out = make([]BlockRule, 0)
	for rows.Next() {
		var r BlockRule
		if err := rows.Scan(&r.ID, &r.RuleType, &r.Value, &r.MatchMode, &r.Source,
			&r.Enabled, &r.Note, &r.CreatedAt, &r.UpdatedAt); err != nil {
			return nil, 0, err
		}
		out = append(out, r)
	}
	return out, total, rows.Err()
}
func (d *DB) enabledBlockRules() ([]BlockRule, error) {
	rows, err := d.sql.Query(
		`SELECT id, rule_type, value, match_mode, source, enabled, note, created_at, updated_at
		 FROM block_rules WHERE enabled = 1 ORDER BY source DESC, id ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out = make([]BlockRule, 0)
	for rows.Next() {
		var r BlockRule
		if err := rows.Scan(&r.ID, &r.RuleType, &r.Value, &r.MatchMode, &r.Source,
			&r.Enabled, &r.Note, &r.CreatedAt, &r.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// addBlockRule 新增一条屏蔽规则（重复 value+rule_type 则忽略）
func (d *DB) addBlockRule(r BlockRule) (bool, error) {
	now := time.Now().Unix()
	var dup int
	err := d.sql.QueryRow(
		`SELECT COUNT(*) FROM block_rules WHERE rule_type = ? AND value = ?`,
		r.RuleType, r.Value).Scan(&dup)
	if err != nil {
		return false, err
	}
	if dup > 0 {
		return false, nil // 已存在，不重复添加
	}
	if r.MatchMode == "" {
		r.MatchMode = "contains"
	}
	if r.Source == "" {
		r.Source = "user"
	}
	_, err = d.sql.Exec(
		`INSERT INTO block_rules (rule_type, value, match_mode, source, enabled, note, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		r.RuleType, r.Value, r.MatchMode, r.Source, 1, r.Note, now, now)
	if err != nil {
		return false, err
	}
	return true, nil
}

// updateBlockRule 更新规则（可改 value/match_mode/enabled/note）
func (d *DB) updateBlockRule(id int64, value, matchMode string, enabled int, note string) error {
	now := time.Now().Unix()
	_, err := d.sql.Exec(
		`UPDATE block_rules SET value = ?, match_mode = ?, enabled = ?, note = ?, updated_at = ?
		 WHERE id = ?`,
		value, matchMode, enabled, note, now, id)
	return err
}

// deleteBlockRule 删除一条规则
func (d *DB) deleteBlockRule(id int64) error {
	_, err := d.sql.Exec(`DELETE FROM block_rules WHERE id = ?`, id)
	return err
}

// countBuiltinRules 统计内置库规则数量（用于判断是否已种子）
func (d *DB) countBuiltinRules() (int64, error) {
	var n int64
	err := d.sql.QueryRow(`SELECT COUNT(*) FROM block_rules WHERE source = 'builtin'`).Scan(&n)
	return n, err
}

// seedBuiltinRules 写入内置默认屏蔽库（仅在无内置数据时执行一次）
// 参考主流垃圾短信/骚扰电话特征整理，keyword 为高置信度营销/诈骗特征词，
// number 为骚扰营销号段前缀；用户可在面板中增删/启停。
func (d *DB) seedBuiltinRules() error {
	n, err := d.countBuiltinRules()
	if err != nil {
		return err
	}
	if n > 0 {
		return nil // 已种子过
	}
	now := time.Now().Unix()
	keywords := []string{
		// 营销退订类
		"退订", "回复TD", "回T退订", "TD退订", "N退订", "拒收请回复",
		// 博彩/彩票/中奖类
		"澳门", "博彩", "棋牌", "六合彩", "彩票", "中奖", "兑奖", "抽奖", "领奖",
		"红包", "返现", "0元购", "免费领",
		// 贷款/金融类
		"贷款", "信贷", "借款", "放款", "秒批", "额度", "提额", "信用卡", "POS机", "养卡", "套现",
		"理财", "投资", "荐股", "原油", "贵金属", "外汇", "期货", "虚拟货币", "区块链", "挖矿",
		// 兼职/刷单类
		"刷单", "兼职", "日结", "代刷", "打字员", "手工活", "赚外快", "副业",
		// 发票类
		"代开", "发票代开", "增值税发票",
		// 游戏推广类
		"棋牌游戏", "捕鱼", "电玩城", "首充", "充值返利",
		// 色情/交友类
		"色情", "约炮", "上门服务", "裸聊", "同城交友", "加威信", "加V",
		// 钓鱼/诈骗类
		"点击链接", "链接失效", "账户异常", "冻结", "解冻", "注销", "ETC", "医保", "社保",
		"营业执照", "年报", "冒充银行", "会员到期", "VIP到期", "续费",
		"领取红包", "恭喜您", "恭喜你", "幸运用户", "您已中奖",
	}
	for _, kw := range keywords {
		if _, err := d.sql.Exec(
			`INSERT INTO block_rules (rule_type, value, match_mode, source, enabled, note, created_at, updated_at)
			 VALUES ('keyword', ?, 'contains', 'builtin', 1, '内置默认库', ?, ?)`,
			kw, now, now); err != nil {
			return err
		}
	}
	// 骚扰营销号段（号码前缀匹配，可自行增删）
	prefixes := []struct {
		value, note string
	}{
		{"1068", "1068 营销短信通道"},
		{"1069", "1069 营销短信通道"},
		{"95", "95 号段营销/骚扰电话（前缀）"},
		{"400", "400 营销外呼（前缀，注意部分正规客服亦为 400）"},
		{"1010", "1010 营销外呼（前缀）"},
	}
	for _, p := range prefixes {
		if _, err := d.sql.Exec(
			`INSERT INTO block_rules (rule_type, value, match_mode, source, enabled, note, created_at, updated_at)
			 VALUES ('number', ?, 'prefix', 'builtin', 1, ?, ?, ?)`,
			p.value, p.note, now, now); err != nil {
			return err
		}
	}
	return nil
}

// resetBuiltinRules 重置内置默认库：删除全部 builtin 规则后重新种子
func (d *DB) resetBuiltinRules() error {
	if _, err := d.sql.Exec(`DELETE FROM block_rules WHERE source = 'builtin'`); err != nil {
		return err
	}
	return d.seedBuiltinRules()
}

// ---------------- 设备日志（日志中心） ----------------

// DeviceLog 设备上报日志（日志中心数据源）
type DeviceLog struct {
	ID         int64  `json:"id"`
	IMEI       string `json:"imei"`
	DeviceName string `json:"deviceName,omitempty"` // 关联设备备注名
	Topic      string `json:"topic"`
	LogType    string `json:"logType"` // online / telemetry / call_record / sms_record / result / powersave / notify_result
	Payload    string `json:"payload"` // 原始上报 JSON
	CreatedAt  int64  `json:"createdAt"`
}

// addDeviceLog 写入一条设备上报日志
func (d *DB) addDeviceLog(rec DeviceLog) error {
	_, err := d.sql.Exec(
		`INSERT INTO device_logs (imei, topic, log_type, payload, created_at)
		 VALUES (?, ?, ?, ?, ?)`,
		rec.IMEI, rec.Topic, rec.LogType, rec.Payload, rec.CreatedAt)
	return err
}

// deviceLogs 分页查询设备日志，支持时间范围/设备/类型/关键字筛选
func (d *DB) deviceLogs(page, pageSize int, from, to int64, imei, logType, keyword string) ([]DeviceLog, error) {
	if page < 1 {
		page = 1
	}
	where := ""
	args := []any{}
	if from > 0 {
		where += " AND l.created_at >= ?"
		args = append(args, from)
	}
	if to > 0 {
		where += " AND l.created_at <= ?"
		args = append(args, to)
	}
	if imei != "" {
		where += " AND l.imei = ?"
		args = append(args, imei)
	}
	if logType != "" {
		where += " AND l.log_type = ?"
		args = append(args, logType)
	}
	if keyword != "" {
		where += " AND (l.payload LIKE ? OR l.topic LIKE ?)"
		kw := "%" + keyword + "%"
		args = append(args, kw, kw)
	}
	rows, err := d.sql.Query(
		`SELECT l.id, l.imei, l.topic, l.log_type, l.payload, l.created_at, COALESCE(d.name, '')
		 FROM device_logs l LEFT JOIN devices d ON d.imei = l.imei
		 WHERE 1=1`+where+`
		 ORDER BY l.id DESC LIMIT ? OFFSET ?`,
		append(args, pageSize, (page-1)*pageSize)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out = make([]DeviceLog, 0)
	for rows.Next() {
		var rec DeviceLog
		if err := rows.Scan(&rec.ID, &rec.IMEI, &rec.Topic, &rec.LogType, &rec.Payload,
			&rec.CreatedAt, &rec.DeviceName); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}

// countDeviceLogs 统计设备日志总数（含筛选）
func (d *DB) countDeviceLogs(from, to int64, imei, logType, keyword string) (int64, error) {
	where := ""
	args := []any{}
	if from > 0 {
		where += " AND created_at >= ?"
		args = append(args, from)
	}
	if to > 0 {
		where += " AND created_at <= ?"
		args = append(args, to)
	}
	if imei != "" {
		where += " AND imei = ?"
		args = append(args, imei)
	}
	if logType != "" {
		where += " AND log_type = ?"
		args = append(args, logType)
	}
	if keyword != "" {
		where += " AND (payload LIKE ? OR topic LIKE ?)"
		kw := "%" + keyword + "%"
		args = append(args, kw, kw)
	}
	var n int64
	err := d.sql.QueryRow(`SELECT COUNT(*) FROM device_logs WHERE 1=1`+where, args...).Scan(&n)
	return n, err
}

// clearDeviceLogs 清理设备日志。days>0 删除距今超过 days 天；days<=0 删除全部。返回删除条数。
func (d *DB) clearDeviceLogs(days int) (int64, error) {
	if days > 0 {
		cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).Unix()
		res, err := d.sql.Exec(`DELETE FROM device_logs WHERE created_at < ?`, cutoff)
		if err != nil {
			return 0, err
		}
		return res.RowsAffected()
	}
	res, err := d.sql.Exec(`DELETE FROM device_logs`)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

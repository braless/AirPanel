import Foundation
import SwiftUI

// MARK: - 展示模型
//
// 这一层是「给人看的」：时间是 Date 而不是 Unix 秒，状态是枚举而不是字符串，
// 电量是百分比而不是毫伏。所有换算都收在 init(wire:) 里，
// 页面只消费这里，不再关心服务端字段长什么样。

// MARK: - 设备

struct Device: Identifiable, Hashable {
    var imei: String
    var phone: String
    var name: String
    var isOnline: Bool
    var lastSeen: Date
    var firstSeen: Date
    var telemetry: Telemetry

    var id: String { imei }

    /// 备注为空时退回手机号，避免列表里出现一行空白标题
    var displayName: String {
        name.isEmpty ? Fmt.phone(phone) : name
    }

    init(wire: Wire.Device, telemetry: Telemetry = .empty) {
        self.imei = wire.imei
        self.phone = wire.phone
        self.name = wire.name
        self.isOnline = wire.connected
        self.lastSeen = Date(timeIntervalSince1970: TimeInterval(wire.lastSeen))
        self.firstSeen = Date(timeIntervalSince1970: TimeInterval(wire.firstSeen))
        self.telemetry = telemetry
    }
}

struct Telemetry: Hashable {
    var voltageMV: Int
    var batteryPercent: Int
    var isCharging: Bool
    var temperature: Double
    var rssi: Int
    var csq: Int
    var netMode: String
    var carrier: String
    var uptime: TimeInterval
    var firmware: String
    var model: String
    var sn: String
    var iccid: String
    var simSlot: String
    var imsi: String
    var phone: String
    var reportedAt: Date

    /// 续航估算：来自 overview.power，服务端按「剩余容量 ÷ 估测电流」算好。
    /// 客户端不重算——电池容量和平均电流是用户在网页端配的，公式只有服务端知道。
    var estHours: Double
    var currentMa: Int

    /// 还没拿到遥测时的占位：全部 0 / 空串，页面会显示成「—」
    static let empty = Telemetry(
        voltageMV: 0, batteryPercent: 0, isCharging: false, temperature: 0,
        rssi: 0, csq: 0, netMode: "", carrier: "", uptime: 0,
        firmware: "", model: "", sn: "", iccid: "", simSlot: "",
        imsi: "", phone: "", reportedAt: .distantPast,
        estHours: 0, currentMa: 0
    )

    var hasData: Bool { reportedAt != .distantPast }

    /// 电压换算成「还剩多少」——单节锂电 3.4V 空、4.2V 满，做线性映射够用。
    var voltageRatio: Double {
        min(max((Double(voltageMV) - 3400) / (4200 - 3400), 0), 1)
    }

    /// 信号格 0–31 → 0–4 格
    var signalBars: Int {
        guard csq > 0 else { return 0 }
        switch csq {
        case 20...: return 4
        case 15..<20: return 3
        case 10..<15: return 2
        default: return 1
        }
    }

    init(voltageMV: Int, batteryPercent: Int, isCharging: Bool, temperature: Double,
         rssi: Int, csq: Int, netMode: String, carrier: String, uptime: TimeInterval,
         firmware: String, model: String, sn: String, iccid: String, simSlot: String,
         imsi: String, phone: String, reportedAt: Date,
         estHours: Double = 0, currentMa: Int = 0) {
        self.voltageMV = voltageMV
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.temperature = temperature
        self.rssi = rssi
        self.csq = csq
        self.netMode = netMode
        self.carrier = carrier
        self.uptime = uptime
        self.firmware = firmware
        self.model = model
        self.sn = sn
        self.iccid = iccid
        self.simSlot = simSlot
        self.imsi = imsi
        self.phone = phone
        self.reportedAt = reportedAt
        self.estHours = estHours
        self.currentMa = currentMa
    }

    /// 电量和充电状态来自 overview.battery（服务端按分段线性估的），
    /// 在线时长来自 overview.onlineSeconds（本次上线到现在），不是设备开机时长。
    init(wire: Wire.Telemetry, battery: Wire.BatteryInfo, onlineSeconds: Int64,
         power: Wire.PowerInfo? = nil) {
        self.voltageMV = wire.voltage
        self.batteryPercent = battery.percent
        self.isCharging = battery.charging
        self.temperature = wire.temperature
        self.rssi = wire.rssi
        self.csq = wire.csq
        self.netMode = wire.netMode
        self.carrier = wire.operatorName
        self.uptime = TimeInterval(onlineSeconds)
        self.firmware = wire.version
        self.model = wire.model
        self.sn = wire.sn
        self.iccid = wire.iccid
        self.simSlot = wire.simSlot
        self.imsi = wire.imsi ?? ""
        self.phone = wire.number ?? ""
        self.reportedAt = Date(timeIntervalSince1970: TimeInterval(wire.createdAt ?? 0))
        self.estHours = power?.estHours ?? 0
        self.currentMa = power?.currentMa ?? 0
    }

    /// 「续航 18 小时」——充电时说明在充，没数据时给破折号，不猜
    var enduranceText: String {
        if isCharging { return "充电中" }
        guard hasData, estHours > 0 else { return "—" }
        if estHours >= 100 { return ">99 小时" }
        if estHours < 1 { return "<1 小时" }
        return "\(Int(estHours.rounded())) 小时"
    }
}

// MARK: - 通话

enum CallDirection: String, Hashable {
    case incoming, outgoing

    var label: String { self == .incoming ? "呼入" : "呼出" }
    var symbol: String { self == .incoming ? "arrow.down.left" : "arrow.up.right" }

    init(wire: String) {
        self = wire == "outgoing" ? .outgoing : .incoming
    }
}

enum CallStatus: String, Hashable {
    case connected, missed, rejected, noAnswer, cancelled

    var label: String {
        switch self {
        case .connected: return "已接通"
        case .missed: return "未接"
        case .rejected: return "已拒接"
        case .noAnswer: return "无应答"
        case .cancelled: return "已取消"
        }
    }

    /// 服务端存的是设备端原始字符串：connected / missed / rejected / no_answer / cancelled
    init(wire: String) {
        switch wire {
        case "connected": self = .connected
        case "missed": self = .missed
        case "rejected": self = .rejected
        case "cancelled": self = .cancelled
        default: self = .noAnswer
        }
    }
}

// MARK: - 通知状态
//
// 通话和短信共用一套。取值照抄服务端 db.go 的注释：
// '' 未通知 / queued 排队 / sent 已发送 / failed 失败 / blocked 被屏蔽。
//
// 之前这个字段在 Wire 里解出来了、但展示层没接，于是列表上完全看不到
// 「这条到底通知出去没有」——设备端通知失败时用户是蒙在鼓里的。

enum NotifyState: String, Hashable {
    case none, queued, sent, failed, blocked

    init(wire: String) {
        self = NotifyState(rawValue: wire) ?? .none
    }

    /// 文案与网页端一致（server-go-v2/static/js/pages/calls.js 的 NOTIFY 表）
    var label: String {
        switch self {
        case .sent: return "已通知"
        case .failed: return "通知失败"
        case .blocked: return "已屏蔽"
        case .queued: return "排队中"
        case .none: return "未通知"
        }
    }
}

struct CallRecord: Identifiable, Hashable {
    var id: String
    var rawID: Int64
    var number: String
    var direction: CallDirection
    var status: CallStatus
    var duration: TimeInterval
    var startedAt: Date
    var spamRule: String?
    var deviceName: String
    /// 通知推送的投递状态（设备端回执）
    var notify: NotifyState
    /// 由 store 在拿到录音列表后回填：同号码且有文件就认为有录音
    var hasRecording: Bool
    var contactName: String?

    init(wire: Wire.CallRecord) {
        self.id = String(wire.id)
        self.rawID = wire.id
        self.number = wire.number
        self.direction = CallDirection(wire: wire.direction)
        self.status = CallStatus(wire: wire.status)
        self.duration = TimeInterval(wire.duration)
        self.startedAt = Date(timeIntervalSince1970: TimeInterval(wire.startedAt))
        self.spamRule = wire.spamRule.isEmpty ? nil : wire.spamRule
        self.deviceName = wire.deviceName ?? ""
        self.notify = NotifyState(wire: wire.notifyStatus)
        self.hasRecording = false
        self.contactName = nil
    }
}

// MARK: - 短信

enum SmsDirection: String, Hashable {
    case inbound, outbound

    var label: String { self == .inbound ? "收到" : "发出" }

    init(wire: String) {
        self = wire == "out" ? .outbound : .inbound
    }
}

struct SmsRecord: Identifiable, Hashable {
    var id: String
    var rawID: Int64
    var number: String
    var direction: SmsDirection
    var content: String
    var time: Date
    var spamRule: String?
    var deviceName: String
    /// 通知推送的投递状态（设备端回执）
    var notify: NotifyState
    var contactName: String?

    init(wire: Wire.SmsRecord) {
        self.id = String(wire.id)
        self.rawID = wire.id
        self.number = wire.number
        self.direction = SmsDirection(wire: wire.direction)
        self.content = wire.content
        self.time = Date(timeIntervalSince1970: TimeInterval(wire.createdAt))
        self.spamRule = wire.spamRule.isEmpty ? nil : wire.spamRule
        self.deviceName = wire.deviceName ?? ""
        self.notify = NotifyState(wire: wire.notifyStatus)
        self.contactName = nil
    }
}

// MARK: - 录音

struct Recording: Identifiable, Hashable {
    var id: String
    var fileName: String
    var number: String
    var date: Date
    var sizeBytes: Int

    /// 文件名约定：`18888888888_20261016162030.wav`
    /// （见 Air724ug/script/handler/handler_call.lua 的上传逻辑）
    init(wire: Wire.Recording) {
        self.id = wire.name
        self.fileName = wire.name
        self.sizeBytes = Int(wire.size)
        self.date = Recording.parseDate(wire.modTime) ?? .distantPast
        self.number = Recording.parseNumber(wire.name)
    }

    private static func parseNumber(_ name: String) -> String {
        let base = name.split(separator: ".").first.map(String.init) ?? name
        let head = base.split(separator: "_").first.map(String.init) ?? base
        return head.allSatisfy({ $0.isNumber || $0 == "+" }) ? head : base
    }

    /// 两种来源两种格式：
    ///   · 真实服务端（webdav.go）给 ISO8601 带偏移：2026-10-22T13:45:05+08:00
    ///   · WebDAV PROPFIND 原始值是 RFC1123：Tue, 20 Oct 2026 14:22:10 GMT
    private static let iso = ISO8601DateFormatter()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private static func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        if let d = iso.date(from: raw) { return d }
        if let d = formatter.date(from: raw) { return d }
        return nil
    }
}

// MARK: - 任务

enum TaskStatus: String, Hashable {
    case success, failed, pending

    var label: String {
        switch self {
        case .success: return "成功"
        case .failed: return "失败"
        case .pending: return "进行中"
        }
    }

    var tint: Color {
        switch self {
        case .success: return Theme.online
        case .failed: return Theme.danger
        case .pending: return Theme.warn
        }
    }

    /// 服务端 recordTask 实际写的是 "done"（见 broker.go:781）。
    /// 但设备把「执行超时」这类失败写在 result 里（`{"error":"任务执行超时"}`），
    /// status 依旧是 done——只看 status 会把超时记成成功，所以 result 也要读。
    /// 判定顺序：error 字段 → result 里的失败信号 → status。
    init(wire: String, error: String = "", result: String = "") {
        if !error.isEmpty || Self.resultSignalsFailure(result) {
            self = .failed
            return
        }
        switch wire {
        case "done", "success": self = .success
        case "failed", "error": self = .failed
        default: self = .pending
        }
    }

    /// result 是设备回执的原始 JSON，可能带 error 或 success:false
    private static func resultSignalsFailure(_ result: String) -> Bool {
        guard
            let data = result.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        if let e = obj["error"] as? String, !e.isEmpty { return true }
        if let ok = obj["success"] as? Bool, ok == false { return true }
        return false
    }
}
struct TaskRecord: Identifiable, Hashable {
    var id: String
    var task: String
    var label: String
    var deviceName: String
    var status: TaskStatus
    var result: String
    var createdAt: Date
    var duration: TimeInterval

    /// 服务端时间戳精确到秒，同一秒内完成的就是 0——写「0.0s」像坏掉了，写「—」更诚实
    var durationText: String {
        duration < 1 ? "—" : String(format: "%.0fs", duration)
    }

    init(wire: Wire.TaskRecord) {
        self.id = wire.taskId
        self.task = wire.task
        self.label = Catalog.command(wire.task)?.label ?? wire.task
        self.deviceName = wire.deviceName ?? ""
        self.status = TaskStatus(wire: wire.status, error: wire.error, result: wire.result)
        let body = wire.result.isEmpty ? wire.error : wire.result
        self.result = body.isEmpty ? "—" : body
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(wire.createdAt))
        self.duration = wire.finishedAt > wire.createdAt
            ? TimeInterval(wire.finishedAt - wire.createdAt)
            : 0
    }
}

// MARK: - 定时任务

struct Schedule: Identifiable, Hashable {
    var id: String
    var rawID: Int64
    var name: String
    var taskLabel: String
    var task: String
    var deviceName: String
    var imei: String
    var spec: Wire.ScheduleSpec
    var enabled: Bool
    var lastRun: Date?
    var params: String

    var humanSpec: String { spec.describe }

    /// 下次执行时间由周期自己算，服务端不返回（它只在命中那一刻判定）
    var nextRun: Date? { enabled ? spec.nextDate(after: Date()) : nil }

    init(wire: Wire.Schedule) {
        self.id = String(wire.id)
        self.rawID = wire.id
        self.name = wire.name.isEmpty ? (Catalog.command(wire.task)?.label ?? wire.task) : wire.name
        self.task = wire.task
        self.taskLabel = Catalog.command(wire.task)?.label ?? wire.task
        self.deviceName = wire.deviceName ?? ""
        self.imei = wire.imei
        self.spec = wire.spec
        self.enabled = wire.enabled
        self.lastRun = wire.lastExecuted > 0
            ? Date(timeIntervalSince1970: TimeInterval(wire.lastExecuted))
            : nil
        self.params = wire.params
    }
}

// MARK: - 周期描述与下次时间
//
// 逐字对齐 server-go-v2/scheduler.go 的 scheduleSpec.describe() 与 due()：
// 面板上写的「每天 04 点 00 分」必须和服务端实际触发的那一刻是同一件事。

extension Wire.ScheduleSpec {
    var describe: String {
        func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        func hm() -> String { "\(pad2(hour ?? 0)) 点 \(pad2(minute ?? 0)) 分" }
        switch type {
        case "weekly":
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let w = weekday ?? 0
            guard (0..<7).contains(w) else { return "未知周期" }
            return "每\(names[w]) \(hm())"
        case "monthly":
            return "每月 \(pad2(day ?? 1)) 日 \(hm())"
        case "daily":
            return "每天 \(hm())"
        case "hourly":
            return "每小时 \(pad2(minute ?? 0)) 分"
        case "interval":
            let n = self.n ?? 1
            return unit == "hour" ? "每 \(n) 小时" : "每 \(n) 分钟"
        default:
            return "未知周期"
        }
    }

    /// 下一次命中时刻。时间点类周期（每天/每周/每月/每小时）落在整分上；
    /// 间隔类按「现在 + 剩余间隔」估，因为真实基准是服务端的 lastCheck。
    func nextDate(after now: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        switch type {
        case "interval":
            let n = max(1, self.n ?? 1)
            let seconds = Double(unit == "hour" ? n * 3600 : n * 60)
            return now.addingTimeInterval(seconds)

        case "hourly":
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
            guard let hourStart = cal.date(from: comps) else { return nil }
            var candidate = hourStart.addingTimeInterval(TimeInterval((minute ?? 0) * 60))
            if candidate <= now { candidate = candidate.addingTimeInterval(3600) }
            return candidate

        case "daily":
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour ?? 0
            comps.minute = minute ?? 0
            comps.second = 0
            guard var candidate = cal.date(from: comps) else { return nil }
            if candidate <= now { candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate }
            return candidate

        case "weekly":
            let target = weekday ?? 0
            let current = cal.component(.weekday, from: now) - 1   // Calendar 里 1=周日
            var offset = (target - current + 7) % 7
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour ?? 0
            comps.minute = minute ?? 0
            comps.second = 0
            guard var candidate = cal.date(from: comps) else { return nil }
            candidate = cal.date(byAdding: .day, value: offset, to: candidate) ?? candidate
            if candidate <= now {
                offset += 7
                candidate = cal.date(byAdding: .day, value: 7, to: candidate) ?? candidate
            }
            return candidate

        case "monthly":
            let day = self.day ?? 1
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = min(day, 28)
            comps.hour = hour ?? 0
            comps.minute = minute ?? 0
            comps.second = 0
            guard var candidate = cal.date(from: comps) else { return nil }
            if candidate <= now {
                candidate = cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            }
            return candidate

        default:
            return nil
        }
    }
}

// MARK: - 屏蔽规则

enum BlockKind: String, Hashable {
    case keyword, number
    var label: String { self == .keyword ? "关键字" : "号码" }
    var wire: String { rawValue }
}

struct BlockRule: Identifiable, Hashable {
    var id: String
    var rawID: Int64
    var kind: BlockKind
    var value: String
    var matchMode: String
    var isBuiltin: Bool
    var enabled: Bool
    var hits: Int
    var note: String

    init(wire: Wire.BlockRule) {
        self.id = String(wire.id)
        self.rawID = wire.id
        self.kind = BlockKind(rawValue: wire.ruleType) ?? .keyword
        self.value = wire.value
        self.matchMode = BlockRule.localized(wire.matchMode)
        self.isBuiltin = wire.source == "builtin"
        self.enabled = wire.enabled != 0
        self.hits = Int(wire.hits)
        self.note = wire.note
    }

    static func localized(_ mode: String) -> String {
        switch mode {
        case "contains": return "包含"
        case "prefix": return "前缀"
        case "exact": return "精确"
        default: return mode
        }
    }

    static func wireMode(_ mode: String) -> String {
        switch mode {
        case "包含": return "contains"
        case "前缀": return "prefix"
        case "精确": return "exact"
        default: return mode
        }
    }
}

// MARK: - 日志

enum LogLevel: String, Hashable {
    case info, warn, error

    var label: String { rawValue.uppercased() }

    var tint: Color {
        switch self {
        case .info: return Theme.ink2
        case .warn: return Theme.warn
        case .error: return Theme.danger
        }
    }
}

struct DeviceLog: Identifiable, Hashable {
    var id: String
    var level: LogLevel
    var source: String
    var message: String
    var time: Date

    /// 设备日志的级别不在字段里，只能从上报内容推断：
    /// 通知回执里带 failed 的算警告，result 里带 error 的算错误，其余都是信息。
    init(wire: Wire.DeviceLog) {
        self.id = String(wire.id)
        self.source = (wire.deviceName?.isEmpty == false ? wire.deviceName! : wire.imei) + " · " + wire.logType
        self.message = wire.payload
        self.time = Date(timeIntervalSince1970: TimeInterval(wire.createdAt))

        let lower = wire.payload.lowercased()
        if lower.contains("\"error\":\"") || wire.logType == "error" {
            self.level = .error
        } else if wire.logType == "notify_result" || lower.contains("failed") || lower.contains("失败") {
            self.level = .warn
        } else {
            self.level = .info
        }
    }
}

// MARK: - 指令目录占位
//
// Catalog 在 Catalog.swift 里定义，这里只声明依赖关系（TaskRecord / Schedule 用到）。

// MARK: - 控制台输出行

struct ConsoleLine: Identifiable, Hashable {
    enum Kind: Hashable { case sent, reply, error, info }
    var id = UUID()
    var kind: Kind
    var text: String
    var time: Date
}

import Foundation

// MARK: - 线路模型（Wire）
//
// 与 server-go-v2 的 JSON 输出一一对应，字段名、类型、可空性都不做任何美化。
// 约定：
//   · 所有时间戳都是 Unix 秒（Int64），不是 ISO8601
//   · 省略字段用 omitempty 的（deviceName）解码成可选
//   · 分页接口统一返回 { list, total, page, pageSize }，列表键名各自不同
//   · 写操作统一返回 { success, message }，失败时 HTTP 200 + success:false 也可能出现
//
// 这一层只负责「像 JSON」，不做任何展示逻辑——展示在 Models.swift 里换算。

enum Wire {}

// MARK: - 认证

extension Wire {
    struct LoginResponse: Decodable {
        var token: String
        var username: String
    }

    struct SimpleResult: Decodable {
        var success: Bool?
        var message: String?
    }

    struct ChangeUserInfo: Decodable {
        var success: Bool?
        var message: String?
        var username: String?
        var needRelogin: Bool?
    }
}

// MARK: - 设备

extension Wire {
    struct Device: Decodable {
        var imei: String
        var phone: String
        var name: String
        var connected: Bool
        var lastSeen: Int64
        var firstSeen: Int64
    }

    struct Telemetry: Decodable {
        var id: Int64?
        var imei: String?
        var voltage: Int
        var temperature: Double
        var rssi: Int
        var rsrp: Int?
        var csq: Int
        var netMode: String
        var operatorName: String
        var number: String?
        var imsi: String?
        var simSlot: String
        var iccid: String
        var version: String
        var model: String
        var sn: String
        var vbus: Bool
        var workTime: Int64
        var createdAt: Int64?

        private enum CodingKeys: String, CodingKey {
            case id, imei, voltage, temperature, rssi, rsrp, csq
            case netMode, simSlot, iccid, version, model, sn, vbus, workTime, createdAt
            case operatorName = "operator"
        }
    }

    struct BatteryInfo: Decodable {
        var mah: Int
        var percent: Int
        var voltage: Int
        var charging: Bool
    }

    struct PowerInfo: Decodable {
        var currentMa: Int
        var estHours: Double
        var avgCurrentMa: Int
    }

    struct DeviceOverview: Decodable {
        var device: Device?
        var connectedAt: Int64
        var onlineSeconds: Int64
        var latest: Telemetry?
        var history: [Telemetry]?
        var battery: BatteryInfo
        var power: PowerInfo
    }

    struct StatsSummary: Decodable {
        var devices: Int
        var online: Int
        var callsToday: Int
        var callIn: Int
        var callOut: Int
        var callMissed: Int
        var smsToday: Int
        var smsIn: Int
        var smsOut: Int
        var tasksToday: Int
        var tasksOK: Int
        var tasksFailed: Int
        var uptimeSec: Int64
    }
}

// MARK: - 记录

extension Wire {
    struct CallRecord: Decodable, Identifiable {
        var id: Int64
        var imei: String
        var deviceName: String?
        var number: String
        var direction: String
        var status: String
        var duration: Int64
        var startedAt: Int64
        var connectedAt: Int64
        var endedAt: Int64
        var reason: String
        var notifyStatus: String
        var spam: Int
        var spamRule: String
    }

    struct SmsRecord: Decodable, Identifiable {
        var id: Int64
        var imei: String
        var deviceName: String?
        var number: String
        var direction: String
        var content: String
        var createdAt: Int64
        var notifyStatus: String
        var spam: Int
        var spamRule: String
    }

    struct CallsPage: Decodable {
        var calls: [CallRecord]
        var total: Int
        var page: Int
        var pageSize: Int
    }

    struct SmsPage: Decodable {
        var sms: [SmsRecord]
        var total: Int
        var page: Int
        var pageSize: Int
    }
}

// MARK: - 任务

extension Wire {
    struct TaskRecord: Decodable, Identifiable {
        var taskId: String
        var imei: String
        var deviceName: String?
        var task: String
        var params: String
        var result: String
        var error: String
        var status: String
        var createdAt: Int64
        var finishedAt: Int64

        var id: String { taskId }
    }

    struct TasksPage: Decodable {
        var tasks: [TaskRecord]
        var total: Int
        var page: Int
        var pageSize: Int
    }

    /// /api/executeTask 与 /api/schedules/run 的返回：result 是设备回的任意 JSON
    struct ExecuteResponse: Decodable {
        var success: Bool
        var message: String?
        var result: JSONValue?
    }
}

// MARK: - 定时任务

extension Wire {
    struct ScheduleSpec: Decodable, Hashable {
        var type: String
        var weekday: Int?
        var day: Int?
        var hour: Int?
        var minute: Int?
        var n: Int?
        var unit: String?
    }

    struct Schedule: Decodable, Identifiable {
        var id: Int64
        var name: String
        var imei: String
        var deviceName: String?
        var task: String
        var params: String
        var spec: ScheduleSpec
        var enabled: Bool
        var createdAt: Int64
        var lastExecuted: Int64
    }

    struct SchedulesPage: Decodable {
        var schedules: [Schedule]
        var total: Int
        var page: Int
        var pageSize: Int
    }
}

// MARK: - 屏蔽规则

extension Wire {
    struct BlockRule: Decodable, Identifiable {
        var id: Int64
        var ruleType: String
        var value: String
        var matchMode: String
        var source: String
        var enabled: Int
        var note: String
        var createdAt: Int64
        var updatedAt: Int64
        var hits: Int64
    }

    struct BlockRulesResponse: Decodable {
        var rules: [BlockRule]
        var total: Int
    }
}

// MARK: - 日志

extension Wire {
    struct DeviceLog: Decodable, Identifiable {
        var id: Int64
        var imei: String
        var deviceName: String?
        var topic: String
        var logType: String
        var payload: String
        var createdAt: Int64
    }

    struct LogsPage: Decodable {
        var logs: [DeviceLog]
        var total: Int
        var page: Int
        var pageSize: Int
    }

    struct ServerLogEntry: Decodable, Identifiable {
        var time: Int64
        var level: String
        var msg: String

        var id: String { "\(time)-\(msg.hashValue)" }
    }

    struct ServerLogsPage: Decodable {
        var lines: [ServerLogEntry]
        var total: Int
    }
}

// MARK: - 设置

extension Wire {
    struct EventLED: Decodable {
        var enabled: Bool
        var color: String
        var blink: Bool
        var duration: Int
    }

    struct WebDAVConfig: Decodable {
        var url: String
        var username: String
        var password: String
        var dir: String
    }

    struct BrandConfig: Decodable {
        var title: String
        var logo: String
        var avatar: String
    }

    struct Settings: Decodable {
        var username: String
        var notifyEnabled: Bool
        var notifyChannels: [String]
        var notifyConfig: [String: [String: String]]
        var smsLed: EventLED
        var callLed: EventLED
        var webdav: WebDAVConfig
        var brand: BrandConfig
    }

    struct NotifyField: Decodable, Identifiable {
        var key: String
        var label: String
        var type: String
        var placeholder: String?
        var required: Bool?

        var id: String { key }
    }

    struct NotifyChannelDef: Decodable, Identifiable {
        var name: String
        var label: String
        var fields: [NotifyField]

        var id: String { name }
    }
}

// MARK: - 录音

extension Wire {
    struct Recording: Decodable, Identifiable {
        var name: String
        var size: Int64
        var modTime: String
        var url: String

        var id: String { name }
    }

    struct RecordingsResponse: Decodable {
        var success: Bool?
        var error: String?
        var files: [Recording]

        /// 老版本服务端可能不带 success，只要给了文件列表就算成功
        var isOK: Bool { success ?? (error == nil) }
    }
}

// MARK: - 运维

extension Wire {
    struct Health: Decodable {
        var ok: Bool
        var version: String
        var uptimeSec: Int64
    }
}

// MARK: - 任意 JSON
//
// 设备回执的 result 是 Lua 里拼出来的任意结构，服务端原样透传。
// 用一个递归枚举承接，任务控制台据此压成单行展示。

enum JSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    /// 单行紧凑渲染，键按字母序——控制台里同一份数据每次长得一样。
    var compact: String {
        switch self {
        case .string(let s):
            return s
        case .number(let d):
            return d == d.rounded() && abs(d) < 1e15
                ? String(Int64(d))
                : String(format: "%g", d)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .array(let items):
            return "[" + items.map(\.compact).joined(separator: ",") + "]"
        case .object(let dict):
            let body = dict.keys.sorted().map { "\"\($0)\":\(dict[$0]!.compact)" }
            return "{" + body.joined(separator: ",") + "}"
        }
    }

    var intValue: Int? {
        if case .number(let d) = self { return Int(d) }
        if case .string(let s) = self { return Int(s) }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// 对象取键。枚举 case 不能直接链式取下标，只能走这个方法。
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    /// get_config 的回执有两种形态：纯字符串，或 { content: "..." } / { config: "..." }
    var configText: String? {
        if let s = stringValue, !s.isEmpty { return s }
        for key in ["content", "config", "text"] {
            if let s = self[key]?.stringValue, !s.isEmpty { return s }
        }
        return nil
    }
}

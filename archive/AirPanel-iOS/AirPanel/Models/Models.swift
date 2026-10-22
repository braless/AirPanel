import Foundation

// MARK: - 设备

/// GET /api/userPool 返回的设备数组元素
struct Device: Codable, Identifiable, Hashable {
    var id: String { imei }
    let imei: String
    let phone: String
    let name: String
    let connected: Bool
    let lastSeen: Int64
    let firstSeen: Int64
}

// MARK: - 遥测 / 概览

/// 设备上报的遥测（GET /api/device/overview 中 latest / history）
struct Telemetry: Codable {
    let ID: Int64?
    let imei: String
    let voltage: Int      // 电池电压 mV
    let temperature: Double
    let rssi: Int         // dBm
    let rsrp: Int
    let csq: Int
    let netMode: String
    let `operator`: String
    let number: String
    let imsi: String
    let simSlot: String
    let iccid: String
    let version: String
    let model: String
    let sn: String
    let vbus: Bool        // 是否充电 / USB 供电
    let workTime: Int64   // 开机时长（秒）
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case ID = "id", imei, voltage, temperature, rssi, rsrp, csq, netMode
        case `operator`, number, imsi, simSlot, iccid, version, model, sn
        case vbus, workTime, createdAt
    }
}

struct BatteryInfo: Codable {
    let mah: Int
    let percent: Int
    let voltage: Int
    let charging: Bool
}

struct PowerInfo: Codable {
    let currentMa: Int
    let estHours: Double
    let avgCurrentMa: Int
}

struct Overview: Codable {
    let device: Device?
    let connectedAt: Int64
    let onlineSeconds: Int64
    let latest: Telemetry?
    let history: [Telemetry]
    let battery: BatteryInfo
    let power: PowerInfo
}

// MARK: - 通话记录

struct CallRecord: Codable, Identifiable {
    let id: Int64
    let imei: String
    let deviceName: String?
    let number: String
    let direction: String   // incoming / outgoing
    let status: String      // answered / missed ...
    let duration: Int64
    let startedAt: Int64
    let connectedAt: Int64?
    let endedAt: Int64?
    let reason: String?
    let notifyStatus: String
    let spam: Int
    let spamRule: String?
}

struct CallList: Codable {
    let calls: [CallRecord]
    let total: Int
    let page: Int
    let pageSize: Int
}

// MARK: - 短信记录

struct SmsRecord: Codable, Identifiable {
    let id: Int64
    let imei: String
    let deviceName: String?
    let number: String
    let direction: String
    let content: String
    let createdAt: Int64
    let notifyStatus: String
    let spam: Int
    let spamRule: String?
}

struct SmsList: Codable {
    let sms: [SmsRecord]
    let total: Int
    let page: Int
    let pageSize: Int
}

// MARK: - 屏蔽规则

struct BlockRule: Codable, Identifiable {
    let id: Int64
    let ruleType: String   // keyword / number
    let value: String
    let matchMode: String  // contains / prefix / exact
    let source: String     // user / builtin
    let enabled: Int
    let note: String?
    let createdAt: Int64
    let updatedAt: Int64
}

struct RuleList: Codable {
    let rules: [BlockRule]
    let total: Int?
}

// MARK: - 定时任务

struct Schedule: Codable, Identifiable {
    let id: Int64
    let name: String
    let imei: String
    let deviceName: String?
    let task: String
    let params: String?
    let spec: ScheduleSpec?
    let enabled: Bool
    let createdAt: Int64
    let lastExecuted: Int64
}

/// 定时任务执行周期（与后端 scheduleSpec 对齐）
struct ScheduleSpec: Codable {
    let type: String?
    let weekday: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?
    let n: Int?
    let unit: String?
}

struct ScheduleList: Codable {
    let schedules: [Schedule]
    let total: Int
    let page: Int
    let pageSize: Int
}

// MARK: - 任务记录

struct TaskRecord: Codable, Identifiable {
    var id: String { taskId }
    let taskId: String
    let imei: String
    let deviceName: String?
    let task: String
    let params: String?
    let result: String?
    let error: String?
    let status: String
    let createdAt: Int64
    let finishedAt: Int64
}

struct TaskList: Codable {
    let tasks: [TaskRecord]
    let total: Int
    let page: Int
    let pageSize: Int
}

// MARK: - 通知渠道 / 通用响应

struct NotifyChannel: Codable, Identifiable {
    var id: String { channel }
    let channel: String
    let enabled: Bool
    let label: String?
}

struct MessageResponse: Codable {
    let message: String?
    let success: Bool?
    let token: String?
    let deleted: Int?
    let result: String?
    let duplicated: Bool?
}

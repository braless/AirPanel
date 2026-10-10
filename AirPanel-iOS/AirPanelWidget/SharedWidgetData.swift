import Foundation

/// 主 App 与桌面小组件之间共享的数据（App Group UserDefaults）
/// 主 App 在登录 / 拉取设备 / 加载记录后写入；小组件进程读取展示。
enum SharedWidgetData {
    static let groupID = "group.com.airpanel.client"
    static let suiteName = "airpanel.widget"   // UserDefaults suite

    struct DeviceItem: Codable {
        var imei: String
        var name: String
        var phone: String
        var online: Bool
        var battery: Int      // 0~100，未知为 -1
        var csq: Int          // 信号 0~31，未知为 -1
        var netMode: String   // 网络模式
    }

    struct SmsItem: Codable {
        var number: String
        var content: String
        var time: Int64
        var spam: Bool
    }

    struct CallItem: Codable {
        var number: String
        var direction: String   // incoming / outgoing / missed
        var time: Int64
        var spam: Bool
    }

    static let kDevice = "shared.device"
    static let kSms = "shared.sms"
    static let kCalls = "shared.calls"
    static let kUpdated = "shared.updated"

    static func suite() -> UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    static func device() -> DeviceItem? {
        guard let d = suite()?.data(forKey: kDevice) else { return nil }
        return try? JSONDecoder().decode(DeviceItem.self, from: d)
    }
    static func sms() -> [SmsItem] {
        guard let d = suite()?.data(forKey: kSms) else { return [] }
        return (try? JSONDecoder().decode([SmsItem].self, from: d)) ?? []
    }
    static func calls() -> [CallItem] {
        guard let d = suite()?.data(forKey: kCalls) else { return [] }
        return (try? JSONDecoder().decode([CallItem].self, from: d)) ?? []
    }

    // MARK: - 写入（主 App 调用）

    static func saveDevice(_ item: DeviceItem?) {
        let data = item.flatMap { try? JSONEncoder().encode($0) }
        suite()?.set(data, forKey: kDevice)
        suite()?.set(Date().timeIntervalSince1970, forKey: kUpdated)
    }
    static func saveSms(_ items: [SmsItem]) {
        suite()?.set(try? JSONEncoder().encode(items), forKey: kSms)
        suite()?.set(Date().timeIntervalSince1970, forKey: kUpdated)
    }
    static func saveCalls(_ items: [CallItem]) {
        suite()?.set(try? JSONEncoder().encode(items), forKey: kCalls)
        suite()?.set(Date().timeIntervalSince1970, forKey: kUpdated)
    }
}

/// 小组件内通用脱敏
func wgMasked(_ s: String, keepHead: Int = 3, keepTail: Int = 4) -> String {
    guard s.count >= keepHead + keepTail else { return s }
    return String(s.prefix(keepHead)) + "****" + String(s.suffix(keepTail))
}
func wgMaskedIMEI(_ s: String) -> String {
    guard s.count >= 8 else { return s }
    return String(s.prefix(6)) + "****" + String(s.suffix(2))
}

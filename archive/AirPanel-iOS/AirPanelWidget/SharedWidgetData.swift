import Foundation

/// 主 App 与桌面小组件之间共享的数据（App Group UserDefaults）
/// 主 App 在登录 / 拉取设备 / 加载记录后写入；小组件进程读取展示。
enum SharedWidgetData {
    static let groupID = "group.0b7900bd78d571ad.1"   // 与用户描述文件 App Group 白名单一致
    static let suiteName = "airpanel.widget"   // UserDefaults suite

    struct DeviceItem: Codable {
        var imei: String
        var name: String
        var phone: String
        var online: Bool
        var battery: Int      // 0~100，未知为 -1
        var csq: Int          // 信号 0~31，未知为 -1
        var netMode: String   // 网络模式
        var lastSeen: Int64?  // 最后在线时间戳（秒），未知为 nil
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
    static let kBaseURL = "shared.baseURL"
    static let kToken = "shared.token"

    static func suite() -> UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    /// App 登录后写入「服务器地址 + 令牌」，供小组件直连使用（不保存密码）
    static func saveConfig(baseURL: String, token: String) {
        suite()?.set(baseURL, forKey: kBaseURL)
        suite()?.set(token, forKey: kToken)
    }
    static func clearConfig() {
        suite()?.removeObject(forKey: kBaseURL)
        suite()?.removeObject(forKey: kToken)
    }
    /// 小组件读取的直连配置；未登录 / 共享区不可用时返回 nil
    static func widgetConfig() -> (baseURL: String, token: String)? {
        guard let b = suite()?.string(forKey: kBaseURL), !b.isEmpty,
              let t = suite()?.string(forKey: kToken), !t.isEmpty else { return nil }
        return (b, t)
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

/// 最后在线时间的相对展示
func wgLastSeenText(_ ts: Int64?) -> String {
    guard let ts, ts > 0 else { return "-" }
    let s = Date().timeIntervalSince1970 - TimeInterval(ts)
    if s < 60 { return "刚刚" }
    if s < 3600 { return "\(Int(s / 60))分钟前" }
    if s < 86400 { return "\(Int(s / 3600))小时前" }
    return "\(Int(s / 86400))天前"
}

// MARK: - Widget 端网络直连
/// 小组件用 App 登录后写入共享区的「服务器地址 + 令牌」直连拉数据（不保存密码）。
enum WidgetAPI {
    private struct Cfg { let baseURL: String; let token: String }

    // 响应模型（仅取所需字段，多余字段自动忽略）
    private struct WDevice: Codable { let imei: String; let phone: String; let name: String; let connected: Bool; let lastSeen: Int64? }
    private struct WOverview: Codable { let battery: WBat?; let latest: WLate? }
    private struct WBat: Codable { let percent: Int? }
    private struct WLate: Codable { let csq: Int?; let netMode: String? }
    private struct WCalls: Codable { let calls: [WCall] }
    private struct WCall: Codable { let number: String?; let direction: String?; let startedAt: Int64?; let spam: Int? }
    private struct WSms: Codable { let sms: [WSmsItem] }
    private struct WSmsItem: Codable { let number: String?; let content: String?; let createdAt: Int64?; let spam: Int? }

    private static func cfg() -> Cfg? {
        guard let c = SharedWidgetData.widgetConfig() else { return nil }
        return Cfg(baseURL: c.baseURL, token: c.token)
    }

    private static func makeURL(_ path: String, _ base: String) -> URL? {
        var b = base
        if !b.hasSuffix("/") { b += "/" }
        return URL(string: b + path)
    }

    private static func request(_ method: String, _ path: String, _ c: Cfg, body: Data? = nil) async throws -> Data {
        guard let url = makeURL(path, c.baseURL) else { throw WidgetAPIError("URL 无效") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
        if let body = body { req.httpBody = body }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WidgetAPIError("请求失败")
        }
        return data
    }

    private static func get<T: Decodable>(_ t: T.Type, _ path: String, _ c: Cfg) async throws -> T {
        try JSONDecoder().decode(t, from: await request("GET", path, c))
    }

    static func fetchDevice() async -> SharedWidgetData.DeviceItem? {
        guard let c = cfg() else { return nil }
        do {
            let devs = try await get([WDevice].self, "/api/userPool", c)
            guard let d = devs.first else { return nil }
            let ov = try? await get(WOverview.self, "/api/device/overview?imei=\(d.imei)", c)
            return SharedWidgetData.DeviceItem(imei: d.imei, name: d.name, phone: d.phone,
                                              online: d.connected, battery: ov?.battery?.percent ?? -1,
                                              csq: ov?.latest?.csq ?? -1, netMode: ov?.latest?.netMode ?? "",
                                              lastSeen: d.lastSeen)
        } catch { return nil }
    }

    static func fetchCalls() async -> [SharedWidgetData.CallItem] {
        guard let c = cfg() else { return [] }
        do {
            let r = try await get(WCalls.self, "/api/calls?page=1", c)
            return r.calls.prefix(6).map {
                SharedWidgetData.CallItem(number: $0.number ?? "", direction: $0.direction ?? "",
                                          time: $0.startedAt ?? 0, spam: ($0.spam ?? 0) > 0)
            }
        } catch { return [] }
    }

    static func fetchSms() async -> [SharedWidgetData.SmsItem] {
        guard let c = cfg() else { return [] }
        do {
            let r = try await get(WSms.self, "/api/sms?page=1", c)
            return r.sms.prefix(6).map {
                SharedWidgetData.SmsItem(number: $0.number ?? "", content: $0.content ?? "",
                                         time: $0.createdAt ?? 0, spam: ($0.spam ?? 0) > 0)
            }
        } catch { return [] }
    }
}

struct WidgetAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ m: String) { message = m }
}

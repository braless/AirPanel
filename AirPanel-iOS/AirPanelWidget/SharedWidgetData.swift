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

// MARK: - Widget 端网络直连
/// 小组件直接连服务端拉数据（不依赖 App Group / 签名），App Group 缓存仅作兜底。
enum WidgetAPI {
    /// 内置服务器与账号（自用；可在 App 内修改服务器后由 App 同步覆盖）
    static var server = "http://142.248.137.59:9527"
    static let username = "admin"
    static let password = "oaife@123456"

    // 响应模型（仅取所需字段，多余字段自动忽略）
    private struct WDevice: Codable { let imei: String; let phone: String; let name: String; let connected: Bool }
    private struct WOverview: Codable { let battery: WBat?; let latest: WLate? }
    private struct WBat: Codable { let percent: Int? }
    private struct WLate: Codable { let csq: Int?; let netMode: String? }
    private struct WCalls: Codable { let calls: [WCall] }
    private struct WCall: Codable { let number: String?; let direction: String?; let startedAt: Int64?; let spam: Int? }
    private struct WSms: Codable { let sms: [WSmsItem] }
    private struct WSmsItem: Codable { let number: String?; let content: String?; let createdAt: Int64?; let spam: Int? }
    private struct WLogin: Codable { let token: String?; let message: String? }

    private static func makeURL(_ path: String) -> URL? {
        var base = server
        if !base.hasSuffix("/") { base += "/" }
        return URL(string: base + path)
    }

    private static func request(_ method: String, _ path: String, token: String = "", body: Data? = nil) async throws -> Data {
        guard let url = makeURL(path) else { throw WidgetAPIError("URL 无效") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body = body { req.httpBody = body }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WidgetAPIError("请求失败")
        }
        return data
    }

    private static func get<T: Decodable>(_ t: T.Type, _ path: String, token: String) async throws -> T {
        try JSONDecoder().decode(t, from: await request("GET", path, token: token))
    }

    private static func login() async throws -> String {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        let data = try await request("POST", "/api/login", body: body)
        let r = try JSONDecoder().decode(WLogin.self, from: data)
        guard let t = r.token, !t.isEmpty else { throw WidgetAPIError("登录失败") }
        return t
    }

    static func fetchDevice() async -> SharedWidgetData.DeviceItem? {
        do {
            let token = try await login()
            let devs = try await get([WDevice].self, "/api/userPool", token: token)
            guard let d = devs.first else { return nil }
            let ov = try? await get(WOverview.self, "/api/device/overview?imei=\(d.imei)", token: token)
            return SharedWidgetData.DeviceItem(imei: d.imei, name: d.name, phone: d.phone,
                                              online: d.connected, battery: ov?.battery?.percent ?? -1,
                                              csq: ov?.latest?.csq ?? -1, netMode: ov?.latest?.netMode ?? "")
        } catch { return nil }
    }

    static func fetchCalls() async -> [SharedWidgetData.CallItem] {
        do {
            let token = try await login()
            let r = try await get(WCalls.self, "/api/calls?page=1", token: token)
            return r.calls.prefix(6).map {
                SharedWidgetData.CallItem(number: $0.number ?? "", direction: $0.direction ?? "",
                                          time: $0.startedAt ?? 0, spam: ($0.spam ?? 0) > 0)
            }
        } catch { return [] }
    }

    static func fetchSms() async -> [SharedWidgetData.SmsItem] {
        do {
            let token = try await login()
            let r = try await get(WSms.self, "/api/sms?page=1", token: token)
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

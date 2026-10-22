import Foundation

// MARK: - 错误

enum APIError: LocalizedError, Equatable {
    /// 401：token 失效，调用方据此清会话回登录页
    case unauthorized(String)
    /// 服务端明确给了 message
    case message(String)
    /// 网络层失败（连不上 / 超时 / TLS）
    case transport(String)
    /// 返回体不是预期结构
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let m): return m
        case .message(let m): return m
        case .transport(let m): return m
        case .decoding(let m): return m
        }
    }

    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

// MARK: - 客户端
//
// 一个实例绑定一个服务端地址 + 一个 token。会话变化时整体替换，
// 不做「改 baseURL」这种可变状态，避免请求打到上一个服务器。

final class APIClient: @unchecked Sendable {

    let baseURL: URL
    private let token: String
    private let session: URLSession

    init(baseURL: URL, token: String, timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.token = token

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = max(timeout, 60)
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: cfg)
    }

    // MARK: 地址归一化
    //
    // 用户手输地址，什么都可能出现：`panel.example.com`、`192.168.1.9:9527`、
    // `http://nas.local`。规则：
    //   · 已有 scheme 就照用
    //   · 私网 / 环回 / .local / 带端口的裸主机 → http（面板多数跑在局域网明文端口）
    //   · 其余裸域名 → https

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // 去掉误粘的路径与尾部斜杠，只保留 scheme://host[:port]
        if let range = s.range(of: "://") {
            let scheme = s[s.startIndex..<range.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            s = String(s[range.upperBound...])
        }
        var scheme = "https"
        let hostPort = s.split(separator: "/").first.map(String.init) ?? s
        let host = hostPort.split(separator: ":").first.map(String.init) ?? hostPort
        let hasPort = hostPort.contains(":")
        if !raw.contains("://") {
            if host.hasPrefix("127.") || host == "localhost"
                || host.hasPrefix("10.")
                || host.hasPrefix("192.168.")
                || host.lowercased().hasSuffix(".local")
                || isPrivate172(host)
                || hasPort {
                scheme = "http"
            }
        } else {
            scheme = raw.lowercased().hasPrefix("http://") ? "http" : "https"
        }
        guard let url = URL(string: "\(scheme)://\(hostPort)"), url.host() != nil else { return nil }
        return url
    }

    private static func isPrivate172(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts[0] == "172", let second = Int(parts[1]) else { return false }
        return (16...31).contains(second)
    }

    // MARK: 请求骨架

    private func makeRequest(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Data? = nil
    ) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false) else {
            throw APIError.transport("地址无效")
        }
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw APIError.transport("地址无效") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError where e.code == .cancelled {
            // 下拉刷新被系统取消 / 页面切走：这不是网络故障，
            // 抛 CancellationError 让上层安静收场，不弹「已取消，重试」
            throw CancellationError()
        } catch let e as URLError {
            throw APIError.transport(Self.describe(e))
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("响应异常")
        }
        if http.statusCode == 401 {
            throw APIError.unauthorized(Self.message(from: data) ?? "登录已失效，请重新登录")
        }
        if http.statusCode >= 400 {
            throw APIError.message(Self.message(from: data) ?? "HTTP \(http.statusCode)")
        }
        if T.self == EmptyBody.self {
            return EmptyBody() as! T
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // 服务端偶发返回非 JSON（例如反代 502 的 HTML），把前 120 字带出来便于排查
            let preview = String(data: data.prefix(120), encoding: .utf8) ?? ""
            throw APIError.decoding("返回格式异常：\(preview)")
        }
    }

    private func call<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        json: [String: Any]? = nil,
        as type: T.Type
    ) async throws -> T {
        var body: Data?
        if let json {
            body = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
        let req = try makeRequest(path, method: method, query: query, body: body)
        return try await perform(req, as: type)
    }

    private func post(_ path: String, json: [String: Any] = [:]) async throws -> Wire.SimpleResult {
        try await call(path, method: "POST", json: json, as: Wire.SimpleResult.self)
    }

    struct EmptyBody: Decodable {}

    private static func message(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let text = String(data: data.prefix(200), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false) ? text : nil
        }
        return (obj["message"] as? String) ?? (obj["error"] as? String)
    }

    private static func describe(_ e: URLError) -> String {
        switch e.code {
        case .cannotFindHost, .dnsLookupFailed:
            return "找不到服务器，检查地址是否写对"
        case .cannotConnectToHost:
            return "无法连接到服务器，检查端口与服务是否在运行"
        case .timedOut:
            return "连接超时，检查网络或服务端是否可达"
        case .notConnectedToInternet:
            return "设备没有联网"
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            return "HTTPS 证书校验失败，局域网面板请用 http:// 地址"
        case .networkConnectionLost:
            return "连接被中断，请重试"
        case .cancelled:
            return "已取消"
        default:
            return e.localizedDescription
        }
    }
}

// MARK: - 端点
//
// 路径、方法、参数名全部照抄 server-go-v2 的 routes()，不做任何重命名。

extension APIClient {

    // MARK: 认证

    /// 不需要 token 的登录调用（用空 token 的临时客户端）
    static func login(server: URL, username: String, password: String) async throws -> Wire.LoginResponse {
        let client = APIClient(baseURL: server, token: "")
        return try await client.call("/api/login", method: "POST",
                                     json: ["username": username, "password": password],
                                     as: Wire.LoginResponse.self)
    }

    func logout() async throws {
        _ = try await post("/api/logout")
    }

    func changeUserInfo(oldPassword: String, newUsername: String, newPassword: String) async throws -> Wire.ChangeUserInfo {
        try await call("/api/change-user-info", method: "POST", json: [
            "oldPassword": oldPassword,
            "newUsername": newUsername,
            "newPassword": newPassword
        ], as: Wire.ChangeUserInfo.self)
    }

    // MARK: 设备

    func devices() async throws -> [Wire.Device] {
        try await call("/api/userPool", as: [Wire.Device].self)
    }

    func overview(imei: String) async throws -> Wire.DeviceOverview {
        try await call("/api/device/overview", query: ["imei": imei], as: Wire.DeviceOverview.self)
    }

    func stats() async throws -> Wire.StatsSummary {
        try await call("/api/stats/summary", as: Wire.StatsSummary.self)
    }

    func remarkDevice(imei: String, name: String) async throws {
        _ = try await post("/api/device/remark", json: ["imei": imei, "name": name])
    }

    func deleteDevice(imei: String) async throws {
        _ = try await post("/api/device/delete", json: ["imei": imei])
    }

    func saveOverviewConfig(batteryMah: Int, avgCurrentMa: Int) async throws {
        _ = try await post("/api/device/overview/config",
                           json: ["batteryMah": batteryMah, "avgCurrentMa": avgCurrentMa])
    }

    // MARK: 任务

    /// 设备回执最多等 30 秒（服务端 ExecuteTask 的上限），所以这条单独放宽超时
    func executeTask(imei: String, task: String, params: [String: String]) async throws -> Wire.ExecuteResponse {
        var body: [String: Any] = ["imei": imei, "task": task]
        for (k, v) in params where !v.isEmpty { body[k] = v }
        return try await call("/api/executeTask", method: "POST", json: body,
                              as: Wire.ExecuteResponse.self)
    }

    func tasks(page: Int) async throws -> Wire.TasksPage {
        try await call("/api/tasks", query: ["page": String(page)], as: Wire.TasksPage.self)
    }

    func clearTasks(days: Int) async throws {
        _ = try await post("/api/tasks/clear", json: ["days": days])
    }

    // MARK: 定时任务

    func schedules(page: Int) async throws -> Wire.SchedulesPage {
        try await call("/api/schedules", query: ["page": String(page)], as: Wire.SchedulesPage.self)
    }

    func toggleSchedule(id: Int64, enabled: Bool) async throws {
        _ = try await post("/api/schedules/toggle", json: ["id": id, "enabled": enabled])
    }

    func runSchedule(id: Int64) async throws -> Wire.ExecuteResponse {
        try await call("/api/schedules/run", method: "POST", json: ["id": id],
                       as: Wire.ExecuteResponse.self)
    }

    func deleteSchedule(id: Int64) async throws {
        _ = try await post("/api/schedules/delete", json: ["id": id])
    }

    func addSchedule(name: String, imei: String, task: String,
                     params: [String: String], spec: [String: Any], enabled: Bool) async throws -> Wire.SimpleResult {
        let body: [String: Any] = [
            "name": name, "imei": imei, "task": task,
            "params": params, "spec": spec, "enabled": enabled
        ]
        return try await call("/api/schedules/add", method: "POST", json: body,
                              as: Wire.SimpleResult.self)
    }

    // MARK: 记录

    func calls(page: Int, pageSize: Int, imei: String?, keyword: String?, direction: String?) async throws -> Wire.CallsPage {
        try await call("/api/calls", query: [
            "page": String(page), "pageSize": String(pageSize),
            "imei": imei, "keyword": keyword, "direction": direction
        ], as: Wire.CallsPage.self)
    }

    func deleteCall(id: Int64) async throws {
        _ = try await post("/api/calls/delete", json: ["id": id])
    }

    func clearCalls(days: Int) async throws {
        _ = try await post("/api/calls/clear", json: ["days": days])
    }

    func sms(page: Int, pageSize: Int, imei: String?, keyword: String?, direction: String?) async throws -> Wire.SmsPage {
        try await call("/api/sms", query: [
            "page": String(page), "pageSize": String(pageSize),
            "imei": imei, "keyword": keyword, "direction": direction
        ], as: Wire.SmsPage.self)
    }

    func deleteSms(id: Int64) async throws {
        _ = try await post("/api/sms/delete", json: ["id": id])
    }

    func clearSms(days: Int) async throws {
        _ = try await post("/api/sms/clear", json: ["days": days])
    }

    // MARK: 日志

    func logs(page: Int, pageSize: Int, imei: String?, type: String?, keyword: String?) async throws -> Wire.LogsPage {
        try await call("/api/logs", query: [
            "page": String(page), "pageSize": String(pageSize),
            "imei": imei, "type": type, "keyword": keyword
        ], as: Wire.LogsPage.self)
    }

    func clearLogs(days: Int) async throws {
        _ = try await post("/api/logs/clear", json: ["days": days])
    }

    func serverLogs(level: String?, keyword: String?, limit: Int) async throws -> Wire.ServerLogsPage {
        try await call("/api/server-logs", query: [
            "level": level, "keyword": keyword, "limit": String(limit)
        ], as: Wire.ServerLogsPage.self)
    }

    func clearServerLogs() async throws {
        _ = try await post("/api/server-logs/clear")
    }

    // MARK: 屏蔽规则

    func blockRules(type: String?) async throws -> Wire.BlockRulesResponse {
        try await call("/api/block-rules", query: ["type": type], as: Wire.BlockRulesResponse.self)
    }

    func addBlockRule(ruleType: String, value: String, matchMode: String, note: String) async throws {
        _ = try await post("/api/block-rules/add", json: [
            "ruleType": ruleType, "value": value, "matchMode": matchMode, "note": note
        ])
    }

    func updateBlockRule(id: Int64, ruleType: String, value: String, matchMode: String,
                         note: String, enabled: Bool) async throws {
        _ = try await post("/api/block-rules/update", json: [
            "id": id, "ruleType": ruleType, "value": value,
            "matchMode": matchMode, "note": note, "enabled": enabled
        ])
    }

    func deleteBlockRule(id: Int64) async throws {
        _ = try await post("/api/block-rules/delete", json: ["id": id])
    }

    func resetBlockRules() async throws {
        _ = try await post("/api/block-rules/reset")
    }

    // MARK: 设置

    func settings() async throws -> Wire.Settings {
        try await call("/api/settings", as: Wire.Settings.self)
    }

    func saveSettings(notifyEnabled: Bool,
                      notifyChannels: [String],
                      notifyConfig: [String: [String: String]],
                      smsLed: [String: Any],
                      callLed: [String: Any],
                      webdav: [String: String],
                      brand: [String: String]) async throws {
        _ = try await post("/api/settings/save", json: [
            "notifyEnabled": notifyEnabled,
            "notifyChannels": notifyChannels,
            "notifyConfig": notifyConfig,
            "smsLed": smsLed,
            "callLed": callLed,
            "webdav": webdav,
            "brand": brand
        ])
    }

    func notifyChannels() async throws -> [Wire.NotifyChannelDef] {
        try await call("/api/notify/channels", as: [Wire.NotifyChannelDef].self)
    }

    func testNotify(channels: [String], config: [String: [String: String]]) async throws -> Wire.SimpleResult {
        try await call("/api/notify/test", method: "POST",
                       json: ["channels": channels, "config": config],
                       as: Wire.SimpleResult.self)
    }

    // MARK: 录音

    func recordings() async throws -> Wire.RecordingsResponse {
        try await call("/api/recordings", as: Wire.RecordingsResponse.self)
    }

    /// 录音是带鉴权的二进制流，不能直接丢给 AVPlayer 用 URL 播放，必须自己取 Data
    func recordingData(file: String) async throws -> Data {
        let req = try makeRequest("/api/recordings/play", query: ["file": file])
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("响应异常") }
            if http.statusCode == 401 { throw APIError.unauthorized("登录已失效") }
            guard http.statusCode == 200 else {
                throw APIError.message("录音读取失败（HTTP \(http.statusCode)）")
            }
            return data
        } catch let e as URLError {
            throw APIError.transport(Self.describe(e))
        }
    }

    func deleteRecording(file: String) async throws {
        _ = try await post("/api/recordings/delete", json: ["file": file])
    }

    // MARK: 运维

    func health() async throws -> Wire.Health {
        try await call("/api/health", as: Wire.Health.self)
    }

    func restart() async throws -> Wire.SimpleResult {
        try await post("/api/restart")
    }
}

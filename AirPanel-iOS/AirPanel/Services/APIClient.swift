import Foundation

/// 与服务端 REST 接口交互的客户端。所有端点均与服务端 api.go 路由一一对应。
struct APIClient {
    var baseURL: URL
    var token: String

    // MARK: - 底层请求

    /// 发送请求，返回服务端 JSON Data；非 2xx 抛 APIError（含服务端 message）
    func request(_ method: String, _ path: String, body: Encodable? = nil) async throws -> Data {
        var req = URLRequest(url: makeURL(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "无网络响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            // 尝试解析服务端 {message}
            if let obj = try? JSONDecoder().decode(MessageResponse.self, from: data),
               let msg = obj.message, !msg.isEmpty {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw APIError(message: "登录已过期，请重新登录")
                }
                throw APIError(message: msg)
            }
            throw APIError(message: "请求失败（\(http.statusCode)）")
        }
        return data
    }

    /// 用字符串拼接保留路径中的 query 参数（?、&、=），避免 appendingPathComponent 把 query 编码成字面量
    private func makeURL(_ path: String) -> URL {
        var base = baseURL.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: base + p) ?? baseURL
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        try decode(type, from: try await request("GET", path))
    }

    // MARK: - 认证

    func login(username: String, password: String) async throws -> String {
        let data = try await request("POST", "/api/login",
                                     body: LoginBody(username: username, password: password))
        let r = try decode(MessageResponse.self, from: data)
        guard let token = r.token, !token.isEmpty else {
            throw APIError(message: "登录失败：未返回令牌")
        }
        return token
    }

    func logout() async throws {
        _ = try await request("POST", "/api/logout")
    }

    // MARK: - 设备

    func userPool() async throws -> [Device] {
        try await get([Device].self, "/api/userPool")
    }

    func updateDeviceRemark(imei: String, name: String) async throws {
        _ = try await request("POST", "/api/device/remark", body: DeviceRemarkBody(imei: imei, name: name))
    }

    func deleteDevice(imei: String) async throws {
        _ = try await request("POST", "/api/device/delete", body: DeviceIMEIBody(imei: imei))
    }

    // MARK: - 概览

    func getOverview(imei: String) async throws -> Overview {
        let safe = imei.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? imei
        return try await get(Overview.self, "/api/device/overview?imei=\(safe)")
    }

    func saveOverviewConfig(batteryMah: Int, avgCurrentMa: Int) async throws {
        _ = try await request("POST", "/api/device/overview/config",
                              body: OverviewConfigBody(batteryMah: batteryMah, avgCurrentMa: avgCurrentMa))
    }

    // MARK: - 任务

    func executeTask(imei: String, task: String, extra: [String: Any]) async throws -> MessageResponse {
        var raw: [String: Any] = ["imei": imei, "task": task]
        raw.merge(extra) { _, new in new }
        let data = try await request("POST", "/api/executeTask", body: AnyEncodable(raw))
        return try decode(MessageResponse.self, from: data)
    }

    func tasks(page: Int) async throws -> TaskList {
        try await get(TaskList.self, "/api/tasks?page=\(page)")
    }

    func clearTasks(days: Int = 0) async throws {
        _ = try await request("POST", "/api/tasks/clear", body: DaysBody(days: days))
    }

    // MARK: - 定时任务

    func schedules(page: Int = 1) async throws -> ScheduleList {
        try await get(ScheduleList.self, "/api/schedules?page=\(page)")
    }

    func addSchedule(name: String, imei: String, task: String, params: [String: Any], spec: [String: Any], enabled: Bool) async throws {
        let body = ScheduleBody(name: name, imei: imei, task: task, params: params, spec: spec, enabled: enabled, id: nil)
        _ = try await request("POST", "/api/schedules/add", body: AnyEncodable(body.dict))
    }

    func updateSchedule(id: Int64, name: String, imei: String, task: String, params: [String: Any], spec: [String: Any], enabled: Bool) async throws {
        let body = ScheduleBody(name: name, imei: imei, task: task, params: params, spec: spec, enabled: enabled, id: id)
        _ = try await request("POST", "/api/schedules/update", body: AnyEncodable(body.dict))
    }

    func toggleSchedule(id: Int64, enabled: Bool) async throws {
        _ = try await request("POST", "/api/schedules/toggle", body: IDEnabledBody(id: id, enabled: enabled))
    }

    func deleteSchedule(id: Int64) async throws {
        _ = try await request("POST", "/api/schedules/delete", body: IDBody(id: id))
    }

    func runSchedule(id: Int64) async throws {
        _ = try await request("POST", "/api/schedules/run", body: IDBody(id: id))
    }

    // MARK: - 通话 / 短信记录

    func calls(page: Int, from: Int64 = 0, to: Int64 = 0, imei: String? = nil) async throws -> CallList {
        var q = "page=\(page)"
        if from > 0 { q += "&from=\(from)" }
        if to > 0 { q += "&to=\(to)" }
        if let imei = imei, !imei.isEmpty {
            q += "&imei=\(imei.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? imei)"
        }
        return try await get(CallList.self, "/api/calls?\(q)")
    }

    func clearCalls(days: Int = 0) async throws {
        _ = try await request("POST", "/api/calls/clear", body: DaysBody(days: days))
    }

    func deleteCall(id: Int64) async throws {
        _ = try await request("POST", "/api/calls/delete", body: IDBody(id: id))
    }

    func sms(page: Int, from: Int64 = 0, to: Int64 = 0, imei: String? = nil) async throws -> SmsList {
        var q = "page=\(page)"
        if from > 0 { q += "&from=\(from)" }
        if to > 0 { q += "&to=\(to)" }
        if let imei = imei, !imei.isEmpty {
            q += "&imei=\(imei.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? imei)"
        }
        return try await get(SmsList.self, "/api/sms?\(q)")
    }

    func clearSms(days: Int = 0) async throws {
        _ = try await request("POST", "/api/sms/clear", body: DaysBody(days: days))
    }

    func deleteSms(id: Int64) async throws {
        _ = try await request("POST", "/api/sms/delete", body: IDBody(id: id))
    }

    // MARK: - 屏蔽规则

    func blockRules(type: String? = nil, page: Int = 0, size: Int = 0) async throws -> RuleList {
        var q = ""
        if let type = type, !type.isEmpty { q += "type=\(type)&" }
        if page > 0 { q += "page=\(page)&" }
        if size > 0 { q += "size=\(size)" }
        let path = q.isEmpty ? "/api/block-rules" : "/api/block-rules?\(q)"
        return try await get(RuleList.self, path)
    }

    func addBlockRule(ruleType: String, value: String, matchMode: String, note: String = "") async throws {
        _ = try await request("POST", "/api/block-rules/add",
                              body: BlockRuleBody(ruleType: ruleType, value: value, matchMode: matchMode, note: note))
    }

    func updateBlockRule(id: Int64, value: String, matchMode: String, enabled: Int, note: String) async throws {
        _ = try await request("POST", "/api/block-rules/update",
                              body: BlockRuleUpdateBody(id: id, value: value, matchMode: matchMode, enabled: enabled, note: note))
    }

    func deleteBlockRule(id: Int64) async throws {
        _ = try await request("POST", "/api/block-rules/delete", body: IDBody(id: id))
    }

    func resetBlockRules() async throws {
        _ = try await request("POST", "/api/block-rules/reset", body: EmptyBody())
    }

    // MARK: - 设置 / 通知

    func settings() async throws -> [String: Any] {
        let data = try await request("GET", "/api/settings")
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func notifyChannels() async throws -> [NotifyChannel] {
        let data = try await request("GET", "/api/notify/channels")
        return (try? JSONDecoder().decode([NotifyChannel].self, from: data)) ?? []
    }

    func testNotify() async throws {
        _ = try await request("POST", "/api/notify/test", body: EmptyBody())
    }

    func changeUserInfo(oldPassword: String, newPassword: String) async throws {
        _ = try await request("POST", "/api/change-user-info",
                              body: ChangeUserBody(oldPassword: oldPassword, newPassword: newPassword))
    }
}

// MARK: - 请求体（与端点 json 字段对齐）

private struct LoginBody: Encodable { let username: String; let password: String }
private struct DeviceRemarkBody: Encodable { let imei: String; let name: String }
private struct DeviceIMEIBody: Encodable { let imei: String }
private struct OverviewConfigBody: Encodable { let batteryMah: Int; let avgCurrentMa: Int }
private struct DaysBody: Encodable { let days: Int }
private struct IDBody: Encodable { let id: Int64 }
private struct IDEnabledBody: Encodable { let id: Int64; let enabled: Bool }
private struct BlockRuleBody: Encodable { let ruleType: String; let value: String; let matchMode: String; let note: String }
private struct BlockRuleUpdateBody: Encodable {
    let id: Int64; let value: String; let matchMode: String; let enabled: Int; let note: String
}
private struct ChangeUserBody: Encodable { let oldPassword: String; let newPassword: String }
private struct EmptyBody: Encodable {}
private struct ScheduleBody {
    let name: String; let imei: String; let task: String
    let params: [String: Any]; let spec: [String: Any]; let enabled: Bool; let id: Int64?
    var dict: [String: Any] {
        var d: [String: Any] = ["name": name, "imei": imei, "task": task,
                                "params": params, "spec": spec, "enabled": enabled]
        if let id = id { d["id"] = id }
        return d
    }
}

/// 任意可编码字典（executeTask / addSchedule 附带参数）
struct AnyEncodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        if let dict = value as? [String: Any] {
            for (k, v) in dict {
                try encodeValue(v, into: &c, key: DynamicKey(k))
            }
        } else {
            try encodeValue(value, into: &c, key: DynamicKey("value"))
        }
    }
    private func encodeValue(_ v: Any, into c: inout KeyedEncodingContainer<DynamicKey>, key: DynamicKey) throws {
        switch v {
        case let s as String: try c.encode(s, forKey: key)
        case let i as Int: try c.encode(i, forKey: key)
        case let d as Double: try c.encode(d, forKey: key)
        case let b as Bool: try c.encode(b, forKey: key)
        case let arr as [Any]: try c.encode(arr.map { AnyEncodable($0) }, forKey: key)
        case let d as [String: Any]: try c.encode(AnyEncodable(d), forKey: key)
        default: try c.encode(String(describing: v), forKey: key)
        }
    }
}
private struct DynamicKey: CodingKey {
    var intValue: Int? { nil }
    var stringValue: String
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// API 错误（携带服务端 message）
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

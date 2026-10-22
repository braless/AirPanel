import Foundation
import Observation
import SwiftUI

// MARK: - 应用状态
//
// 所有数据都来自 server-go-v2，没有任何本地假数据。设计上的两条硬规矩：
//
// 1. 写操作走「请求 → 重新拉取」而不是本地改数组。服务端会对数据做聚合
//    （比如 spam 标记、命中次数），本地猜出来的值迟早和真实值对不上。
// 2. 401 一律当作会话结束：清 token、回到登录页，不在页面里弹错误。

@MainActor
@Observable
final class PanelStore {

    // MARK: 会话

    private(set) var session: Session?
    private(set) var client: APIClient?

    /// 启动时先读 Keychain，读完之前不要闪一下登录页
    private(set) var isBootstrapping = true
    var isLoggingIn = false
    var loginError: String?

    // MARK: 连接状态

    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// 最近一次轻量刷新（前台定时器），页脚用它显示「刚刚更新」
    private(set) var lastLiveRefresh: Date?
    var loadError: String?

    // MARK: 设备与数据

    var devices: [Device] = []
    var activeDeviceID: String = ""
    var calls: [CallRecord] = []
    var sms: [SmsRecord] = []
    var recordings: [Recording] = []
    var taskRecords: [TaskRecord] = []
    var schedules: [Schedule] = []
    var blockRules: [BlockRule] = []
    var logs: [DeviceLog] = []
    var serverLogs: [Wire.ServerLogEntry] = []

    /// 服务端的总条数：列表只拉最近两页，但「共 N 条」要说真话
    private(set) var tasksTotal = 0
    private(set) var schedulesTotal = 0

    // 通话/短信按页加载：一次 20 条，用户点「加载更多」再取下一页。
    // 一次拉 50 条看起来省事，但首屏要多等好几秒，而且 90% 的条目根本没人往下翻。
    static let pageSize = 20
    private(set) var callsTotal = 0
    private(set) var smsTotal = 0
    private(set) var isLoadingMoreCalls = false
    private(set) var isLoadingMoreSms = false
    private var callsPage = 0
    private var smsPage = 0

    var canLoadMoreCalls: Bool { calls.count < callsTotal }
    var canLoadMoreSms: Bool { sms.count < smsTotal }

    private(set) var stats: Wire.StatsSummary?
    private(set) var history: [Wire.Telemetry] = []
    /// WebDAV 未配置时 /api/recordings 会返回 success:false + error，这里原样留着给页面显示
    private(set) var recordingsError: String?

    // MARK: 设置

    private(set) var settings: Wire.Settings?
    private(set) var channelDefs: [Wire.NotifyChannelDef] = []

    // MARK: 任务控制台

    var console: [ConsoleLine] = []
    private(set) var isSending = false

    // MARK: - 启动

    init() {
        if let restored = Credentials.restore() {
            adopt(restored)
        }
        isBootstrapping = false
    }

    private func adopt(_ s: Session) {
        session = s
        client = APIClient(baseURL: s.server, token: s.token)
    }

    // MARK: - 登录

    func login(server rawServer: String, username: String, password: String, remember: Bool) async {
        loginError = nil
        guard let url = APIClient.normalize(rawServer) else {
            loginError = "服务器地址格式不对，例如 192.168.1.9:9527 或 https://panel.example.com"
            return
        }
        guard !username.isEmpty, !password.isEmpty else {
            loginError = "请填写账号和密码"
            return
        }

        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let resp = try await APIClient.login(server: url, username: username, password: password)
            let s = Session(server: url, token: resp.token, username: resp.username.isEmpty ? username : resp.username)
            Credentials.rememberPassword = remember
            Credentials.save(s, password: remember ? password : nil)
            adopt(s)
            console.removeAll()
            await refreshAll()
        } catch {
            loginError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    #if DEBUG
    /// 调试用：`-autologin "http://127.0.0.1:9527|admin|admin123"` 直接登录。
    /// 第四段写 `remember` 就走「记住密码」，用来验证 Keychain 跨冷启动恢复。
    /// 只在 Debug 构建里存在——Release 包里没有这条路径，也不读启动参数。
    func devAutoLogin(_ spec: String) async {
        let parts = spec.split(separator: "|").map(String.init)
        guard parts.count >= 3 else { return }
        await login(server: parts[0], username: parts[1], password: parts[2],
                    remember: parts.count >= 4 && parts[3] == "remember")
    }
    #endif

    func logout() async {
        // 先告诉服务端把这个 token 拉黑，失败也照样本地退出
        try? await client?.logout()
        Credentials.clearSession()
        session = nil
        client = nil
        reset()
    }

    private func reset() {
        devices = []
        activeDeviceID = ""
        calls = []
        sms = []
        recordings = []
        taskRecords = []
        schedules = []
        blockRules = []
        logs = []
        serverLogs = []
        stats = nil
        history = []
        settings = nil
        recordingsError = nil
        console = []
        loadError = nil
        lastRefresh = nil
        loadedSections = []
    }

    // MARK: - 刷新

    /// 数据分片：每一段单独记录「拿到过没有」。
    /// 只用一个全局 isRefreshing 判断的话，某个接口偶尔卡 30 秒，
    /// 所有页面都会一直转圈——而这 30 秒里其它数据其实早就到了。
    enum Section: String, CaseIterable {
        case devices, overview, settings, stats, recordings
        case calls, sms, tasks, schedules, logs, blockRules
    }

    private(set) var loadedSections: Set<Section> = []

    /// 这一段还在路上（且列表为空时调用方才需要显示转圈）
    func isLoading(_ section: Section) -> Bool {
        isRefreshing && !loadedSections.contains(section)
    }

    func refreshAll() async {
        guard client != nil else { return }
        isRefreshing = true
        loadError = nil
        // 中途被取消（页面切走 / 又下拉了一次）也必须把状态收干净，
        // 否则 isRefreshing 永远卡在 true，页面一直显示「正在读取」
        defer { isRefreshing = false }

        // 公网服务端单次往返 1.5～2 秒，十几个接口全串行要 30 秒以上——
        // 打开 App 得盯着空列表半分钟。所以除了「有依赖的」之外全部并发。
        //
        // 实测这个服务端 12 个请求一起打也是全 200（Cloudflare 只按 UA 拦，
        // 不按并发限流），所以并发宽度取 8：整体墙钟 5～6 秒，
        // 而且每个接口一回来对应页面就自己填上，不用等全部结束。
        //
        // 设备列表必须排在最前：它决定 activeDeviceID，overview 和
        // 「当前设备」相关的展示都靠它。
        await refreshDevices()

        await parallel([
            { await self.refreshOverview() },
            { await self.refreshOtherOverviews() },
            { await self.refreshSettings() },
            { await self.refreshStats() },
            { await self.refreshRecordings() },
            { await self.refreshCalls() },
            { await self.refreshSms() },
            { await self.refreshTasks() },
            { await self.refreshSchedules() },
            { await self.refreshLogs() },
            { await self.refreshBlockRules() }
        ], width: 8)

        // 录音和通话是两个独立接口，谁先回来不确定，
        // 所以「有没有录音」统一在最后回填一次，不依赖请求顺序。
        backfillRecordingFlags()

        lastRefresh = Date()
    }

    /// 轻量刷新：只更新「会自己变」的几项，给前台定时器用。
    /// 3 个请求、约 2 秒——每 60 秒跑一次也不会让服务端难受。
    func refreshLive() async {
        guard client != nil, !isRefreshing else { return }
        await parallel([
            { await self.refreshOverview() },
            { await self.refreshStats() },
            { await self.refreshDevices() }
        ], width: 3)
        lastLiveRefresh = Date()
    }

    /// 限流并发：最多 width 个任务同时在飞，完成一个补一个
    private func parallel(_ ops: [@Sendable () async -> Void], width: Int) async {
        guard !ops.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            for _ in 0..<min(width, ops.count) {
                let op = ops[next]
                next += 1
                group.addTask { await op() }
            }
            while await group.next() != nil {
                if next < ops.count {
                    let op = ops[next]
                    next += 1
                    group.addTask { await op() }
                }
            }
        }
    }

    /// 录音列表里的号码 → 通话记录上的「有录音」标记
    private func backfillRecordingFlags() {
        let numbers = Set(recordings.map(\.number))
        guard !numbers.isEmpty, !calls.isEmpty else { return }
        for i in calls.indices where numbers.contains(calls[i].number) {
            calls[i].hasRecording = true
        }
    }

    /// 统一的错误处理：401 直接踢回登录页，其余留在 loadError 上给页面显示
    private func handle(_ error: Error) {
        // 下拉刷新被系统取消、页面切走导致请求中断——这些不是「出错了」，
        // 报给用户只会看到「已取消，重试」这种莫名其妙的一行。
        if error is CancellationError { return }
        if case APIError.transport(let message) = error, message == Self.cancelledText { return }
        if let api = error as? APIError, api.isUnauthorized {
            session = nil
            client = nil
            Credentials.clearSession()
            reset()
            return
        }
        loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// 请求被取消时的统一文案，用来在 handle 里识别（不弹给用户）
    private static let cancelledText = "已取消"

    func refreshStats() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.stats) }
            stats = try await client.stats()
        } catch { handle(error) }
    }

    /// 只拉设备列表：先把「有几台、哪台在线」画出来，
    /// 遥测（overview）拆到 refreshOverview() 并发去取——
    /// 原来这里串着拉，设备列表要等两轮往返才出现。
    func refreshDevices() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.devices) }
            let list = try await client.devices()
            devices = list.map { Device(wire: $0) }
            if !devices.contains(where: { $0.imei == activeDeviceID }) {
                activeDeviceID = devices.first?.imei ?? ""
            }
        } catch { handle(error) }
    }

    /// 当前设备的遥测与历史曲线
    func refreshOverview() async {
        guard let client, !activeDeviceID.isEmpty else { return }
        do {
            defer { loadedSections.insert(.overview) }
            let ov = try await client.overview(imei: activeDeviceID)
            history = (ov.history ?? []).sorted { $0.createdAt ?? 0 < $1.createdAt ?? 0 }
            if let idx = devices.firstIndex(where: { $0.imei == activeDeviceID }) {
                devices[idx].telemetry = Self.telemetry(from: ov)
            }
        } catch { handle(error) }
    }

    /// 其余设备的遥测（列表里每张卡片都要显示电量/信号，但优先级低于当前设备）
    func refreshOtherOverviews() async {
        guard let client else { return }
        let others = devices.map(\.imei).filter { $0 != activeDeviceID }
        guard !others.isEmpty else { return }
        for imei in others {
            guard let ov = try? await client.overview(imei: imei) else { continue }
            if let idx = devices.firstIndex(where: { $0.imei == imei }) {
                devices[idx].telemetry = Self.telemetry(from: ov)
            }
        }
    }

    /// 切换当前设备：遥测与趋势跟着换
    func selectDevice(_ imei: String) async {
        activeDeviceID = imei
        guard let client else { return }
        do {
            let ov = try await client.overview(imei: imei)
            history = (ov.history ?? []).sorted { $0.createdAt ?? 0 < $1.createdAt ?? 0 }
            if let idx = devices.firstIndex(where: { $0.imei == imei }) {
                devices[idx].telemetry = Self.telemetry(from: ov)
            }
        } catch { handle(error) }
    }

    private static func telemetry(from ov: Wire.DeviceOverview) -> Telemetry {
        guard let latest = ov.latest else { return .empty }
        return Telemetry(wire: latest, battery: ov.battery, onlineSeconds: ov.onlineSeconds,
                         power: ov.power)
    }

    // MARK: 分页拉取
    //
    // 服务端每页 10 条（定时任务 5 条）。手机上翻两页就够看了，
    // 超出部分用「共 N 条」提示，不做无限滚动——每多翻一页就是一次 1.5 秒的往返。

    private func drain<T>(
        pageSize: Int,
        maxPages: Int,
        fetch: (Int, Int) async throws -> (items: [T], total: Int)
    ) async throws -> [T] {
        var out: [T] = []
        var page = 1
        while page <= maxPages {
            do {
                let (items, total) = try await fetch(page, pageSize)
                out.append(contentsOf: items)
                if items.isEmpty || out.count >= total { break }
            } catch {
                // 第一页就失败才是真失败；后续页失败说明网络抖了一下，
                // 用已经拿到的数据，别让整页变空。
                if out.isEmpty { throw error }
                break
            }
            page += 1
        }
        return out
    }

    func refreshCalls() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.calls) }
            let r = try await client.calls(page: 1, pageSize: Self.pageSize,
                                           imei: nil, keyword: nil, direction: nil)
            callsPage = 1
            callsTotal = r.total
            calls = r.calls.map { CallRecord(wire: $0) }
            // 录音没有接口字段，按号码比对回填「有无录音」标记
            backfillRecordingFlags()
        } catch { handle(error) }
    }

    /// 下一页通话，追加而不是替换
    func loadMoreCalls() async {
        guard let client, canLoadMoreCalls, !isLoadingMoreCalls else { return }
        isLoadingMoreCalls = true
        defer { isLoadingMoreCalls = false }
        do {
            let r = try await client.calls(page: callsPage + 1, pageSize: Self.pageSize,
                                           imei: nil, keyword: nil, direction: nil)
            callsPage += 1
            callsTotal = r.total
            // 期间可能有新记录插到前面，翻页会重叠，按 id 去重
            let known = Set(calls.map(\.id))
            calls.append(contentsOf: r.calls.map { CallRecord(wire: $0) }.filter { !known.contains($0.id) })
            backfillRecordingFlags()
        } catch { handle(error) }
    }

    func refreshSms() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.sms) }
            let r = try await client.sms(page: 1, pageSize: Self.pageSize,
                                         imei: nil, keyword: nil, direction: nil)
            smsPage = 1
            smsTotal = r.total
            sms = r.sms.map { SmsRecord(wire: $0) }
        } catch { handle(error) }
    }

    func loadMoreSms() async {
        guard let client, canLoadMoreSms, !isLoadingMoreSms else { return }
        isLoadingMoreSms = true
        defer { isLoadingMoreSms = false }
        do {
            let r = try await client.sms(page: smsPage + 1, pageSize: Self.pageSize,
                                         imei: nil, keyword: nil, direction: nil)
            smsPage += 1
            smsTotal = r.total
            let known = Set(sms.map(\.id))
            sms.append(contentsOf: r.sms.map { SmsRecord(wire: $0) }.filter { !known.contains($0.id) })
        } catch { handle(error) }
    }

    func refreshRecordings() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.recordings) }
            let resp = try await client.recordings()
            recordingsError = resp.isOK ? nil : (resp.error ?? "录音列表读取失败")
            recordings = resp.files.map { Recording(wire: $0) }
            backfillRecordingFlags()
        } catch { handle(error) }
    }

    func refreshTasks() async {
        guard let client else { return }
        var total = 0
        do {
            defer { loadedSections.insert(.tasks) }
            let raw = try await drain(pageSize: 10, maxPages: 2) { page, _ in
                let r = try await client.tasks(page: page)
                if page == 1 { total = r.total }
                return (r.tasks, r.total)
            }
            tasksTotal = max(total, raw.count)
            taskRecords = raw.map { TaskRecord(wire: $0) }
        } catch { handle(error) }
    }

    func refreshSchedules() async {
        guard let client else { return }
        var total = 0
        do {
            defer { loadedSections.insert(.schedules) }
            let raw = try await drain(pageSize: 5, maxPages: 2) { page, _ in
                let r = try await client.schedules(page: page)
                if page == 1 { total = r.total }
                return (r.schedules, r.total)
            }
            schedulesTotal = max(total, raw.count)
            schedules = raw.map { Schedule(wire: $0) }
        } catch { handle(error) }
    }

    func refreshLogs() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.logs) }
            async let deviceLogs = drain(pageSize: 50, maxPages: 1) { page, size in
                let r = try await client.logs(page: page, pageSize: size, imei: nil, type: nil, keyword: nil)
                return (r.logs, r.total)
            }
            async let srv = client.serverLogs(level: nil, keyword: nil, limit: 200)

            let (rawLogs, srvPage) = try await (deviceLogs, srv)
            logs = rawLogs.map { DeviceLog(wire: $0) }
            serverLogs = srvPage.lines
        } catch { handle(error) }
    }

    func refreshBlockRules() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.blockRules) }
            let resp = try await client.blockRules(type: nil)
            blockRules = resp.rules.map { BlockRule(wire: $0) }
        } catch { handle(error) }
    }

    func refreshSettings() async {
        guard let client else { return }
        do {
            defer { loadedSections.insert(.settings) }
            async let s = client.settings()
            async let defs = client.notifyChannels()
            settings = try await s
            channelDefs = try await defs
        } catch { handle(error) }
    }

    // MARK: - 派生

    var activeDevice: Device? {
        devices.first { $0.imei == activeDeviceID }
    }

    var onlineCount: Int {
        stats?.online ?? devices.filter(\.isOnline).count
    }

    var todayCallCount: Int {
        stats?.callsToday ?? calls.filter { Calendar.current.isDateInToday($0.startedAt) }.count
    }

    var todaySmsCount: Int {
        stats?.smsToday ?? sms.filter { Calendar.current.isDateInToday($0.time) }.count
    }

    var todayTaskCount: Int {
        stats?.tasksToday ?? taskRecords.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    /// 和其他三个数字保持同一口径：都算「今天」。
    /// 服务端的 stats/summary 没有拦截数，只能从已加载的记录里数。
    var spamCount: Int {
        let today = calls.filter { Calendar.current.isDateInToday($0.startedAt) && $0.spamRule != nil }.count
            + sms.filter { Calendar.current.isDateInToday($0.time) && $0.spamRule != nil }.count
        return today
    }

    var recentEvents: [DeviceLog] {
        Array(logs.sorted { $0.time > $1.time }.prefix(4))
    }

    /// 概览页趋势图：服务端只存电压，电量按同一套分段线性换算（对齐 api_devices.go）
    var signalTrend: [Double] {
        history.map { Double($0.rssi) }
    }

    var batteryTrend: [Double] {
        history.map { Double(Self.voltageToPercent($0.voltage)) }
    }

    static func voltageToPercent(_ mv: Int) -> Int {
        let v = Double(mv) / 1000
        switch mv {
        case ...0: return 0
        case ...3300: return 0
        case 4200...: return 100
        default: break
        }
        if v <= 3.60 { return Int((v - 3.30) / (3.60 - 3.30) * 30 + 0.5) }
        if v <= 3.80 { return Int((v - 3.60) / (3.80 - 3.60) * (60 - 30) + 30 + 0.5) }
        if v <= 4.05 { return Int((v - 3.80) / (4.05 - 3.80) * (85 - 60) + 60 + 0.5) }
        return Int((v - 4.05) / (4.20 - 4.05) * (100 - 85) + 85 + 0.5)
    }

    // MARK: - 设置项代理
    //
    // 页面只认中文名与布尔值，和 wire 字段的映射收在这里，
    // 免得每个 View 都自己翻译一遍「green → 绿色」。

    private static let ledPairs: [(wire: String, cn: String)] = [
        ("off", "关闭"), ("red", "红色"), ("green", "绿色"), ("blue", "蓝色"),
        ("yellow", "黄色"), ("purple", "紫色"), ("cyan", "青色"), ("white", "白色")
    ]

    var notifyChannels: Set<String> {
        get { Set(settings?.notifyChannels ?? []) }
        set { settings?.notifyChannels = newValue.sorted() }
    }

    var notifyEnabled: Bool {
        get { settings?.notifyEnabled ?? false }
        set { settings?.notifyEnabled = newValue }
    }

    var ledEnabled: Bool {
        get { settings?.smsLed.enabled ?? false }
        set { settings?.smsLed.enabled = newValue; settings?.callLed.enabled = newValue }
    }

    var ledColor: String {
        get {
            let wire = settings?.smsLed.color ?? "green"
            return Self.ledPairs.first { $0.wire == wire }?.cn ?? "绿色"
        }
        set {
            let wire = Self.ledPairs.first { $0.cn == newValue }?.wire ?? "green"
            settings?.smsLed.color = wire
            settings?.callLed.color = wire
        }
    }

    var ledBlink: Bool {
        get { settings?.smsLed.blink ?? false }
        set { settings?.smsLed.blink = newValue; settings?.callLed.blink = newValue }
    }

    var webdavURL: String {
        get { settings?.webdav.url ?? "" }
        set { settings?.webdav.url = newValue }
    }

    var webdavDir: String {
        get { settings?.webdav.dir ?? "" }
        set { settings?.webdav.dir = newValue }
    }

    var brandTitle: String {
        get { settings?.brand.title ?? "" }
        set { settings?.brand.title = newValue }
    }

    var brandLogo: String {
        get { settings?.brand.logo ?? "" }
        set { settings?.brand.logo = newValue }
    }

    /// 管理员头像：服务端存的是字符串（图床直链 / 站内相对路径 / 旧版 base64）
    var brandAvatar: String {
        get { settings?.brand.avatar ?? "" }
        set { settings?.brand.avatar = newValue }
    }

    var savedUsername: String { session?.username ?? "" }
    var serverHost: String {
        guard let s = session?.server else { return "" }
        return s.host() ?? s.absoluteString
    }

    // MARK: - 指令下发

    func send(_ command: Command, params: [String: String] = [:]) {
        guard !isSending else { return }
        guard let client, let device = activeDevice else {
            console.append(ConsoleLine(kind: .error, text: "没有可用设备，先让设备连上 broker", time: .now))
            return
        }

        let payload = Self.jsonPreview(params)
        console.append(ConsoleLine(kind: .sent,
                                   text: "cmd/\(device.imei) › \(command.id) \(payload)",
                                   time: .now))
        isSending = true

        Task {
            defer { isSending = false }
            do {
                let resp = try await client.executeTask(imei: device.imei, task: command.id, params: params)
                if resp.success {
                    let text = resp.result?.compact ?? "ok"
                    console.append(ConsoleLine(kind: .reply, text: text, time: .now))
                } else {
                    console.append(ConsoleLine(kind: .error,
                                               text: resp.message ?? "设备未响应", time: .now))
                }
            } catch {
                console.append(ConsoleLine(kind: .error,
                                           text: (error as? APIError)?.errorDescription ?? error.localizedDescription,
                                           time: .now))
                handle(error)
            }
            await refreshTasks()
            await refreshDevices()
        }
    }

    /// 立即执行一次定时任务
    func runSchedule(_ id: String) async {
        guard let client, let raw = schedules.first(where: { $0.id == id })?.rawID else { return }
        do {
            let resp = try await client.runSchedule(id: raw)
            console.append(ConsoleLine(kind: resp.success ? .reply : .error,
                                       text: resp.success ? (resp.result?.compact ?? "ok")
                                                          : (resp.message ?? "执行失败"),
                                       time: .now))
            await refreshTasks()
        } catch { handle(error) }
    }

    func clearConsole() {
        console.removeAll()
    }

    private static func jsonPreview(_ params: [String: String]) -> String {
        guard !params.isEmpty else { return "{}" }
        let body = params
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\"\($0.value)\"" }
            .joined(separator: ",")
        return "{\(body)}"
    }

    // MARK: - 写操作

    func toggleSchedule(_ id: String) async {
        guard let client, let idx = schedules.firstIndex(where: { $0.id == id }) else { return }
        let target = !schedules[idx].enabled
        // 先本地翻转给即时反馈，失败再回滚
        schedules[idx].enabled = target
        do {
            try await client.toggleSchedule(id: schedules[idx].rawID, enabled: target)
        } catch {
            schedules[idx].enabled = !target
            handle(error)
        }
    }

    func toggleBlockRule(_ id: String) async {
        guard let client, let idx = blockRules.firstIndex(where: { $0.id == id }) else { return }
        let rule = blockRules[idx]
        let target = !rule.enabled
        blockRules[idx].enabled = target
        do {
            try await client.updateBlockRule(id: rule.rawID, ruleType: rule.kind.wire,
                                             value: rule.value,
                                             matchMode: BlockRule.wireMode(rule.matchMode),
                                             note: rule.note, enabled: target)
        } catch {
            blockRules[idx].enabled = !target
            handle(error)
        }
    }

    func addBlockRule(kind: BlockKind, value: String, matchMode: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.addBlockRule(ruleType: kind.wire, value: value,
                                          matchMode: BlockRule.wireMode(matchMode), note: "")
            await refreshBlockRules()
            return true
        } catch { handle(error); return false }
    }

    func deleteBlockRule(_ id: String) async {
        guard let client, let raw = blockRules.first(where: { $0.id == id })?.rawID else { return }
        do {
            try await client.deleteBlockRule(id: raw)
            await refreshBlockRules()
        } catch { handle(error) }
    }

    /// 删单条：先本地摘掉再请求（乐观更新），失败放回原位。
    /// 等网络往返再消失的话，用户划完会有半秒「怎么没反应」的空窗，
    /// 那半秒就是之前「删除动画卡顿」的主要观感来源。
    /// 也不重拉第一页——重拉会把已经翻到的页数打回原点，位置会跳。
    func deleteCall(_ id: String) async {
        guard let client, let raw = calls.first(where: { $0.id == id })?.rawID else { return }
        let backup = calls.first { $0.id == id }
        let index = calls.firstIndex { $0.id == id }

        withAnimation(Motion.layout) {
            calls.removeAll { $0.id == id }
            callsTotal = max(0, callsTotal - 1)
        }

        do {
            try await client.deleteCall(id: raw)
            await refreshStats()
        } catch {
            // 服务端没删掉：把行放回去，让用户知道「这条还在」
            if let backup, let index {
                withAnimation(Motion.layout) {
                    calls.insert(backup, at: min(index, calls.count))
                    callsTotal += 1
                }
            }
            handle(error)
        }
    }

    func deleteSms(_ id: String) async {
        guard let client, let raw = sms.first(where: { $0.id == id })?.rawID else { return }
        let backup = sms.first { $0.id == id }
        let index = sms.firstIndex { $0.id == id }

        withAnimation(Motion.layout) {
            sms.removeAll { $0.id == id }
            smsTotal = max(0, smsTotal - 1)
        }

        do {
            try await client.deleteSms(id: raw)
            await refreshStats()
        } catch {
            if let backup, let index {
                withAnimation(Motion.layout) {
                    sms.insert(backup, at: min(index, sms.count))
                    smsTotal += 1
                }
            }
            handle(error)
        }
    }

    func deleteDevice(_ imei: String) async {
        guard let client else { return }
        do {
            try await client.deleteDevice(imei: imei)
            await refreshDevices()
            await refreshStats()
        } catch { handle(error) }
    }

    func renameDevice(_ imei: String, name: String) async {
        guard let client else { return }
        do {
            try await client.remarkDevice(imei: imei, name: name)
            await refreshDevices()
        } catch { handle(error) }
    }

    /// 删录音：同样乐观更新。文件删掉就找不回来了，所以失败必须放回去。
    func deleteRecording(_ fileName: String) async {
        guard let client else { return }
        let backup = recordings
        withAnimation(Motion.layout) {
            recordings.removeAll { $0.fileName == fileName }
        }
        do {
            try await client.deleteRecording(file: fileName)
        } catch {
            withAnimation(Motion.layout) { recordings = backup }
            handle(error)
        }
    }

    // MARK: 设置保存

    func saveSettings() async -> Bool {
        guard let client, let s = settings else { return false }
        do {
            try await client.saveSettings(
                notifyEnabled: s.notifyEnabled,
                notifyChannels: s.notifyChannels,
                notifyConfig: s.notifyConfig,
                smsLed: ["enabled": s.smsLed.enabled, "color": s.smsLed.color,
                         "blink": s.smsLed.blink, "duration": s.smsLed.duration],
                callLed: ["enabled": s.callLed.enabled, "color": s.callLed.color,
                          "blink": s.callLed.blink, "duration": s.callLed.duration],
                webdav: ["url": s.webdav.url, "username": s.webdav.username,
                         "password": s.webdav.password, "dir": s.webdav.dir],
                brand: ["title": s.brand.title, "logo": s.brand.logo, "avatar": s.brand.avatar]
            )
            return true
        } catch { handle(error); return false }
    }

    func testNotify() async -> (ok: Bool, message: String) {
        guard let client else { return (false, "未登录") }
        let channels = settings?.notifyChannels ?? []
        guard !channels.isEmpty else { return (false, "请先选择至少一个通知渠道") }
        do {
            let r = try await client.testNotify(channels: channels, config: settings?.notifyConfig ?? [:])
            return (r.success ?? false, r.message ?? "已发送")
        } catch {
            handle(error)
            return (false, (error as? APIError)?.errorDescription ?? "发送失败")
        }
    }

    // MARK: 设备端配置（录音 / 省电）
    //
    // 这两项不是面板设置，而是设备 nvm_para.lua 里的开关。
    // 服务端没有对应端点，只能走设备命令：get_config 取全文 → 就地改几行 → set_config 写回。
    // 与 server-go-v2/static/js/pages/settings.js 的 patchLuaConfig 完全一致的策略。

    private(set) var deviceConfigText: String = ""
    private(set) var deviceConfigLoading = false
    private(set) var deviceFlags: [String: Bool] = [:]
    private(set) var devicePower: [String: Any] = [:]

    var recordEnabled: Bool {
        get { deviceFlags["RECORD_ENABLE"] ?? true }
        set { deviceFlags["RECORD_ENABLE"] = newValue }
    }

    var ttsBeforeEnabled: Bool {
        get { deviceFlags["TTS_BEFORE_ENABLE"] ?? true }
        set { deviceFlags["TTS_BEFORE_ENABLE"] = newValue }
    }

    var powerSaveEnabled: Bool {
        get { devicePower["POWERSAVE_ENABLE"] as? Bool ?? false }
        set { devicePower["POWERSAVE_ENABLE"] = newValue }
    }

    var powerSaveWindow: String {
        let start = devicePower["POWERSAVE_START_HOUR"] as? Int ?? 1
        let end = devicePower["POWERSAVE_END_HOUR"] as? Int ?? 8
        return String(format: "%02d:00 – %02d:00", start, end)
    }

    /// 读取设备当前配置并解析出关心的键
    func loadDeviceConfig() async {
        guard let client, let device = activeDevice else { return }
        deviceConfigLoading = true
        defer { deviceConfigLoading = false }
        do {
            let resp = try await client.executeTask(imei: device.imei, task: "get_config", params: [:])
            let text = resp.result?.configText ?? ""
            deviceConfigText = text
            let parsed = Self.parseLua(text)
            deviceFlags = [
                "RECORD_ENABLE": (parsed["RECORD_ENABLE"] as? Bool) ?? true,
                "TTS_BEFORE_ENABLE": (parsed["TTS_BEFORE_ENABLE"] as? Bool) ?? true
            ]
            devicePower = parsed
        } catch { handle(error) }
    }

    /// 把改动写回设备：取最新全文 → 打补丁 → set_config
    func applyDeviceConfig(_ kv: [String: Any]) async -> Bool {
        guard let client, let device = activeDevice else { return false }
        do {
            let resp = try await client.executeTask(imei: device.imei, task: "get_config", params: [:])
            let text = resp.result?.configText ?? deviceConfigText
            guard !text.isEmpty else { loadError = "设备未返回配置内容"; return false }

            let patched = Self.patchLua(text, kv)
            let write = try await client.executeTask(imei: device.imei, task: "set_config",
                                                     params: ["configText": patched])
            if write.success == false {
                loadError = write.message ?? "写入失败"
                return false
            }
            deviceConfigText = patched
            return true
        } catch { handle(error); return false }
    }

    private static func luaLiteral(_ v: Any) -> String {
        switch v {
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let d as Double: return String(Int(d))
        default: return "\"\(v)\""
        }
    }

    /// 按行替换已有的 `KEY = value`，缺的键追加到末尾
    static func patchLua(_ text: String, _ kv: [String: Any]) -> String {
        var lines = text.components(separatedBy: "\n")
        var done = Set<String>()
        for i in lines.indices {
            let line = lines[i]
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                  let value = kv[key], !done.contains(key) else { continue }
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            lines[i] = "\(indent)\(key) = \(luaLiteral(value))"
            done.insert(key)
        }
        let missing = kv.keys.filter { !done.contains($0) }
        if !missing.isEmpty {
            var out = lines.joined(separator: "\n")
            while let last = out.last, last.isWhitespace { out.removeLast() }
            out += "\n" + missing.sorted().map { "\($0) = \(luaLiteral(kv[$0]!))" }.joined(separator: "\n") + "\n"
            return out
        }
        return lines.joined(separator: "\n")
    }

    /// 只认顶格的 `KEY = 字面量`，够解析 nvm_para.lua 这种扁平配置
    static func parseLua(_ text: String) -> [String: Any] {
        var out: [String: Any] = [:]
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("--"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            while let last = value.last, last == "," || last == ";" { value.removeLast() }
            if value == "true" { out[key] = true }
            else if value == "false" { out[key] = false }
            else if let i = Int(value) { out[key] = i }
            else if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                out[key] = String(value.dropFirst().dropLast())
            }
        }
        return out
    }

    // MARK: - 录音播放
    //
    // 录音在 WebDAV 上，接口要 Bearer 才能取，所以不能把 URL 直接丢给播放器。
    // 先取 Data 再本地播，进度就是真实的播放进度。

    func recordingData(file: String) async throws -> Data {
        guard let client else { throw APIError.unauthorized("未登录") }
        return try await client.recordingData(file: file)
    }

    // MARK: - 运维

    func restartServer() async -> Bool {
        guard let client else { return false }
        do {
            let r = try await client.restart()
            return r.success ?? false
        } catch { handle(error); return false }
    }
}

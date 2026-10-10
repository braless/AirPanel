import SwiftUI
import Combine
import WidgetKit

/// 外观模式：自动（跟随系统）/ 浅色 / 深色
enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "自动"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    /// 应用到 preferredColorScheme；auto 返回 nil 以跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 全局应用状态：服务器地址、登录态、设备列表、当前选中设备
@MainActor
final class AppStore: ObservableObject {
    @Published var baseURLText: String
    @Published var token: String
    @Published var loggedIn: Bool
    @Published var devices: [Device] = []
    @Published var selectedIMEI: String?
    @Published var appearance: Appearance
    @Published var selectedTab: Int = 0
    @Published var pendingTask: String?        // 小组件快捷命令预选的任务类型
    @Published var lastBattery: Int = -1        // 遥测快照（供小组件设备信息）
    @Published var lastCsq: Int = -1
    @Published var lastNetMode: String = ""
    @Published var lastCharging: Bool = false
    @Published var rememberPassword: Bool = false

    private let defaults = UserDefaults.standard
    private static let kBase = "airpanel.baseURL"
    private static let kToken = "airpanel.token"
    private static let kAppearance = "airpanel.appearance"
    private static let kRemember = "airpanel.remember"
    private static let kSavedUser = "airpanel.savedUser"
    private static let kSavedPwd = "airpanel.savedPwd"

    init() {
        baseURLText = defaults.string(forKey: Self.kBase) ?? ""
        let t = defaults.string(forKey: Self.kToken) ?? ""
        token = t
        loggedIn = !t.isEmpty
        appearance = Appearance(rawValue: defaults.string(forKey: Self.kAppearance) ?? "") ?? .auto
        rememberPassword = defaults.bool(forKey: Self.kRemember)
        if loggedIn {
            Task { await refreshDevices(); await loadRecordsForWidget() }
        }
    }

    /// 拉取最近短信与来电写入小组件共享区（登录后 / 打开时调用，避免依赖 Widget 自身网络）
    func loadRecordsForWidget() async {
        guard loggedIn else { return }
        if let c = try? await api.calls(page: 1) {
            saveCallsForWidget(c.calls.prefix(8).map {
                SharedWidgetData.CallItem(number: $0.number, direction: $0.direction,
                                          time: $0.startedAt, spam: $0.spam > 0)
            })
        }
        if let s = try? await api.sms(page: 1) {
            saveSmsForWidget(s.sms.prefix(8).map {
                SharedWidgetData.SmsItem(number: $0.number, content: $0.content,
                                         time: $0.createdAt, spam: $0.spam > 0)
            })
        }
    }

    /// 记住的账号 / 密码（仅在开启“记住密码”时存在）
    var savedUsername: String? { defaults.string(forKey: Self.kSavedUser) }
    var savedPassword: String? { defaults.string(forKey: Self.kSavedPwd) }

    /// 切换外观模式并持久化
    func setAppearance(_ a: Appearance) {
        appearance = a
        defaults.set(a.rawValue, forKey: Self.kAppearance)
    }

    /// 当前 API 客户端（基于已保存的地址与令牌）
    var api: APIClient {
        APIClient(baseURL: URL(string: baseURLText) ?? URL(string: "http://localhost")!,
                  token: token)
    }

    var selectedDevice: Device? {
        guard let imei = selectedIMEI else { return devices.first }
        return devices.first { $0.imei == imei } ?? devices.first
    }

    /// 登录并保存令牌 / 服务器地址；remember 为真则记住账号密码
    func login(username: String, password: String, baseURL: String, remember: Bool) async throws {
        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let api = APIClient(baseURL: URL(string: normalized) ?? URL(string: "http://localhost")!,
                            token: "")
        let tk = try await api.login(username: username, password: password)
        self.baseURLText = normalized
        self.token = tk
        self.loggedIn = true
        self.rememberPassword = remember
        defaults.set(normalized, forKey: Self.kBase)
        defaults.set(tk, forKey: Self.kToken)
        defaults.set(remember, forKey: Self.kRemember)
        // 写入共享区供桌面小组件直连（仅存地址 + 令牌，不存密码）
        SharedWidgetData.saveConfig(baseURL: normalized, token: tk)
        if remember {
            defaults.set(username, forKey: Self.kSavedUser)
            defaults.set(password, forKey: Self.kSavedPwd)
        } else {
            defaults.removeObject(forKey: Self.kSavedUser)
            defaults.removeObject(forKey: Self.kSavedPwd)
        }
        await refreshDevices()
        await loadRecordsForWidget()
    }

    func logout() async {
        let api = self.api
        if loggedIn { try? await api.logout() }
        token = ""
        loggedIn = false
        devices = []
        selectedIMEI = nil
        defaults.removeObject(forKey: Self.kToken)
        SharedWidgetData.clearConfig()
    }

    /// 拉取设备列表并尽量保持当前选中
    func refreshDevices() async {
        do {
            let list = try await api.userPool()
            devices = list
            if let sel = selectedIMEI, !list.contains(where: { $0.imei == sel }) {
                selectedIMEI = list.first?.imei
            } else if selectedIMEI == nil {
                selectedIMEI = list.first?.imei
            }
        } catch {
            // 静默失败，保留旧列表
        }
    }

    func select(imei: String) {
        selectedIMEI = imei
        refreshWidgetData()
    }

    /// 记录最新遥测并刷新小组件设备信息
    func rememberTelemetry(battery: Int, csq: Int, netMode: String, charging: Bool) {
        lastBattery = battery; lastCsq = csq; lastNetMode = netMode; lastCharging = charging
        refreshWidgetData()
    }

    /// 把当前设备信息写入小组件共享区并刷新小组件
    func refreshWidgetData() {
        guard let dev = selectedDevice else { return }
        let item = SharedWidgetData.DeviceItem(
            imei: dev.imei, name: dev.name, phone: dev.phone,
            online: dev.connected, battery: lastBattery, csq: lastCsq, netMode: lastNetMode,
            lastSeen: dev.lastSeen)
        SharedWidgetData.saveDevice(item)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 写入最近短信 / 来电到小组件共享区
    func saveSmsForWidget(_ items: [SharedWidgetData.SmsItem]) {
        SharedWidgetData.saveSms(items)
        WidgetCenter.shared.reloadTimelines(ofKind: "AirPanelSMS")
    }
    func saveCallsForWidget(_ items: [SharedWidgetData.CallItem]) {
        SharedWidgetData.saveCalls(items)
        WidgetCenter.shared.reloadTimelines(ofKind: "AirPanelCalls")
    }

    /// 处理 airpanel:// 快捷命令 URL（小组件点击唤起）
    func handle(url: URL) {
        guard let scheme = url.scheme, scheme.lowercased() == "airpanel" else { return }
        let host = url.host ?? ""
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]
        switch host {
        case "command":
            selectedTab = 3                 // 任务指挥台
            if let task = params["task"] { pendingTask = task }
        case "records":
            selectedTab = 2                 // 记录
        case "devices":
            selectedTab = 1                 // 设备
        default:
            break
        }
    }
}

/// 通用加载状态
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    static func == (a: LoadState, b: LoadState) -> Bool {
        switch (a, b) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded): return true
        case (.failed(let x), .failed(let y)): return x == y
        default: return false
        }
    }
}

// MARK: - 格式化工具

enum Fmt {
    /// Unix 秒 → "MM-dd HH:mm"
    static func time(_ t: Int64) -> String {
        guard t > 0 else { return "-" }
        let d = Date(timeIntervalSince1970: TimeInterval(t))
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    /// 时长（秒）→ "X小时Y分" / "Y分Z秒"
    static func duration(_ sec: Int64) -> String {
        if sec <= 0 { return "-" }
        let h = sec / 3600, m = (sec % 3600) / 60, s = sec % 60
        if h > 0 { return "\(h)小时\(m)分" }
        if m > 0 { return "\(m)分\(s)秒" }
        return "\(s)秒"
    }

    /// 在线时长（秒）→ 人性化
    static func online(_ sec: Int64) -> String {
        if sec < 0 { return "离线" }
        let h = sec / 3600, m = (sec % 3600) / 60
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分钟"
    }
}

// MARK: - 玻璃拟态样式常量

enum Theme {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)          // #0A84FF
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)          // #30D158
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.04)          // #FF9F0A
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)             // #FF453A
    static let purple = Color(red: 0.75, green: 0.35, blue: 0.95)         // #BF5AF2
    static let teal = Color(red: 0.39, green: 0.82, blue: 1.0)            // #64D2FF

    /// 依据系统深浅色自动切换的动态色
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    /// 页面背景
    static let background = dynamic(
        light: Color(red: 0.93, green: 0.94, blue: 0.96),   // 浅色浅灰底
        dark: Color(red: 0.04, green: 0.06, blue: 0.10))    // 深色底

    /// 卡片 / 输入框等半透明填充底（已封装深浅差异）
    static let fill = dynamic(
        light: Color.black.opacity(0.05),
        dark: Color.white.opacity(0.07))

    /// 描边
    static let stroke = dynamic(
        light: Color.black.opacity(0.12),
        dark: Color.white.opacity(0.14))

    /// 主要文字 / 图标前景
    static let text = dynamic(
        light: Color.black.opacity(0.88),
        dark: Color.white)

    /// 玻璃卡片视图修饰器
    static func glass(_ radius: CGFloat = 20) -> some ViewModifier {
        GlassModifier(radius: radius)
    }
}

struct GlassModifier: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

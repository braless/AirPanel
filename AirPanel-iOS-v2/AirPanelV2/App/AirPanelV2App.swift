import SwiftUI

@main
struct AirPanelV2App: App {
    @State private var store = PanelStore()

    /// 外观偏好存在 UserDefaults，冷启动也生效（登录页就已经是用户选的外观）。
    /// 调试用的 `-appearance light|dark|system` 不用单独解析：Foundation 会把
    /// 命令行里的 `-key value` 放进 NSArgumentDomain，`@AppStorage` 直接就读到了。
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.system.rawValue

    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootGate()
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

// MARK: - 会话闸门
//
// 没登录只给登录页，登录后才挂 TabView。
// 两层之间用淡入切换而不是滑动：这不是导航，是「换了一个世界」。

struct RootGate: View {
    @Environment(PanelStore.self) private var store

    /// 截图/演示用：-login 强制停在登录页
    private var forceLogin: Bool {
        ProcessInfo.processInfo.arguments.contains("-login")
    }

    private var showLogin: Bool { store.session == nil || forceLogin }

    var body: some View {
        ZStack {
            #if DEBUG
            // 小组件预览：本机没法长按桌面加小组件，用同一套视图在这里渲染
            if ProcessInfo.processInfo.arguments.contains("-widgetpreview") {
                WidgetPreviewScreen()
            } else if showLogin {
                LoginView()
                    .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity)
            }
            #else
            if showLogin {
                LoginView()
                    .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity)
            }
            #endif
        }
        .motion(Motion.fade, value: showLogin)
        .task {
            #if DEBUG
            // 截图 / 联调：-autologin "http://127.0.0.1:9527|admin|admin123"
            let args = ProcessInfo.processInfo.arguments
            // 带这个参数就强制重登（方便在多个服务端之间来回切换验证）
            if let i = args.firstIndex(of: "-autologin"), i + 1 < args.count {
                await store.devAutoLogin(args[i + 1])
                return
            }
            #endif
            // 冷启动时 token 已在，直接把首屏数据拉满
            if store.session != nil, !forceLogin {
                await store.refreshAll()
            }
        }
    }
}

// MARK: - 主框架
//
// 5 个 Tab，每个 Tab 自带 NavigationStack（iOS 26 的玻璃 TabBar 会浮在内容之上，
// 滚动时向下收起，把屏幕让给数据）。
// 支持 -tab <name> 启动参数，方便截图与演示直达某个页面。

enum AppTab: String, Hashable, CaseIterable {
    case overview, comms, automation, devices, settings

    var title: String {
        switch self {
        case .overview: return "概览"
        case .comms: return "通信"
        case .automation: return "自动化"
        case .devices: return "设备"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .comms: return "phone.bubble.left"
        // 自动化不用闪电：闪电读作「充电/快」，和「定时任务、指令下发」没关系。
        // 魔杖更贴近「编排好的自动化」这件事。
        case .automation: return "wand.and.stars"
        case .devices: return "cpu"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(PanelStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = RootView.initialTab

    /// 前台自动刷新间隔。60 秒：够快能看到电量变化，又不至于一直打服务端。
    /// Debug 下可用 `-autorefresh 10` 缩短，方便验证定时器真的在跑。
    private var autoRefreshInterval: Duration {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-autorefresh"), i + 1 < args.count,
           let seconds = Int(args[i + 1]), seconds > 0 {
            return .seconds(seconds)
        }
        #endif
        return .seconds(60)
    }

    private static var initialTab: AppTab {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count,
           let t = AppTab(rawValue: args[i + 1]) {
            return t
        }
        return .overview
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(AppTab.overview.title, systemImage: AppTab.overview.symbol, value: AppTab.overview) {
                OverviewView()
            }
            // 原来用「双气泡」bubble.left.and.text.bubble.right：这个符号本身宽一圈，
            // 系统又会把 Tab 图标统一归一化，改字号没用（试过，系统忽略）。
            // 换成电话+气泡，含义还是「通话+短信」，视觉重量和其它四个齐平。
            Tab(AppTab.comms.title, systemImage: AppTab.comms.symbol, value: AppTab.comms) {
                CommsView()
            }
            Tab(AppTab.automation.title, systemImage: AppTab.automation.symbol, value: AppTab.automation) {
                AutomationView()
            }
            Tab(AppTab.devices.title, systemImage: AppTab.devices.symbol, value: AppTab.devices) {
                DevicesView()
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // 让 TabBar 选中态、按钮、开关都跟着主题配色走
        .tint(Theme.accent)
        .task {
            // 前台定时轻量刷新：只更新概览/统计/设备三个接口。
            // 之前只有下拉才会更新，页面放着不动就会一直显示几分钟前的数据。
            while !Task.isCancelled {
                try? await Task.sleep(for: autoRefreshInterval)
                guard !Task.isCancelled else { break }
                await store.refreshLive()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 从后台回来立刻拉一次，别让用户先看到一段过期数据
            guard phase == .active, store.session != nil else { return }
            Task { await store.refreshLive() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = store.loadError {
                ErrorBanner(message: error) {
                    Task { await store.refreshAll() }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .motion(Motion.fade, value: store.loadError)
    }
}

// MARK: - 错误提示条
//
// 网络断了、token 过期、服务端返回了看不懂的东西——这些必须让用户看到，
// 而不是安静地显示一个空列表让人以为「真的没数据」。

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 1)
            Text(message)
                .font(Theme.micro)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button("重试", action: retry)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.danger.opacity(0.14))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.25), lineWidth: 0.75)
        }
    }
}

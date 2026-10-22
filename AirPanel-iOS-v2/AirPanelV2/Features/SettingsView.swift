import SwiftUI

// MARK: - 设置
//
// 分三类，来源完全不同，界面上必须让人看得出来：
//   · 面板设置（通知 / 灯光 / WebDAV / 品牌）→ 存服务端数据库，POST /api/settings/save
//   · 设备设置（录音 / 省电）→ 存在设备 nvm_para.lua，走 get_config → set_config
//   · 只读数据（屏蔽命中、日志）→ 直接来自接口
//
// 所以每个页面底部都有一个明确的保存按钮，而不是「改了就自动存」——
// 设备配置要下发到几公里外的模组，不该由一次误触触发。

enum SettingsPage: Hashable {
    case notify, led, power, record, storage, block, logs, brand
}

struct SettingsView: View {
    @Environment(PanelStore.self) private var store
    @State private var path: [SettingsPage] = SettingsView.initialPath

    /// 外观偏好：改了立刻生效（根视图读同一个 key）
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.system.rawValue

    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }

    private var appearanceBinding: Binding<Appearance> {
        Binding(get: { Appearance(rawValue: appearanceRaw) ?? .system },
                set: { appearanceRaw = $0.rawValue })
    }

    /// 六个色点。选中的多一圈描边 + 对勾，色盲用户也能靠形状分辨。
    private var accentSwatches: some View {
        HStack(spacing: 9) {
            ForEach(AccentChoice.allCases) { option in
                let selected = AccentTheme.shared.choice == option
                Button {
                    withAnimation(Motion.fade) { AccentTheme.shared.choice = option }
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 21, height: 21)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Theme.ink.opacity(selected ? 0.22 : 0), lineWidth: 2)
                                .padding(-3.5)
                        }
                }
                .buttonStyle(.pressable(scale: 0.88))
                .accessibilityLabel("主题配色 \(option.label)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private static var initialPath: [SettingsPage] {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-settings"), i + 1 < args.count else { return [] }
        switch args[i + 1] {
        case "notify": return [.notify]
        case "led": return [.led]
        case "power": return [.power]
        case "record": return [.record]
        case "storage": return [.storage]
        case "block": return [.block]
        case "logs": return [.logs]
        case "brand": return [.brand]
        default: return []
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    PageHeader("设置", subtitle: headerSubtitle) {
                        GlassIconButton(symbol: "arrow.clockwise") {
                            Task { await store.refreshAll() }
                        }
                    }

                    accountCard

                    section("通知与提示") {
                        NavigationLink(value: SettingsPage.notify) {
                            SettingsRow(symbol: "bell.badge", tint: Theme.accent,
                                        title: "通知推送",
                                        value: "\(store.notifyChannels.count) 个渠道")
                        }
                        RowDivider(inset: 46)
                        NavigationLink(value: SettingsPage.led) {
                            SettingsRow(symbol: "lightbulb", tint: Theme.warn,
                                        title: "灯光指示",
                                        value: store.ledEnabled ? store.ledColor : "关闭")
                        }
                    }

                    section("通信与存储") {
                        NavigationLink(value: SettingsPage.record) {
                            SettingsRow(symbol: "waveform", tint: Theme.violet,
                                        title: "通话录音",
                                        value: store.recordEnabled ? "已开启" : "关闭")
                        }
                        RowDivider(inset: 46)
                        NavigationLink(value: SettingsPage.power) {
                            SettingsRow(symbol: "battery.75percent", tint: Theme.online,
                                        title: "省电模式",
                                        value: store.powerSaveEnabled ? store.powerSaveWindow : "关闭")
                        }
                        RowDivider(inset: 46)
                        NavigationLink(value: SettingsPage.storage) {
                            SettingsRow(symbol: "externaldrive.connected.to.line.below", tint: Theme.cyan,
                                        title: "存储配置",
                                        value: store.webdavURL.isEmpty ? "未配置" : "WebDAV")
                        }
                    }

                    section("安全与记录") {
                        NavigationLink(value: SettingsPage.block) {
                            SettingsRow(symbol: "shield.lefthalf.filled", tint: Theme.danger,
                                        title: "屏蔽配置",
                                        value: "\(store.blockRules.filter(\.enabled).count) 条启用")
                        }
                        RowDivider(inset: 46)
                        NavigationLink(value: SettingsPage.logs) {
                            SettingsRow(symbol: "list.bullet.rectangle", tint: Theme.ink2,
                                        title: "日志中心",
                                        value: "\(store.logs.count) 条")
                        }
                    }

                    section("外观与界面") {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            GlassSegmented(items: Appearance.allCases.map { (value: $0, label: $0.label) },
                                           selection: appearanceBinding)
                            HStack(spacing: 5) {
                                Image(systemName: appearance.symbol)
                                    .font(.system(size: 9, weight: .semibold))
                                Text(appearance.hint)
                                Spacer(minLength: 0)
                            }
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)
                        }
                        .padding(.vertical, Theme.Space.s)

                        RowDivider(inset: 0)
                        HStack {
                            Text("主题配色")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: Theme.Space.xs)
                            accentSwatches
                        }
                        .padding(.vertical, Theme.Space.s)

                        RowDivider(inset: 46)
                        NavigationLink(value: SettingsPage.brand) {
                            SettingsRow(symbol: "paintpalette", tint: Theme.accent,
                                        title: "界面设置",
                                        value: "标题与图标")
                        }
                    }

                    section("运维") {
                        Button {
                            Task { _ = await store.restartServer() }
                        } label: {
                            SettingsRow(symbol: "arrow.triangle.2.circlepath", tint: Theme.warn,
                                        title: "重启服务端", value: nil, showsChevron: false)
                        }
                        .buttonStyle(.pressable(scale: 0.99))
                        RowDivider(inset: 46)
                        Button {
                            Task { await store.logout() }
                        } label: {
                            SettingsRow(symbol: "rectangle.portrait.and.arrow.right", tint: Theme.danger,
                                        title: "退出登录", value: nil, showsChevron: false)
                        }
                        .buttonStyle(.pressable(scale: 0.99))
                    }

                    footer
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
            .refreshable { await store.refreshAll() }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .notify: NotifySettingsView()
                case .led: LEDSettingsView()
                case .power: PowerSaveSettingsView()
                case .record: RecordSettingsView()
                case .storage: StorageSettingsView()
                case .block: BlockListView()
                case .logs: LogsView()
                case .brand: BrandSettingsView()
                }
            }
        }
    }

    private var headerSubtitle: String {
        if let at = store.lastRefresh {
            return "\(store.serverHost) · 更新于 \(Fmt.clock(at))"
        }
        return store.serverHost.isEmpty ? "未连接" : "\(store.serverHost) · 连接中…"
    }

    private var avatarLetter: String {
        String(store.savedUsername.prefix(1)).uppercased()
    }

    private var accountCard: some View {
        GlassCard {
            HStack(spacing: Theme.Space.s) {
                ZStack {
                    AvatarView(raw: store.brandAvatar,
                               fallback: avatarLetter.isEmpty ? "?" : avatarLetter,
                               size: 48,
                               base: store.session?.server)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.savedUsername.isEmpty ? "未登录" : store.savedUsername)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                    Text("\(store.serverHost) · 管理员")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                StatusPill(isOnline: store.session != nil, text: "已登录")
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: title)
            GlassCard(padding: 0) {
                VStack(spacing: 0) { content() }
                    .padding(.horizontal, Theme.Space.m)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("AirPanel · 远程管理面板")
                .font(Theme.micro)
                .foregroundStyle(Theme.ink3)
            Text("服务端 v2 · 设备端 v2.0.6")
                .font(Theme.micro)
                .foregroundStyle(Theme.ink3.opacity(0.7))
        }
        .padding(.top, Theme.Space.s)
    }
}

// MARK: - 设置行

struct SettingsRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var value: String?
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            IconBadge(symbol: symbol, tint: tint, size: 30)
            Text(title)
                .font(Theme.bodyStrong)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.ink3.opacity(0.7))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - 保存按钮
//
// 每个设置页共用一个：点下去先转圈，成功后短暂显示「已保存」，
// 失败把服务端 message 原样贴出来——不要含糊成「操作失败」。

struct SaveButton: View {
    var title: String = "保存到服务端"
    let action: () async -> Bool

    @State private var phase: Phase = .idle
    private enum Phase: Equatable { case idle, saving, done, failed(String) }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    phase = .saving
                    let ok = await action()
                    phase = ok ? .done : .failed("保存失败")
                    try? await Task.sleep(for: .seconds(2))
                    if case .done = phase { phase = .idle }
                    if case .failed = phase { phase = .idle }
                }
            } label: {
                HStack(spacing: 7) {
                    switch phase {
                    case .saving:
                        ProgressView().controlSize(.small).tint(Theme.ink)
                    case .done:
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .semibold))
                    case .idle:
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 13, weight: .semibold))
                    }
                    Text(labelText)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(phase == .done ? Theme.online : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.pressable(scale: 0.98))
            .disabled(phase == .saving)

            if case .failed(let msg) = phase {
                Text(msg)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.danger)
                    .transition(.opacity)
            }
        }
    }

    private var labelText: String {
        switch phase {
        case .idle: return title
        case .saving: return "保存中…"
        case .done: return "已保存"
        case .failed: return "重试保存"
        }
    }
}

// MARK: - 通知推送

struct NotifySettingsView: View {
    @Environment(PanelStore.self) private var store
    @State private var testResult: String?
    @State private var testing = false

    /// 渠道列表要取「定义 ∪ 已启用」的并集。
    /// 真实服务端会把自定义 POST 之类的渠道直接存进 settings，但它不在
    /// /api/notify/channels 的定义表里——只渲染定义表，用户会看到「已启用 1 个渠道」
    /// 却找不到那一条，也就关不掉。
    private struct ChannelRow: Identifiable {
        var id: String { name }
        var name: String
        var label: String
        var detail: String
    }

    private static let aliases: [String: String] = [
        "custom_post": "自定义 POST",
        "custom_get": "自定义 GET",
        "webhook": "自定义 Webhook"
    ]

    private var rows: [ChannelRow] {
        var out = store.channelDefs.map { ch in
            ChannelRow(name: ch.name, label: ch.label, detail: fieldSummary(ch))
        }
        let known = Set(out.map(\.name))
        for name in store.notifyChannels.subtracting(known).sorted() {
            out.append(ChannelRow(
                name: name,
                label: Self.aliases[name] ?? name,
                detail: "已启用 · 参数在网页版配置"
            ))
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                if rows.isEmpty {
                    GlassCard {
                        EmptyOrLoading(symbol: "paperplane",
                                   title: "没有可用渠道",
                                   message: "服务端 /api/notify/channels 没有返回渠道定义。",
                                   isLoading: store.isLoading(.settings))
                    }
                } else {
                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, ch in
                                HStack(spacing: Theme.Space.s) {
                                    IconBadge(symbol: "paperplane.fill", tint: tint(idx), size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ch.label)
                                            .font(Theme.bodyStrong)
                                            .foregroundStyle(Theme.ink)
                                        Text(ch.detail)
                                            .font(Theme.micro)
                                            .foregroundStyle(Theme.ink3)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { store.notifyChannels.contains(ch.name) },
                                        set: { on in
                                            if on { store.notifyChannels.insert(ch.name) }
                                            else { store.notifyChannels.remove(ch.name) }
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(Theme.accent)
                                    .scaleEffect(0.85)
                                }
                                .padding(.horizontal, Theme.Space.m)
                                .padding(.vertical, 6)
                                if idx < rows.count - 1 {
                                    RowDivider(inset: Theme.Space.m + 42)
                                }
                            }
                        }
                    }
                }

                SaveButton(title: "保存通知渠道") { await store.saveSettings() }

                Button {
                    Task {
                        testing = true
                        let r = await store.testNotify()
                        testing = false
                        withAnimation(Motion.fade) { testResult = r.message }
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(Motion.fade) { testResult = nil }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if testing {
                            ProgressView().controlSize(.small).tint(Theme.ink)
                        } else {
                            Image(systemName: "paperplane").font(.system(size: 13, weight: .semibold))
                        }
                        Text(testing ? "发送中…" : "发送测试通知")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.pressable(scale: 0.98))
                .disabled(testing)

                if let testResult {
                    Text(testResult)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                        .transition(.opacity)
                }

                Text("离线通知在设备失联 5 分钟后触发；省电模式下放宽到 30 分钟。渠道的具体参数（Key / Webhook）在网页版配置，这里只控制启停。")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("通知推送")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tint(_ i: Int) -> Color {
        [Theme.online, Theme.accent, Theme.violet, Theme.cyan, Theme.warn][i % 5]
    }

    private func fieldSummary(_ ch: Wire.NotifyChannelDef) -> String {
        let filled = ch.fields.filter { f in
            !(store.settings?.notifyConfig[ch.name]?[f.key] ?? "").isEmpty
        }.count
        return filled == 0 ? "\(ch.fields.count) 个参数 · 未填写" : "\(filled)/\(ch.fields.count) 个参数已填写"
    }
}

// MARK: - 灯光指示
//
// 颜色选择用色块网格而不是下拉——灯的颜色是「看一眼就知道」的选择。

struct LEDSettingsView: View {
    @Environment(PanelStore.self) private var store

    private let colors: [(name: String, color: Color)] = [
        ("关闭", .clear),
        ("红色", Color(hex: 0xFF3B30)),
        ("绿色", Color(hex: 0x34C759)),
        ("蓝色", Color(hex: 0x0A84FF)),
        ("黄色", Color(hex: 0xFFD60A)),
        ("紫色", Color(hex: 0xBF5AF2)),
        ("青色", Color(hex: 0x64D2FF)),
        ("白色", Color(hex: 0xF2F2F7))
    ]

    private var current: Color {
        colors.first { $0.name == store.ledColor }?.color ?? Theme.online
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                preview

                GlassCard(padding: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Toggle(isOn: Binding(get: { store.ledEnabled }, set: { store.ledEnabled = $0 })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("事件灯光")
                                    .font(Theme.bodyStrong)
                                    .foregroundStyle(Theme.ink)
                                Text("来短信 / 来电时点亮")
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                        .tint(Theme.accent)

                        RowDivider()

                        Text("颜色")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.ink3)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(colors, id: \.name) { item in
                                Button {
                                    withAnimation(Motion.layout) { store.ledColor = item.name }
                                } label: {
                                    VStack(spacing: 5) {
                                        ZStack {
                                            if item.color == .clear {
                                                Circle()
                                                    .strokeBorder(
                                                        Theme.ink3.opacity(0.6),
                                                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])
                                                    )
                                                    .frame(width: 26, height: 26)
                                            } else {
                                                Circle()
                                                    .fill(item.color)
                                                    .frame(width: 26, height: 26)
                                            }
                                        }
                                        Text(item.name)
                                            .font(.system(size: 9.5, weight: .medium))
                                            .foregroundStyle(store.ledColor == item.name ? Theme.ink : Theme.ink3)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(store.ledColor == item.name
                                                  ? Color.primary.opacity(0.09)
                                                  : Color.clear)
                                    )
                                }
                                .buttonStyle(.pressable(scale: 0.95))
                            }
                        }

                        RowDivider()

                        Toggle(isOn: Binding(get: { store.ledBlink }, set: { store.ledBlink = $0 })) {
                            Text("闪烁提示")
                                .font(Theme.bodyStrong)
                                .foregroundStyle(Theme.ink)
                        }
                        .tint(Theme.accent)
                    }
                }

                SaveButton(title: "保存灯光设置") { await store.saveSettings() }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("灯光指示")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewCaption: String {
        guard store.ledEnabled else { return "已关闭" }
        let blink = store.ledBlink ? " · 闪烁" : ""
        return "当前：\(store.ledColor)\(blink)"
    }

    private var previewFill: Color {
        guard store.ledEnabled, current != .clear else { return Color.primary.opacity(0.10) }
        return current
    }

    private var previewGlow: Color {
        store.ledEnabled && current != .clear ? current.opacity(0.75) : .clear
    }

    private var preview: some View {
        GlassCard {
            VStack(spacing: 10) {
                Circle()
                    .fill(previewFill)
                    .frame(width: 44, height: 44)
                    .shadow(color: previewGlow, radius: 22)
                Text(previewCaption)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - 省电模式
//
// 这里的开关落在设备 nvm_para.lua 里，所以要「读设备 → 改 → 写设备」，
// 不能像面板设置那样直接 POST 一个 JSON。

struct PowerSaveSettingsView: View {
    @Environment(PanelStore.self) private var store
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                if store.deviceConfigLoading && !loaded {
                    GlassCard { loadingRow }
                } else {
                    GlassCard(padding: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Toggle(isOn: Binding(get: { store.powerSaveEnabled },
                                                 set: { store.powerSaveEnabled = $0 })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("启用省电模式")
                                        .font(Theme.bodyStrong)
                                        .foregroundStyle(Theme.ink)
                                    Text("夜间降低心跳频率，延长续航")
                                        .font(Theme.micro)
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            .tint(Theme.online)

                            RowDivider()

                            HStack {
                                Text("生效时段")
                                    .font(Theme.bodyStrong)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(store.powerSaveWindow)
                                    .font(Theme.metric(14, .medium))
                                    .foregroundStyle(Theme.online)
                            }

                            RowDivider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("离线判定放宽到 30 分钟")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.ink2)
                                Text("省电期间应用心跳拉长到 10 分钟，若仍按 5 分钟判定会被误报离线。")
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.ink3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .opacity(store.powerSaveEnabled ? 1 : 0.65)
                    .motion(Motion.layout, value: store.powerSaveEnabled)

                    SaveButton(title: "写入设备") {
                        await store.applyDeviceConfig([
                            "POWERSAVE_ENABLE": store.powerSaveEnabled,
                            "POWERSAVE_START_HOUR": 1,
                            "POWERSAVE_END_HOUR": 8
                        ])
                    }

                    Text("生效时段目前固定 01:00–08:00。需要精细调整请到网页版的省电配置页。")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("省电模式")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadDeviceConfig()
            loaded = true
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在读取设备配置…")
                .font(Theme.callout)
                .foregroundStyle(Theme.ink2)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 通话录音

struct RecordSettingsView: View {
    @Environment(PanelStore.self) private var store
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                if store.deviceConfigLoading && !loaded {
                    GlassCard {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在读取设备配置…")
                                .font(Theme.callout)
                                .foregroundStyle(Theme.ink2)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    GlassCard(padding: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Toggle(isOn: Binding(get: { store.recordEnabled }, set: { store.recordEnabled = $0 })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("接通即录音")
                                        .font(Theme.bodyStrong)
                                        .foregroundStyle(Theme.ink)
                                    Text("录音自动上传到 WebDAV")
                                        .font(Theme.micro)
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            .tint(Theme.violet)

                            RowDivider()

                            Toggle(isOn: Binding(get: { store.ttsBeforeEnabled }, set: { store.ttsBeforeEnabled = $0 })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("前置语音提示")
                                        .font(Theme.bodyStrong)
                                        .foregroundStyle(Theme.ink)
                                    Text("录音开始前播放「本次通话将被录音」")
                                        .font(Theme.micro)
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            .tint(Theme.violet)
                            .disabled(!store.recordEnabled)
                            .opacity(store.recordEnabled ? 1 : 0.5)
                        }
                    }

                    SaveButton(title: "写入设备") {
                        await store.applyDeviceConfig([
                            "RECORD_ENABLE": store.recordEnabled,
                            "TTS_BEFORE_ENABLE": store.ttsBeforeEnabled
                        ])
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("录音文件按「号码_年月日时分秒」命名，存到 WebDAV 的中文目录下。开关写入设备后即刻生效，不需要重启。")
                        .font(Theme.micro)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("通话录音")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadDeviceConfig()
            loaded = true
        }
    }
}

// MARK: - 存储配置

struct StorageSettingsView: View {
    @Environment(PanelStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                GlassCard(padding: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        field("服务器地址", text: Binding(get: { store.webdavURL },
                                                      set: { store.webdavURL = $0 }),
                              placeholder: "https://web.example.com")
                        field("录音目录", text: Binding(get: { store.webdavDir },
                                                    set: { store.webdavDir = $0 }),
                              placeholder: "通话录音")
                        readOnly("账号", store.settings?.webdav.username ?? "—")
                        readOnly("密码", (store.settings?.webdav.password.isEmpty == false) ? "••••••••" : "未设置")
                    }
                }

                SaveButton(title: "保存存储配置") { await store.saveSettings() }

                Text("账号与密码涉及凭据，只在网页版可改。这里能改服务器地址与录音目录。")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("存储配置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink3)
            TextField(placeholder, text: text)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }

    private func readOnly(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.caption).foregroundStyle(Theme.ink3)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink2)
        }
    }
}

// MARK: - 界面设置

struct BrandSettingsView: View {
    @Environment(PanelStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                GlassCard(padding: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("站点标题")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.ink3)
                        TextField("AirPanel", text: Binding(get: { store.brandTitle },
                                                            set: { store.brandTitle = $0 }))
                            .font(Theme.body)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )

                        RowDivider()

                        // 头像：网页端存在 brand.avatar 里，App 这边既能看也能改
                        HStack(spacing: Theme.Space.s) {
                            AvatarView(raw: store.brandAvatar,
                                       fallback: store.savedUsername.isEmpty
                                           ? "?" : String(store.savedUsername.prefix(1)).uppercased(),
                                       size: 44,
                                       base: store.session?.server)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("头像地址")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.ink3)
                                TextField("https://example.com/avatar.png",
                                          text: Binding(get: { store.brandAvatar },
                                                        set: { store.brandAvatar = $0 }))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.ink)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                    )
                            }
                        }
                        Text("图片直链；留空则显示用户名首字母。和网页端「界面设置」是同一份数据。")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)

                        RowDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("站点 Logo")
                                    .font(Theme.bodyStrong)
                                    .foregroundStyle(Theme.ink)
                                Text(store.brandLogo.isEmpty
                                     ? "未设置，使用默认图标"
                                     : store.brandLogo)
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.ink3)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            IconBadge(symbol: "photo", tint: Theme.accent, size: 32)
                        }
                    }
                }

                SaveButton(title: "保存界面设置") { await store.saveSettings() }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("界面设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 屏蔽配置

struct BlockListView: View {
    @Environment(PanelStore.self) private var store
    @State private var kind: BlockKind = .keyword
    @State private var adding = false
    @State private var draftValue = ""
    @State private var draftMode = "包含"

    private var rules: [BlockRule] {
        store.blockRules.filter { $0.kind == kind }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                GlassSegmented(
                    items: [(BlockKind.keyword, "关键字"), (BlockKind.number, "号码")],
                    selection: $kind
                )

                GlassCard(padding: Theme.Space.m) {
                    VStack(spacing: 0) {
                        if rules.isEmpty {
                            EmptyOrLoading(symbol: "shield",
                                       title: "没有规则",
                                       message: "命中规则的短信与来电不会推送通知，但仍会记录。",
                                       isLoading: store.isLoading(.blockRules))
                        } else {
                            ForEach(Array(rules.enumerated()), id: \.element.id) { idx, rule in
                                HStack(spacing: Theme.Space.s) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(rule.value)
                                                .font(Theme.bodyStrong)
                                                .foregroundStyle(Theme.ink)
                                            if rule.isBuiltin {
                                                Text("内置")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(Theme.ink3)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                                            }
                                        }
                                        Text("\(rule.matchMode)匹配 · 已拦截 \(rule.hits) 次")
                                            .font(Theme.micro)
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { rule.enabled },
                                        set: { _ in Task { await store.toggleBlockRule(rule.id) } }
                                    ))
                                    .labelsHidden()
                                    .tint(Theme.danger)
                                    .scaleEffect(0.82)
                                }
                                .padding(.vertical, 9)
                                .contextMenu {
                                    if !rule.isBuiltin {
                                        Button("删除规则", role: .destructive) {
                                            Task { await store.deleteBlockRule(rule.id) }
                                        }
                                    }
                                }
                                if idx < rules.count - 1 {
                                    RowDivider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshBlockRules() }
        .background(AppBackground())
        .navigationTitle("屏蔽配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .alert(kind == .keyword ? "新增关键字" : "新增号码", isPresented: $adding) {
            TextField(kind == .keyword ? "娱乐城" : "400", text: $draftValue)
            if kind == .number {
                Button("前缀匹配") { commit("前缀") }
                Button("精确匹配") { commit("精确") }
            } else {
                Button("添加") { commit("包含") }
            }
            Button("取消", role: .cancel) { draftValue = "" }
        } message: {
            Text(kind == .keyword ? "短信正文包含该词时不再推送通知。" : "来电号码匹配时不再推送通知。")
        }
    }

    private func commit(_ mode: String) {
        let value = draftValue.trimmingCharacters(in: .whitespaces)
        draftValue = ""
        guard !value.isEmpty else { return }
        Task { _ = await store.addBlockRule(kind: kind, value: value, matchMode: mode) }
    }
}

// MARK: - 日志中心

struct LogsView: View {
    @Environment(PanelStore.self) private var store
    @State private var source: Source = .device
    @State private var filter: LogFilter = .all

    enum Source: Hashable { case device, server }
    enum LogFilter: Hashable { case all, warn, error }

    private var deviceRows: [DeviceLog] {
        let sorted = store.logs.sorted { $0.time > $1.time }
        switch filter {
        case .all: return sorted
        case .warn: return sorted.filter { $0.level == .warn }
        case .error: return sorted.filter { $0.level == .error }
        }
    }

    private var serverRows: [Wire.ServerLogEntry] {
        let sorted = store.serverLogs.sorted { $0.time > $1.time }
        switch filter {
        case .all: return sorted
        case .warn: return sorted.filter { $0.level == "warn" }
        case .error: return sorted.filter { $0.level == "error" }
        }
    }

    private var isEmpty: Bool {
        source == .device ? deviceRows.isEmpty : serverRows.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                GlassSegmented(
                    items: [(Source.device, "设备上报"), (Source.server, "服务端")],
                    selection: $source
                )
                GlassSegmented(
                    items: [(LogFilter.all, "全部"), (LogFilter.warn, "警告"), (LogFilter.error, "错误")],
                    selection: $filter
                )

                GlassCard(padding: Theme.Space.m) {
                    VStack(spacing: 0) {
                        if isEmpty {
                            EmptyOrLoading(symbol: "checkmark.seal",
                                       title: "没有匹配的日志",
                                       message: "切换筛选条件，或等设备上报新的运行日志。",
                                       isLoading: store.isLoading(.logs))
                        } else if source == .device {
                            ForEach(Array(deviceRows.enumerated()), id: \.element.id) { idx, log in
                                deviceRow(log)
                                if idx < deviceRows.count - 1 { RowDivider(inset: 20) }
                            }
                        } else {
                            ForEach(Array(serverRows.enumerated()), id: \.element.id) { idx, line in
                                serverRow(line)
                                if idx < serverRows.count - 1 { RowDivider(inset: 20) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshLogs() }
        .background(AppBackground())
        .navigationTitle("日志中心")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deviceRow(_ log: DeviceLog) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(log.level.label.prefix(1))
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(log.level.tint)
                .frame(width: 12)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(log.source)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                    Spacer()
                    Text(Fmt.dayLabel(log.time) + " " + Fmt.clock(log.time))
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
                Text(log.message)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(log.level == .error ? Theme.danger.opacity(0.9) : Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(6)
            }
        }
        .padding(.vertical, 8)
    }

    private func serverRow(_ line: Wire.ServerLogEntry) -> some View {
        let level: LogLevel = line.level == "error" ? .error : (line.level == "warn" ? .warn : .info)
        return HStack(alignment: .top, spacing: 8) {
            Text(level.label.prefix(1))
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(level.tint)
                .frame(width: 12)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(line.level.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Text(Fmt.clock(Date(timeIntervalSince1970: TimeInterval(line.time))))
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
                Text(line.msg)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(level == .error ? Theme.danger.opacity(0.9) : Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(6)
            }
        }
        .padding(.vertical, 8)
    }
}

import SwiftUI

// MARK: - 概览
//
// 一屏回答四个问题：设备在不在线、还能撑多久、今天发生了什么、最近出了什么事。
// 主视觉是一块「仪表盘」卡片：电量环 + 三个关键读数，其余信息按重要度往下排。

struct OverviewView: View {
    @Environment(PanelStore.self) private var store
    @State private var pickerOpen = false
    @State private var trend: TrendKind = .signal
    @State private var runningCommand: Command?

    enum TrendKind: Hashable { case signal, battery }

    private var device: Device? { store.activeDevice }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    header
                    if device == nil {
                        GlassCard {
                            EmptyOrLoading(symbol: "cpu",
                                       title: "还没有设备接入",
                                       message: "设备第一次连上服务端 broker 后会自动出现在这里，不需要手动添加。",
                                       isLoading: store.isLoading(.devices))
                        }
                    } else {
                        heroCard
                        quickActions
                        statsCard
                        trendCard
                    }
                    eventsCard
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
            .refreshable { await store.refreshAll() }
            .background(
                AppBackground(glow: (device?.isOnline ?? false) ? Theme.online : Theme.ink3)
            )
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $pickerOpen) {
                DevicePickerSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
            }
            .sheet(item: $runningCommand) { cmd in
                CommandRunnerSheet(command: cmd)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        PageHeader("概览", subtitle: subtitleText, titleAccessory: { serverUptimeTag }) {
            Button {
                pickerOpen = true
            } label: {
                HStack(spacing: 6) {
                    StatusDot(color: (device?.isOnline ?? false) ? Theme.online : Theme.ink3, size: 6)
                    Text(chipName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        // 按内容收窄：之前给了 maxWidth 132，短名字也会被撑成一条长胶囊
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.pressable)
        }
    }

    /// 设备名是用户自己起的，可能很长。固定按 8 个字截断再交给 `fixedSize`，
    /// 既不会把标题挤掉，也不会像原来那样短名字也占满一整条。
    private var chipName: String {
        let name = device?.displayName ?? "未选择设备"
        return name.count > 8 ? String(name.prefix(8)) + "…" : name
    }

    /// 服务端已运行时间：挂在「概览」标题右边，小点隔开，只留图标 + 时长。
    /// 数据是 `/api/stats/summary` 的 `uptimeSec`（服务端进程启动到现在），
    /// **不是**设备在线时长——设备掉线重连不影响这个数，反过来服务端重启也不影响设备。
    @ViewBuilder
    private var serverUptimeTag: some View {
        if store.serverUptime > 0 {
            HStack(spacing: 5) {
                Text("·")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink3.opacity(0.5))
                Image(systemName: "server.rack")
                    .font(.system(size: 10, weight: .semibold))
                Text(Fmt.uptime(store.serverUptime))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.ink3)
            .accessibilityLabel("服务端已运行 \(Fmt.uptime(store.serverUptime))")
        }
    }

    private var subtitleText: String {
        guard let device else { return "还没有绑定设备" }
        guard device.isOnline else { return "最后在线 \(Fmt.ago(device.lastSeen))" }
        guard device.telemetry.hasData else { return "在线 · 等待遥测上报" }
        // 只放时长：运营商与网络已经在下面的仪表盘里，副标题再重复一遍会挤到省略号
        return "已在线 \(Fmt.uptime(device.telemetry.uptime))"
    }

    // MARK: 仪表盘

    /// 「续航 18 小时」：和在线状态排在一起，一眼就是「还能撑多久」
    @ViewBuilder
    private var enduranceChip: some View {
        if let device, device.telemetry.hasData {
            let t = device.telemetry
            // 充电时「续航」这个词就不成立了，直接说「充电中」
            HStack(spacing: 4) {
                Image(systemName: t.isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 10, weight: .semibold))
                Text(t.isCharging ? "充电中" : "续航 \(t.enduranceText)")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(t.isCharging ? Theme.online : Theme.ink2)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(t.isCharging ? "正在充电" : "预计续航 \(t.enduranceText)")
        }
    }

    private var heroCard: some View {
        GlassCard {
            VStack(spacing: Theme.Space.m) {
                HStack(alignment: .center, spacing: Theme.Space.l) {
                    ring
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            StatusPill(isOnline: device?.isOnline ?? false,
                                       text: (device?.isOnline ?? false) ? "在线" : "离线")
                            enduranceChip
                            Spacer(minLength: 0)
                        }
                        metricRow("bolt.fill", "电压", voltageText, "V", Theme.accent)
                        metricRow("thermometer.medium", "温度", tempText, "℃", Theme.warn)
                        metricRow("cellularbars", "信号", signalText, "dBm", Theme.cyan)
                    }
                    Spacer(minLength: 0)
                }

                RowDivider()

                HStack(spacing: 10) {
                    Text(carrierText)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                    Text("·")
                        .foregroundStyle(Theme.ink3)
                    Text(netText)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                    Spacer(minLength: 6)
                    Text(reportText)
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    private var ring: some View {
        RingGauge(
            progress: Double(device?.telemetry.batteryPercent ?? 0) / 100,
            tint: batteryTint,
            lineWidth: 10,
            size: 106
        ) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(device?.telemetry.batteryPercent ?? 0)")
                        .font(Theme.metric(31))
                        .foregroundStyle(Theme.ink)
                    Text("%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                Text(device?.telemetry.isCharging == true ? "充电中" : "电量")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    private var batteryTint: Color {
        let p = device?.telemetry.batteryPercent ?? 0
        if p <= 20 { return Theme.danger }
        if p <= 40 { return Theme.warn }
        return Theme.online
    }

    private var carrierText: String {
        let c = device?.telemetry.carrier ?? ""
        return c.isEmpty ? "未上报" : c
    }

    private var netText: String {
        let t = device?.telemetry
        let parts = [t?.netMode ?? "", t?.simSlot ?? ""].filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var reportText: String {
        guard let at = device?.telemetry.reportedAt, at != .distantPast else { return "暂无遥测" }
        return "上报 \(Fmt.ago(at))"
    }

    private var voltageText: String {
        guard let t = device?.telemetry, t.hasData else { return "—" }
        return String(format: "%.2f", Double(t.voltageMV) / 1000)
    }

    private var tempText: String {
        guard let t = device?.telemetry, t.hasData else { return "—" }
        return String(format: "%.1f", t.temperature)
    }

    private var signalText: String {
        guard let t = device?.telemetry, t.hasData else { return "—" }
        return "\(t.rssi)"
    }

    private func metricRow(_ symbol: String, _ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 15)
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink2)
            Text(value)
                .font(Theme.metric(15))
                .foregroundStyle(Theme.ink)
            Text(unit)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 0)
        }
    }

    // MARK: 快捷操作
    //
    // 只放四个真正常用的：发短信、打电话、查状态、重启。
    // 其余 14 条命令在「自动化 › 任务」里，避免首页变成按钮墙。

    private var quickActions: some View {
        HStack(spacing: 0) {
            ForEach(Catalog.quick.compactMap(Catalog.command), id: \.id) { cmd in
                Button {
                    runningCommand = cmd
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: cmd.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(cmd.tint)
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular.interactive(), in: .circle)
                        Text(cmd.label)
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: 今日统计

    private var statsCard: some View {
        GlassCard(padding: Theme.Space.m) {
            HStack(spacing: 0) {
                statColumn("\(store.todayCallCount)", "通话", Theme.accent)
                verticalRule
                statColumn("\(store.todaySmsCount)", "短信", Theme.cyan)
                verticalRule
                statColumn("\(store.todayTaskCount)", "任务", Theme.violet)
                verticalRule
                statColumn("\(store.spamCount)", "已拦截", Theme.danger)
            }
        }
    }

    private func statColumn(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.metric(21))
                .foregroundStyle(tint)
            Text(label)
                .font(Theme.micro)
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5, height: 26)
    }

    // MARK: 趋势

    private var trendCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("遥测趋势")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                        Text(trend == .signal
                             ? "信号强度 · dBm（越接近 0 越好）"
                             : "电量 · %（按电压换算）")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    GlassSegmented(
                        items: [(TrendKind.signal, "信号"), (TrendKind.battery, "电量")],
                        selection: $trend
                    )
                    .frame(width: 132)
                }

                if trendValues.count < 2 {
                    EmptyOrLoading(symbol: "chart.line.uptrend.xyaxis",
                               title: "样本还不够",
                               message: "设备每上报一条遥测就会多一个点，攒到两个以上才画得出曲线。",
                               isLoading: store.isLoading(.overview),
                               loadingTitle: "正在读取遥测…")
                        .frame(height: 110)
                } else {
                    Sparkline(
                        values: trendValues,
                        tint: trend == .signal ? Theme.cyan : batteryTint
                    )
                    .frame(height: 92)
                    .padding(.top, 2)

                    HStack {
                        Text("最早").font(Theme.micro).foregroundStyle(Theme.ink3)
                        Spacer()
                        Text("\(trendValues.count) 个采样点").font(Theme.micro).foregroundStyle(Theme.ink3)
                        Spacer()
                        Text("最新").font(Theme.micro).foregroundStyle(Theme.ink3)
                    }
                }
            }
        }
    }

    private var trendValues: [Double] {
        trend == .signal ? store.signalTrend : store.batteryTrend
    }

    // MARK: 最近事件

    private var eventsCard: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("最近事件")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(store.logs.count) 条")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 10)

                ForEach(Array(store.recentEvents.enumerated()), id: \.element.id) { idx, log in
                    EventRow(log: log)
                    if idx < store.recentEvents.count - 1 {
                        RowDivider(inset: 4)
                    }
                }
            }
        }
    }
}

// MARK: - 事件行

struct EventRow: View {
    let log: DeviceLog

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(log.level.tint)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(log.source)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(log.level.tint.opacity(0.9))
                    Text(Fmt.ago(log.time))
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                    Spacer(minLength: 0)
                }
                Text(log.message)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
    }
}

import SwiftUI

// MARK: - 设备
//
// 卡片列表而不是表格：每台设备给一块「体检小结」——在线状态、电量、信号、最后在线。
// 点开是详情，详情里才有危险操作（删除），并且要二次确认。

struct DevicesView: View {
    @Environment(PanelStore.self) private var store
    @State private var detail: Device?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    PageHeader("设备", subtitle: "\(store.devices.count) 台 · \(store.onlineCount) 台在线") {
                        GlassIconButton(symbol: "plus") {}
                    }

                    if store.devices.isEmpty {
                        GlassCard {
                            EmptyOrLoading(
                                symbol: "cpu",
                                title: "还没有设备",
                                message: "设备首次连接 broker 后会自动出现在这里，无需手动添加。",
                                isLoading: store.isLoading(.devices),
                                action: ("查看接入说明", {})
                            )
                        }
                    } else {
                        ForEach(store.devices) { device in
                            Button {
                                detail = device
                            } label: {
                                DeviceCard(device: device, isActive: device.id == store.activeDeviceID)
                            }
                            .buttonStyle(.pressable(scale: 0.985))
                        }
                    }

                    hintCard
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refreshAll() }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $detail) { device in
                DeviceDetailSheet(device: device)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
            }
            .onAppear {
                // 冷启动时设备还没拉回来，这里先试一次，没数据就等 onChange 补
                if ProcessInfo.processInfo.arguments.contains("-device") {
                    detail = store.devices.first
                }
            }
            .onChange(of: store.devices.isEmpty) { _, isEmpty in
                guard ProcessInfo.processInfo.arguments.contains("-device"),
                      !isEmpty, detail == nil else { return }
                detail = store.devices.first
            }
        }
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink3)
                .padding(.top, 1)
            Text("离线判定：普通模式 5 分钟无心跳；省电模式下放宽到 30 分钟，避免半在线被误报。")
                .font(Theme.caption)
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

// MARK: - 设备卡片

struct DeviceCard: View {
    let device: Device
    var isActive: Bool

    private var batteryTint: Color {
        let p = device.telemetry.batteryPercent
        if p <= 20 { return Theme.danger }
        if p <= 40 { return Theme.warn }
        return Theme.online
    }

    var body: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    IconBadge(
                        symbol: device.isOnline ? "cpu.fill" : "cpu",
                        tint: device.isOnline ? Theme.online : Theme.ink3,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.displayName)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(Fmt.phone(device.phone))
                                .font(Theme.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink2)
                            if isActive {
                                Text("当前")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.accent.opacity(0.16)))
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    StatusPill(isOnline: device.isOnline)
                }

                RowDivider()

                HStack(spacing: 0) {
                    mini("电量", "\(device.telemetry.batteryPercent)", "%", batteryTint)
                    miniDivider
                    mini("信号", "\(device.telemetry.csq)", "/31", Theme.cyan)
                    miniDivider
                    mini("温度", String(format: "%.1f", device.telemetry.temperature), "℃", Theme.warn)
                    miniDivider
                    mini(device.isOnline ? "在线" : "最后在线",
                         device.isOnline ? Fmt.uptime(device.telemetry.uptime) : Fmt.ago(device.lastSeen),
                         "", Theme.ink2)
                }
            }
        }
        .opacity(device.isOnline ? 1 : 0.84)
    }

    private func mini(_ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(Theme.metric(14))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private var miniDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(width: 0.5, height: 22)
    }
}

// MARK: - 设备选择

struct DevicePickerSheet: View {
    @Environment(PanelStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(store.devices) { device in
                        Button {
                            Task { await store.selectDevice(device.id) }
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Space.s) {
                                IconBadge(
                                    symbol: device.isOnline ? "cpu.fill" : "cpu",
                                    tint: device.isOnline ? Theme.online : Theme.ink3,
                                    size: 36
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.displayName)
                                        .font(Theme.bodyStrong)
                                        .foregroundStyle(Theme.ink)
                                    Text(Fmt.phone(device.phone))
                                        .font(Theme.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.ink2)
                                }
                                Spacer()
                                if device.id == store.activeDeviceID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Theme.accent)
                                } else {
                                    StatusPill(isOnline: device.isOnline)
                                }
                            }
                            .padding(Theme.Space.s)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                                    .fill(device.id == store.activeDeviceID
                                          ? Theme.accent.opacity(0.09)
                                          : Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.pressable(scale: 0.985))
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xs)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .navigationTitle("切换设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - 设备详情

struct DeviceDetailSheet: View {
    /// 只当作「初始快照」：真正的数据每次从 store 现取。
    /// 直接用快照渲染的话，打开这一刻 overview 还没回来，
    /// 电量/电压/温度会一直停在 0，数据到了也不会刷新。
    let device: Device

    private var live: Device {
        store.devices.first { $0.imei == device.imei } ?? device
    }

    @Environment(PanelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    summary
                    telemetryGrid
                    identityCard
                    actions
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(live.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .confirmationDialog("删除设备", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除「\(live.displayName)」", role: .destructive) {
                    Task { await store.deleteDevice(live.imei) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会同时移除该设备的通话、短信与任务记录，且无法恢复。")
            }
        }
    }

    private var summary: some View {
        GlassCard {
            HStack(spacing: Theme.Space.m) {
                RingGauge(
                    progress: Double(live.telemetry.batteryPercent) / 100,
                    tint: live.telemetry.batteryPercent <= 20 ? Theme.danger : Theme.online,
                    lineWidth: 8,
                    size: 84
                ) {
                    Text("\(live.telemetry.batteryPercent)%")
                        .font(Theme.metric(17))
                        .foregroundStyle(Theme.ink)
                }
                VStack(alignment: .leading, spacing: 5) {
                    StatusPill(isOnline: live.isOnline)
                    Text(live.isOnline
                         ? "已连续在线 \(Fmt.uptime(live.telemetry.uptime))"
                         : "最后在线 \(Fmt.ago(live.lastSeen))")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.ink2)
                    Text("首次接入 \(Fmt.dayLabel(live.firstSeen))")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var telemetryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.xs),
                            GridItem(.flexible(), spacing: Theme.Space.xs)],
                  spacing: Theme.Space.xs) {
            gridItem("电压", String(format: "%.2f V", Double(live.telemetry.voltageMV) / 1000), Theme.accent)
            gridItem("温度", String(format: "%.1f ℃", live.telemetry.temperature), Theme.warn)
            gridItem("RSSI", "\(live.telemetry.rssi) dBm", Theme.cyan)
            gridItem("信号格", "\(live.telemetry.csq) / 31", Theme.cyan)
            gridItem("网络", "\(live.telemetry.netMode) · \(live.telemetry.carrier)", Theme.ink)
            gridItem("卡槽", live.telemetry.simSlot, Theme.ink)
        }
    }

    private func gridItem(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.micro)
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(Theme.metric(15))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var identityCard: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(spacing: 0) {
                kv("IMEI", live.id, copyable: true)
                RowDivider()
                kv("SN", live.telemetry.sn)
                RowDivider()
                kv("ICCID", live.telemetry.iccid)
                RowDivider()
                kv("固件", live.telemetry.firmware)
            }
        }
    }

    private func kv(_ key: String, _ value: String, copyable: Bool = false) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(key)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink3)
                .frame(width: 46, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if copyable {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.vertical, 10)
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.xs) {
            Button {
                Task { await store.selectDevice(live.id) }
                dismiss()
            } label: {
                actionLabel("设为当前设备", "checkmark.circle", Theme.accent)
            }
            .buttonStyle(.pressable(scale: 0.985))

            Button {
                confirmDelete = true
            } label: {
                actionLabel("删除设备", "trash", Theme.danger)
            }
            .buttonStyle(.pressable(scale: 0.985))
        }
    }

    private func actionLabel(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

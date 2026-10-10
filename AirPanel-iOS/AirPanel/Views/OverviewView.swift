import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: AppStore
    @State private var overview: Overview?
    @State private var state: LoadState = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let ov = overview {
                    metricGrid(ov)
                    powerCard(ov)
                    chartCard(ov)
                    infoCard(ov)
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("概览")
        .task(id: store.selectedIMEI) { await load() }
        .refreshable { await load() }
        .overlay {
            switch state {
            case .loading: LoadingView(text: "加载概览…")
            case .failed(let msg): ErrorView(message: msg) { Task { await load() } }
            case .idle, .loaded: EmptyView()
            }
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                deviceMenu
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let ov = overview, let d = ov.device, d.connected {
                        StatusPill(text: "在线", color: Theme.green)
                    } else {
                        StatusPill(text: "离线", color: Theme.red)
                    }
                    Text("最后在线 \(lastSeenText)")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.text.opacity(0.45))
                }
            }
            if let d = overview?.device {
                Text("\(maskedIMEI(d.imei))")
                    .font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.5))
                Text(d.name.isEmpty ? maskedPhone(d.phone) : "\(d.name) · \(maskedPhone(d.phone))")
                    .font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.55))
            }
        }
    }

    /// 最后在线时间的相对展示
    var lastSeenText: String {
        guard let t = overview?.device?.lastSeen, t > 0 else { return "-" }
        let diff = Date().timeIntervalSince1970 - Double(t)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        let days = Int(diff / 86400)
        return days < 7 ? "\(days) 天前" : Fmt.time(t)
    }

    var deviceMenu: some View {
        Menu {
            ForEach(store.devices) { d in
                Button(d.name.isEmpty ? maskedIMEI(d.imei) : "\(d.name) · \(maskedIMEI(d.imei))") {
                    store.select(imei: d.imei)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(store.selectedDevice?.name.isEmpty == false ? store.selectedDevice!.name : (store.selectedDevice.map { maskedIMEI($0.imei) } ?? "选择设备"))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.text.opacity(0.5))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.fill, in: Capsule())
        }
    }

    func metricGrid(_ ov: Overview) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
            MetricCard(label: "信号强度", value: sig(ov), unit: "dBm",
                       subtitle: "RSRP \(ov.latest?.rsrp ?? 0) · \(ov.latest?.netMode ?? "LTE")",
                       color: Theme.teal, pill: ov.latest?.operator ?? "移动", pillColor: Theme.green)
            MetricCard(label: "电池电量", value: "\(ov.battery.percent)", unit: "%",
                       subtitle: "\(String(format: "%.2f", Float(ov.battery.voltage) / 1000)) V · \(ov.battery.charging ? "充电中" : "电池")",
                       color: Theme.green, pill: ov.battery.charging ? "USB 供电" : "电池供电", pillColor: ov.battery.charging ? Theme.orange : Theme.green)
            MetricCard(label: "在线时长", value: "\(ov.onlineSeconds / 3600)", unit: "小时",
                       subtitle: "开机 \(Fmt.duration(ov.latest?.workTime ?? 0))",
                       color: Theme.accent, pill: "心跳正常", pillColor: Theme.green)
            MetricCard(label: "模组温度", value: temp(ov), unit: "℃",
                       subtitle: "当前温度",
                       color: Theme.orange, pill: "正常", pillColor: Theme.green)
        }
    }

    func sig(_ ov: Overview) -> String {
        let r = ov.latest?.rssi ?? 0
        return "\(r)"
    }
    func temp(_ ov: Overview) -> String {
        String(format: "%.1f", ov.latest?.temperature ?? 0)
    }

    func powerCard(_ ov: Overview) -> some View {
        GlassCard {
            VStack(spacing: 10) {
                HStack {
                    Text("功耗与续航").font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                HStack(spacing: 0) {
                    metricCell("当前电流", "\(ov.power.currentMa)", "mA")
                    Divider().frame(height: 34).background(Theme.stroke)
                    metricCell("预估续航", hours(ov.power.estHours), "时")
                    Divider().frame(height: 34).background(Theme.stroke)
                    metricCell("电池容量", "\(ov.battery.mah)", "mAh")
                }
                Text("电流按功耗模型估算 · 可在设置校准")
                    .font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
            }
        }
    }

    func metricCell(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundColor(Theme.text.opacity(0.45))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 20, weight: .bold))
                Text(unit).font(.system(size: 10)).foregroundColor(Theme.text.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }

    func hours(_ h: Double) -> String {
        h > 0 ? String(format: "%.1f", h) : "-"
    }

    func chartCard(_ ov: Overview) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("信号 / 电压 / 温度 趋势").font(.system(size: 14, weight: .bold))
                Text("最近 \(ov.history.count) 次上报").font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
                if ov.history.count >= 2 {
                    Chart {
                        ForEach(Array(ov.history.enumerated()), id: \.element.ID) { idx, t in
                            LineMark(x: .value("n", idx),
                                     y: .value("rssi", t.rssi))
                                .foregroundStyle(Theme.teal)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        ForEach(Array(ov.history.enumerated()), id: \.element.ID) { idx, t in
                            LineMark(x: .value("n", idx),
                                     y: .value("voltage", Double(t.voltage) / 1000))
                                .foregroundStyle(Theme.green)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        ForEach(Array(ov.history.enumerated()), id: \.element.ID) { idx, t in
                            LineMark(x: .value("n", idx),
                                     y: .value("temp", t.temperature))
                                .foregroundStyle(Theme.orange)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 130)
                    HStack(spacing: 14) {
                        legend(Theme.teal, "信号 dBm")
                        legend(Theme.green, "电压 V")
                        legend(Theme.orange, "温度 ℃")
                        Spacer()
                    }
                } else {
                    EmptyState(text: "遥测数据不足（至少 2 次）")
                }
            }
        }
    }

    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 10.5)).foregroundColor(Theme.text.opacity(0.55))
        }
    }

    func infoCard(_ ov: Overview) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                GlassRow(icon: "iphone", color: Theme.accent, title: "本机号码",
                         subtitle: ov.latest?.operator ?? "-", trailing: ov.latest?.number ?? "-")
                Divider().overlay(Theme.stroke)
                GlassRow(icon: "bolt.fill", color: Theme.orange,
                         title: "供电状态", subtitle: ov.battery.charging ? "VBUS 已连接 · USB 供电" : "电池供电",
                         trailing: ov.battery.charging ? "充电" : "电池", trailingColor: ov.battery.charging ? Theme.green : Theme.green)
                Divider().overlay(Theme.stroke)
                GlassRow(icon: "doc.text", color: Theme.purple, title: "固件版本",
                         subtitle: ov.latest?.model ?? "-", trailing: ov.latest?.version ?? "-")
                Divider().overlay(Theme.stroke)
                GlassRow(icon: "sim", color: Theme.teal, title: "SIM 卡",
                         subtitle: "ICCID \(ov.latest?.iccid ?? "-")", trailing: ov.latest?.simSlot ?? "-")
            }
        }
    }

    @MainActor
    func load() async {
        guard let imei = store.selectedDevice?.imei ?? store.selectedIMEI else {
            state = .idle
            return
        }
        state = .loading
        do {
            overview = try await store.api.getOverview(imei: imei)
            if let o = overview {
                store.rememberTelemetry(battery: o.battery.percent,
                                         csq: o.latest?.csq ?? -1,
                                         netMode: o.latest?.netMode ?? "",
                                         charging: o.battery.charging)
            }
            state = .loaded
        } catch {
            if isCancelError(error) { return }
            state = .failed((error as? APIError)?.message ?? error.localizedDescription)
        }
    }
}

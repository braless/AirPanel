import SwiftUI
import WidgetKit

// MARK: - 小组件配色
//
// 不能直接用 App 的 Theme：那套依赖 AccentTheme 单例、依赖 App 生命周期，
// 小组件里跑不起来。这里留一份最小配色，色值与 Theme 一一对应，
// 改主题时两边一起改（只有这一处是重复的，值本身不会各说各话）。

enum WidgetTheme {
    static let ink = Color(wLight: 0x0A0A0C, wDark: 0xF7F7F9)
    static let ink2 = Color(wLight: 0x60606A, wDark: 0x9C9CA6)
    static let ink3 = Color(wLight: 0x8C8C96, wDark: 0x6B6B76)
    static let online = Color(wLight: 0x1DA34C, wDark: 0x30D158)
    static let warn = Color(wLight: 0xD97706, wDark: 0xFF9F0A)
    static let danger = Color(wLight: 0xD92D20, wDark: 0xFF453A)

    /// 主题主色：跟着 App 设置里选的配色走（快照里带过来的是名字）
    static func accent(_ name: String) -> Color {
        switch name {
        case "violet": return Color(wLight: 0x6E3AD6, wDark: 0xBF5AF2)
        case "teal": return Color(wLight: 0x0E8C9E, wDark: 0x40C8E0)
        case "green": return Color(wLight: 0x1DA34C, wDark: 0x30D158)
        case "orange": return Color(wLight: 0xC96A00, wDark: 0xFF9F0A)
        case "pink": return Color(wLight: 0xC2185B, wDark: 0xFF375F)
        default: return Color(wLight: 0x0071E3, wDark: 0x0A84FF)
        }
    }
}

extension Color {
    /// 与 Theme 里同名的那个区分开：`wLight`/`wDark` 前缀避免和 App 的扩展撞车
    init(wLight: UInt32, wDark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? wDark : wLight
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

// MARK: - 小组件底板

/// 桌面上的小组件不能用实时模糊（WidgetKit 里没有），
/// 所以给一层**不透明**底色 + 主色光晕：
/// 壁纸是浅色照片时，半透明底会让深色文字糊在背景里，读不出来。
struct WidgetBackground: View {
    var accent: Color

    private var base: Color {
        Color(wLight: 0xF7F7FB, wDark: 0x101014)
    }

    var body: some View {
        ZStack {
            base
            LinearGradient(
                colors: [accent.opacity(0.14), accent.opacity(0.01)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
}

// MARK: - 时间

enum WidgetFmt {
    static func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }

    /// 通话时长：不足 1 分钟按秒说，超过按「X 分 Y 秒」
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) 秒" }
        return "\(total / 60) 分 \(total % 60) 秒"
    }

    static func hours(_ value: Double) -> String {
        value <= 0 ? "—" : String(format: "%.0f 小时", value)
    }
}

// MARK: - 内容分发

struct WidgetContent: View {
    let snapshot: WidgetSnapshot?
    let kind: WidgetKind
    /// App 内的调试预览要指定尺寸；小组件里留 nil，走环境的 `widgetFamily`
    var familyOverride: WidgetFamily?

    @Environment(\.widgetFamily) private var envFamily

    private var family: WidgetFamily { familyOverride ?? envFamily }
    /// 快照读到就用快照；读不到时**不要**拿示例数据糊弄，
    /// 明确显示「打开 AirPanel 同步」空态，这样用户能立刻看出是「数据没同步」而不是「组件坏了」。
    private var data: WidgetSnapshot { snapshot ?? .empty }
    private var accent: Color { WidgetTheme.accent(data.accent) }
    private var isMedium: Bool { family == .systemMedium }

    var body: some View {
        Group {
            if data.hasData {
                content
            } else {
                WidgetEmptyState(accent: accent)
            }
        }
        .padding(.horizontal, isMedium ? 16 : 14)
        .padding(.vertical, isMedium ? 14 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch (kind, isMedium) {
        case (.device, false): DeviceSmall(data: data, accent: accent)
        case (.device, true): DeviceMedium(data: data, accent: accent)
        case (.calls, false): EventSmall(data: data, accent: accent, mode: .calls)
        case (.calls, true): EventMedium(data: data, accent: accent, mode: .calls)
        case (.sms, false): EventSmall(data: data, accent: accent, mode: .sms)
        case (.sms, true): EventMedium(data: data, accent: accent, mode: .sms)
        case (.stats, false): StatsSmall(data: data, accent: accent)
        case (.stats, true): StatsMedium(data: data, accent: accent)
        }
    }
}

// MARK: - 通用小件

private struct WidgetHeader: View {
    let symbol: String
    let title: String
    var accent: Color
    var trailing: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetTheme.ink3)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetTheme.ink3.opacity(0.8))
            }
        }
    }
}

private struct BigNumber: View {
    let text: String
    var tint: Color
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(text)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let unit {
                Text(unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetTheme.ink3)
            }
        }
    }
}

private struct MetaLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(WidgetTheme.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct OnlineDot: View {
    let online: Bool

    var body: some View {
        Circle()
            .fill(online ? WidgetTheme.online : WidgetTheme.ink3.opacity(0.5))
            .frame(width: 6, height: 6)
    }
}

// MARK: - 设备 · 小

private struct DeviceSmall: View {
    let data: WidgetSnapshot
    let accent: Color

    private var device: WidgetDevice? { data.device }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "iphone.gen3", title: "设备", accent: accent,
                         trailing: "\(data.stats.online)/\(data.stats.devices)")

            Spacer(minLength: 6)

            if let device {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    BigNumber(text: "\(device.battery)", tint: batteryTint(device),
                              unit: "%")
                    if device.charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WidgetTheme.online)
                    }
                }
                MetaLine(text: String(format: "%.2f V · %.1f ℃ · CSQ %d",
                                      device.voltage, device.temperature, device.csq))
            } else {
                Text("还没有设备")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WidgetTheme.ink3)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                OnlineDot(online: device?.online ?? false)
                Text(device?.name ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetTheme.ink2)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 设备 · 中

private struct DeviceMedium: View {
    let data: WidgetSnapshot
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(symbol: "iphone.gen3", title: "设备", accent: accent,
                         trailing: "在线 \(data.stats.online)/\(data.stats.devices)")

            HStack(alignment: .top, spacing: 14) {
                ring
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(data.devices.prefix(3).enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(WidgetTheme.ink3.opacity(0.16))
                                .frame(height: 0.5)
                                .padding(.vertical, 5)
                        }
                        row(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 电量环：比数字更容易一眼看出「还剩多少」
    private var ring: some View {
        let device = data.device
        let value = Double(device?.battery ?? 0) / 100
        let tint = device.map(batteryTint) ?? WidgetTheme.ink3

        return ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(device?.battery ?? 0)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.ink)
                Text("%")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetTheme.ink3)
            }
        }
        .frame(width: 74, height: 74)
    }

    private func row(_ device: WidgetDevice) -> some View {
        HStack(spacing: 6) {
            OnlineDot(online: device.online)
            Text(device.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            if device.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WidgetTheme.online)
            }
            Text("\(device.battery)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(device.online ? WidgetTheme.ink2 : WidgetTheme.ink3)
        }
    }
}

// MARK: - 通话 / 短信 · 小

private enum EventMode {
    case calls, sms

    var title: String { self == .calls ? "今日通话" : "今日短信" }
    var symbol: String { self == .calls ? "phone.fill" : "message.fill" }
}

private struct EventSmall: View {
    let data: WidgetSnapshot
    let accent: Color
    let mode: EventMode

    private var total: Int { mode == .calls ? data.stats.callsToday : data.stats.smsToday }
    private var meta: String {
        mode == .calls
            ? "呼入 \(data.stats.callIn) · 呼出 \(data.stats.callOut) · 未接 \(data.stats.callMissed)"
            : "收 \(data.stats.smsIn) · 发 \(data.stats.smsOut) · 拦截 \(data.stats.blockedToday)"
    }
    private var latest: WidgetEvent? {
        mode == .calls ? data.calls.first : data.sms.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: mode.symbol, title: mode.title, accent: accent)

            Spacer(minLength: 6)

            BigNumber(text: "\(total)", tint: WidgetTheme.ink, unit: "条")
            MetaLine(text: meta)

            Spacer(minLength: 6)

            if let latest {
                HStack(spacing: 4) {
                    Image(systemName: latest.tone.symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(latest.tone == .missed ? WidgetTheme.danger : WidgetTheme.ink3)
                    Text(latest.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetTheme.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(WidgetFmt.ago(latest.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetTheme.ink3.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - 通话 / 短信 · 中

private struct EventMedium: View {
    let data: WidgetSnapshot
    let accent: Color
    let mode: EventMode

    private var total: Int { mode == .calls ? data.stats.callsToday : data.stats.smsToday }
    private var summary: String {
        mode == .calls
            ? "呼入 \(data.stats.callIn) · 呼出 \(data.stats.callOut) · 未接 \(data.stats.callMissed)"
            : "收 \(data.stats.smsIn) · 发 \(data.stats.smsOut) · 拦截 \(data.stats.blockedToday)"
    }
    private var items: [WidgetEvent] {
        Array((mode == .calls ? data.calls : data.sms).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(symbol: mode.symbol, title: mode.title, accent: accent,
                         trailing: "\(total) 条")
            Text(summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetTheme.ink3)
                .lineLimit(1)

            if items.isEmpty {
                Spacer(minLength: 0)
                Text("今天还没有\(mode == .calls ? "通话" : "短信")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetTheme.ink3)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(WidgetTheme.ink3.opacity(0.16))
                                .frame(height: 0.5)
                                .padding(.vertical, 4)
                        }
                        row(item)
                    }
                }
            }
        }
    }

    private func row(_ item: WidgetEvent) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.tone.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(item.tone == .missed ? WidgetTheme.danger : accent)
                .frame(width: 12)
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .layoutPriority(1)
            Text(item.detail)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(WidgetTheme.ink3)
                .lineLimit(1)
            Spacer(minLength: 2)
            if item.flagged {
                Text("垃圾")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WidgetTheme.danger)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(WidgetTheme.danger.opacity(0.14)))
            }
            Text(WidgetFmt.ago(item.date))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetTheme.ink3.opacity(0.8))
                .lineLimit(1)
        }
    }
}

// MARK: - 统计 · 小

private struct StatsSmall: View {
    let data: WidgetSnapshot
    let accent: Color

    private var cells: [(String, Int, Color)] {
        [("通话", data.stats.callsToday, WidgetTheme.ink),
         ("短信", data.stats.smsToday, WidgetTheme.ink),
         ("任务", data.stats.tasksToday, WidgetTheme.ink),
         ("拦截", data.stats.blockedToday, data.stats.blockedToday > 0 ? WidgetTheme.danger : WidgetTheme.ink)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "chart.bar.fill", title: "今日统计", accent: accent)

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    tile(cells[0]); tile(cells[1])
                }
                HStack(spacing: 8) {
                    tile(cells[2]); tile(cells[3])
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func tile(_ cell: (String, Int, Color)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(cell.1)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(cell.2)
            Text(cell.0)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WidgetTheme.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 统计 · 中

private struct StatsMedium: View {
    let data: WidgetSnapshot
    let accent: Color

    private var cells: [(String, String, Int, Color)] {
        [("通话", "phone.fill", data.stats.callsToday, WidgetTheme.ink),
         ("未接", "phone.down.fill", data.stats.callMissed, WidgetTheme.danger),
         ("短信", "message.fill", data.stats.smsToday, WidgetTheme.ink),
         ("任务", "bolt.horizontal.fill", data.stats.tasksToday, accent),
         ("失败", "exclamationmark.triangle.fill", data.stats.tasksFailed,
          data.stats.tasksFailed > 0 ? WidgetTheme.warn : WidgetTheme.ink3),
         ("拦截", "hand.raised.fill", data.stats.blockedToday,
          data.stats.blockedToday > 0 ? WidgetTheme.danger : WidgetTheme.ink3)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(symbol: "chart.bar.fill", title: "今日统计", accent: accent,
                         trailing: "在线 \(data.stats.online)/\(data.stats.devices)")

            HStack(spacing: 10) {
                ForEach(Array(cells.prefix(3).enumerated()), id: \.offset) { _, cell in
                    tile(cell)
                }
            }
            HStack(spacing: 10) {
                ForEach(Array(cells.suffix(3).enumerated()), id: \.offset) { _, cell in
                    tile(cell)
                }
            }
        }
    }

    private func tile(_ cell: (String, String, Int, Color)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: cell.1)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(cell.3.opacity(0.9))
                Text(cell.0)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(WidgetTheme.ink3)
            }
            Text("\(cell.2)")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(cell.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WidgetTheme.ink3.opacity(0.10))
        )
    }
}

// MARK: - 空状态

private struct WidgetEmptyState: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
            Text("打开 AirPanel")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.ink)
            Text("同步一次设备数据后，这里就会显示内容")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 电量配色

/// 低电量用危险色、充电中用在线绿、其余用主色——
/// 和 App 概览页的「电量」口径保持一致（20% 以下算低）。
private func batteryTint(_ device: WidgetDevice) -> Color {
    if device.charging { return WidgetTheme.online }
    if device.battery <= 20 { return WidgetTheme.danger }
    if device.battery <= 40 { return WidgetTheme.warn }
    return WidgetTheme.ink
}

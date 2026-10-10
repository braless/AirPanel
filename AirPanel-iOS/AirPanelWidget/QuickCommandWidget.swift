import WidgetKit
import SwiftUI

// MARK: - 快捷命令（点击唤起主 App 执行）

struct QuickCommandEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
}

struct QuickCommandProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCommandEntry { QuickCommandEntry(date: Date(), hasData: false) }
    func getSnapshot(in context: Context, completion: @escaping (QuickCommandEntry) -> Void) {
        completion(QuickCommandEntry(date: Date(), hasData: SharedWidgetData.device() != nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCommandEntry>) -> Void) {
        let e = QuickCommandEntry(date: Date(), hasData: SharedWidgetData.device() != nil)
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct QuickCommandWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelCommands", provider: QuickCommandProvider()) { entry in
            QuickCommandView(entry: entry)
        }
        .configurationDisplayName("快捷命令")
        .description("一键打开拨打电话 / 发送短信 / 重启等操作")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickCommandView: View {
    @Environment(\.widgetFamily) var family
    let entry: QuickCommandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPanel 命令").font(.headline)
            if family == .systemSmall {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { cmdCell("拨打电话", "phone.fill", .green, "dial_call") }
                    GridRow { cmdCell("发送短信", "message.fill", .blue, "send_sms") }
                    GridRow { cmdCell("重启设备", "arrow.clockwise", .orange, "reboot") }
                }
            } else {
                HStack(spacing: 8) {
                    cmdCell("拨打电话", "phone.fill", .green, "dial_call")
                    cmdCell("发送短信", "message.fill", .blue, "send_sms")
                    cmdCell("写入配置", "pencil", .purple, "set_config")
                    cmdCell("重启设备", "arrow.clockwise", .orange, "reboot")
                }
            }
            Text(entry.hasData ? "点击后由主 App 执行" : "请先打开 AirPanel 登录")
                .font(.caption2).foregroundColor(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func cmdCell(_ title: String, _ icon: String, _ color: Color, _ task: String) -> some View {
        Link(destination: URL(string: "airpanel://command?task=\(task)")!) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3).foregroundColor(color)
                Text(title).font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

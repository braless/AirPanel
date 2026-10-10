import WidgetKit
import SwiftUI

// MARK: - 来电记录

struct CallsEntry: TimelineEntry {
    let date: Date
    let items: [SharedWidgetData.CallItem]
}

struct CallsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CallsEntry { CallsEntry(date: Date(), items: []) }
    func getSnapshot(in context: Context, completion: @escaping (CallsEntry) -> Void) {
        completion(CallsEntry(date: Date(), items: SharedWidgetData.calls()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CallsEntry>) -> Void) {
        Task {
            let fresh = await WidgetAPI.fetchCalls()
            let items = fresh.isEmpty ? SharedWidgetData.calls() : fresh
            completion(Timeline(entries: [CallsEntry(date: Date(), items: items)],
                                policy: .after(Date().addingTimeInterval(900))))
        }
    }
}

struct CallsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelCalls", provider: CallsProvider()) { entry in
            CallsView(entry: entry)
        }
        .configurationDisplayName("来电记录")
        .description("展示最近的来电记录")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CallsView: View {
    @Environment(\.widgetFamily) var family
    let entry: CallsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("最近来电", systemImage: "phone.fill")
                .font(.headline)
            if entry.items.isEmpty {
                Spacer()
                Text("暂无来电记录").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.items.prefix(family == .systemLarge ? 6 : 3), id: \.time) { it in
                    HStack {
                        Image(systemName: dirIcon(it.direction)).foregroundColor(dirColor(it.direction))
                        Text(wgMasked(it.number)).font(.caption.weight(.semibold))
                        Spacer()
                        Text(wgTime(it.time)).font(.caption2).foregroundColor(.secondary)
                        if it.spam { Text("骚扰").font(.caption2.weight(.bold)).foregroundColor(.orange) }
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func dirIcon(_ d: String) -> String {
        d == "outgoing" ? "arrow.up.right" : (d == "missed" ? "arrow.down.circle" : "arrow.down.left")
    }
    func dirColor(_ d: String) -> Color {
        d == "missed" ? .red : (d == "outgoing" ? .green : .blue)
    }
}

/// 通用时间格式化（小组件内）
func wgTime(_ t: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
}

import WidgetKit
import SwiftUI

// MARK: - 短信记录

struct SmsEntry: TimelineEntry {
    let date: Date
    let items: [SharedWidgetData.SmsItem]
}

struct SmsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmsEntry { SmsEntry(date: Date(), items: []) }
    func getSnapshot(in context: Context, completion: @escaping (SmsEntry) -> Void) {
        completion(SmsEntry(date: Date(), items: SharedWidgetData.sms()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SmsEntry>) -> Void) {
        Task {
            let cached = SharedWidgetData.sms()
            let items = cached.isEmpty ? await WidgetAPI.fetchSms() : cached
            completion(Timeline(entries: [SmsEntry(date: Date(), items: items)],
                                policy: .after(Date().addingTimeInterval(900))))
        }
    }
}

struct SMSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelSMS", provider: SmsProvider()) { entry in
            SmsView(entry: entry)
        }
        .configurationDisplayName("短信记录")
        .description("展示最近的短信记录")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SmsView: View {
    @Environment(\.widgetFamily) var family
    let entry: SmsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("最近短信", systemImage: "message.fill")
                .font(.headline)
            if entry.items.isEmpty {
                Spacer()
                Text("暂无短信记录").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.items.prefix(family == .systemLarge ? 6 : 3), id: \.time) { it in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(wgMasked(it.number)).font(.caption.weight(.semibold))
                            Spacer()
                            Text(wgTime(it.time)).font(.caption2).foregroundColor(.secondary)
                            if it.spam { Text("垃圾").font(.caption2.weight(.bold)).foregroundColor(.orange) }
                        }
                        Text(it.content).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

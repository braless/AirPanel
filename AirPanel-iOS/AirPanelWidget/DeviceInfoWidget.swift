import WidgetKit
import SwiftUI

// MARK: - 设备信息

struct DeviceEntry: TimelineEntry {
    let date: Date
    let device: SharedWidgetData.DeviceItem?
}

struct DeviceProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeviceEntry { DeviceEntry(date: Date(), device: nil) }
    func getSnapshot(in context: Context, completion: @escaping (DeviceEntry) -> Void) {
        completion(DeviceEntry(date: Date(), device: SharedWidgetData.device()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeviceEntry>) -> Void) {
        Task {
            if let cached = SharedWidgetData.device() {
                let e = DeviceEntry(date: Date(), device: cached)
                completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(1800))))
            } else {
                let fresh = await WidgetAPI.fetchDevice()
                let e = DeviceEntry(date: Date(), device: fresh)
                completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(900))))
            }
        }
    }
}

struct DeviceInfoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelDeviceInfo", provider: DeviceProvider()) { entry in
            DeviceInfoView(entry: entry)
        }
        .configurationDisplayName("设备信息")
        .description("展示 AirPanel 设备的在线状态、电量与信号")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DeviceInfoView: View {
    @Environment(\.widgetFamily) var family
    let entry: DeviceEntry

    var body: some View {
        if let d = entry.device {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Label(d.online ? "在线" : "离线", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(d.online ? Color.green : Color.secondary)
                    Spacer(minLength: 4)
                    Text("最后在线 \(wgLastSeenText(d.lastSeen))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(d.name.isEmpty ? wgMaskedIMEI(d.imei) : d.name)
                    .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                    .lineLimit(1)
                Text("IMEI \(wgMaskedIMEI(d.imei))").font(.caption2).foregroundColor(.secondary)
                if family == .systemMedium {
                    Text("号码 \(wgMasked(d.phone))").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    if d.battery >= 0 {
                        Label("\(d.battery)%", systemImage: batteryIcon(d.battery)).font(.caption2)
                    }
                    if d.csq >= 0 {
                        Label("信号 \(d.csq)", systemImage: "cellularbars").font(.caption2)
                    }
                    if !d.netMode.isEmpty {
                        Text(d.netMode).font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title2)
                Text("打开 AirPanel 同步设备信息").font(.caption2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    func batteryIcon(_ v: Int) -> String {
        v >= 100 ? "battery.100percent" : (v >= 66 ? "battery.75percent" : (v >= 33 ? "battery.50percent" : (v >= 10 ? "battery.25percent" : "battery.0percent")))
    }
}

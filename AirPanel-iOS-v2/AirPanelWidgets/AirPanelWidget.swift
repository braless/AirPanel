import SwiftUI
import WidgetKit

// MARK: - 小组件（经典 TimelineProvider）
//
// 旧版用 AppIntentConfiguration 在部分侧载环境下渲染空白（能添加、有选择器，
// 但桌面 timeline 不绘制）。这里改回 v1 验证过可用的经典方式：
// `TimelineProvider` + `StaticConfiguration`，由 4 个独立小组件组成 WidgetBundle，
// 每个固定显示一类内容（设备 / 通话 / 短信 / 统计）。
// 数据来源统一是 App 写进 App Group 的快照（WidgetSnapshotStore.load()）。

struct AirPanelEntry: TimelineEntry {
    let date: Date
    let kind: WidgetKind
    let snapshot: WidgetSnapshot?
}

struct AirPanelProvider: TimelineProvider {
    let kind: WidgetKind

    func placeholder(in context: Context) -> AirPanelEntry {
        // 小组件库里的预览用示例数据，好看；真实桌面走 getSnapshot/getTimeline。
        AirPanelEntry(date: .now, kind: kind, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (AirPanelEntry) -> Void) {
        // 小组件库预览给示例数据；真实桌面读共享快照。
        completion(AirPanelEntry(date: .now, kind: kind,
                                 snapshot: context.isPreview ? .preview : WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AirPanelEntry>) -> Void) {
        let entry = AirPanelEntry(date: .now, kind: kind, snapshot: WidgetSnapshotStore.load())
        // 快照只在 App 刷新时变，App 写完会主动 reloadAllTimelines；
        // 这里留 20 分钟兜底，避免系统长期不给刷新机会时时间停在很久以前。
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(20 * 60))))
    }
}

// MARK: - 4 个独立小组件

struct DeviceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelDevice", provider: AirPanelProvider(kind: .device)) { entry in
            WidgetContent(snapshot: entry.snapshot, kind: entry.kind)
                .containerBackground(for: .widget) {
                    WidgetBackground(accent: WidgetTheme.accent(entry.snapshot?.accent ?? "blue"))
                }
        }
        .configurationDisplayName("设备信息")
        .description("设备状态：电量、电压、温度、信号")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct CallsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelCalls", provider: AirPanelProvider(kind: .calls)) { entry in
            WidgetContent(snapshot: entry.snapshot, kind: entry.kind)
                .containerBackground(for: .widget) {
                    WidgetBackground(accent: WidgetTheme.accent(entry.snapshot?.accent ?? "blue"))
                }
        }
        .configurationDisplayName("通话信息")
        .description("今日通话与最近三通")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct SmsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelSms", provider: AirPanelProvider(kind: .sms)) { entry in
            WidgetContent(snapshot: entry.snapshot, kind: entry.kind)
                .containerBackground(for: .widget) {
                    WidgetBackground(accent: WidgetTheme.accent(entry.snapshot?.accent ?? "blue"))
                }
        }
        .configurationDisplayName("短信息")
        .description("今日短信与最近三条")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct StatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirPanelStats", provider: AirPanelProvider(kind: .stats)) { entry in
            WidgetContent(snapshot: entry.snapshot, kind: entry.kind)
                .containerBackground(for: .widget) {
                    WidgetBackground(accent: WidgetTheme.accent(entry.snapshot?.accent ?? "blue"))
                }
        }
        .configurationDisplayName("消息统计")
        .description("通话 / 短信 / 任务 / 拦截")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

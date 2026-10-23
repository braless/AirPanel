import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 可选内容
//
// 用户长按桌面 →「编辑小组件」→「显示内容」里看到的就是这三个。
// 用 AppEnum 而不是自由文本：枚举能出选择器，用户不用打字。

enum WidgetKindOption: String, AppEnum {
    case device
    case calls
    case sms
    case stats

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "显示内容")

    static var caseDisplayRepresentations: [WidgetKindOption: DisplayRepresentation] = [
        .device: DisplayRepresentation(title: "设备信息",
                                       subtitle: "电量、电压、温度、信号",
                                       image: .init(systemName: "iphone.gen3")),
        .calls: DisplayRepresentation(title: "通话信息",
                                      subtitle: "今日通话与最近三通",
                                      image: .init(systemName: "phone.fill")),
        .sms: DisplayRepresentation(title: "短信息",
                                    subtitle: "今日短信与最近三条",
                                    image: .init(systemName: "message.fill")),
        .stats: DisplayRepresentation(title: "消息统计",
                                      subtitle: "通话 / 短信 / 任务 / 拦截",
                                      image: .init(systemName: "chart.bar.fill"))
    ]

    var kind: WidgetKind { WidgetKind(rawValue: rawValue) ?? .device }
}

struct AirPanelWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "AirPanel 小组件"
    static var description = IntentDescription("选择小组件显示的内容；尺寸在系统的「小 / 中」之间切换。")

    @Parameter(title: "显示内容", default: .device)
    var kind: WidgetKindOption

    init() {}
}

// MARK: - 时间线

struct AirPanelEntry: TimelineEntry {
    let date: Date
    let kind: WidgetKind
    let snapshot: WidgetSnapshot?
}

struct AirPanelProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> AirPanelEntry {
        AirPanelEntry(date: .now, kind: .device, snapshot: .preview)
    }

    func snapshot(for configuration: AirPanelWidgetIntent, in context: Context) async -> AirPanelEntry {
        // 小组件库里展示的预览一律用占位数据：
        // 那里是给别人看的，不该出现真实的通话号码和短信内容。
        AirPanelEntry(
            date: .now,
            kind: configuration.kind.kind,
            snapshot: context.isPreview ? .preview : WidgetSnapshotStore.load()
        )
    }

    func timeline(for configuration: AirPanelWidgetIntent, in context: Context) async -> Timeline<AirPanelEntry> {
        let entry = AirPanelEntry(
            date: .now,
            kind: configuration.kind.kind,
            snapshot: WidgetSnapshotStore.load()
        )
        // 快照只在 App 刷新时变，App 写完会主动 reloadAllTimelines；
        // 这里仍留 20 分钟兜底，免得系统长期不给刷新机会时时间显示停在很久以前。
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(20 * 60)))
    }
}

// MARK: - 小组件

struct AirPanelWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetShared.widgetKind,
            intent: AirPanelWidgetIntent.self,
            provider: AirPanelProvider()
        ) { entry in
            WidgetContent(snapshot: entry.snapshot, kind: entry.kind)
                .containerBackground(for: .widget) {
                    WidgetBackground(accent: WidgetTheme.accent(entry.snapshot?.accent ?? "blue"))
                }
        }
        .configurationDisplayName("AirPanel")
        .description("设备状态、通话、短信与消息统计。长按小组件 →「编辑小组件」可切换显示内容。")
        .supportedFamilies([.systemSmall, .systemMedium])
        // 边距自己算（WidgetContent 里有 padding），关掉系统的默认边距，
        // 否则中组件右侧会多出一圈空白。
        .contentMarginsDisabled()
    }
}

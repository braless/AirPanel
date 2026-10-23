import Foundation
import WidgetKit

// MARK: - 小组件共享数据
//
// 小组件是**独立进程**：没有网络栈、没有 token、更不能碰 Keychain。
// 所以这里不做任何请求，App 每次刷新完把结果写一份「快照」到 App Group，
// 小组件只读这份快照。快照里只放渲染要用的字段——不放凭据、不放整段短信库。
//
// 文件同时编进 App 与 Widget 两个 target（同一个 PBXFileSystemSynchronizedRootGroup
// 挂在两个 target 上），所以这里不能 import App 里的任何类型。

enum WidgetShared {
    /// 必须在 App 与 Widget 的 entitlements 里都声明，否则两边看到的是两个沙盒
    static let appGroup = "group.com.oaife.airpanel.v2"
    /// 存储 key 带版本号：以后字段变了直接换 key，老快照自动作废，不用写迁移
    static let storageKey = "widget.snapshot.v2"
    /// Widget 的 kind，必须和 `AppIntentConfiguration(kind:)` 一致
    static let widgetKind = "AirPanelWidget"
}

// MARK: - 显示类型
//
// 用户在桌面长按 →「编辑小组件」里选的就是它。
// 存成字符串而不是下标：AppEnum 的 rawValue 要稳定，不能因为调换顺序就串了。

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case device
    case calls
    case sms
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: return "设备"
        case .calls: return "通话"
        case .sms: return "短信"
        case .stats: return "统计"
        }
    }

    var symbol: String {
        switch self {
        case .device: return "iphone.gen3"
        case .calls: return "phone.fill"
        case .sms: return "message.fill"
        case .stats: return "chart.bar.fill"
        }
    }
}

// MARK: - 快照结构

struct WidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    /// 服务端地址只留主机名，用于在小组件角上标一句「哪台服务器」
    var serverHost: String
    /// 当前设备（概览里选中的那台）
    var device: WidgetDevice?
    /// 全部设备，最多留 3 台给中组件列表用
    var devices: [WidgetDevice]
    var calls: [WidgetEvent]
    var sms: [WidgetEvent]
    var stats: WidgetStats
    /// 主题配色名（blue/violet/…），小组件跟着 App 的配色走
    var accent: String

    static let empty = WidgetSnapshot(
        updatedAt: .distantPast,
        serverHost: "",
        device: nil,
        devices: [],
        calls: [],
        sms: [],
        stats: .zero,
        accent: "blue"
    )

    var hasData: Bool { device != nil || !devices.isEmpty }
}

struct WidgetDevice: Codable, Equatable, Identifiable {
    var id: String          // imei
    var name: String
    var online: Bool
    var battery: Int
    var charging: Bool
    var voltage: Double     // V
    var temperature: Double // ℃
    var csq: Int
    var estHours: Double    // 0 表示服务端没给估算
}

struct WidgetEvent: Codable, Equatable, Identifiable {
    enum Tone: String, Codable {
        case incoming, outgoing, missed, plain

        var symbol: String {
            switch self {
            case .incoming: return "arrow.down.left"
            case .outgoing: return "arrow.up.right"
            case .missed: return "phone.down.fill"
            case .plain: return "message.fill"
            }
        }
    }

    var id: String
    var title: String   // 号码或联系人
    var detail: String  // 通话时长 / 短信正文摘要
    var date: Date
    var tone: Tone
    var flagged: Bool   // 垃圾标记
}

struct WidgetStats: Codable, Equatable {
    var devices: Int
    var online: Int
    var callsToday: Int
    var callIn: Int
    var callOut: Int
    var callMissed: Int
    var smsToday: Int
    var smsIn: Int
    var smsOut: Int
    var tasksToday: Int
    var tasksOK: Int
    var tasksFailed: Int
    var blockedToday: Int

    static let zero = WidgetStats(devices: 0, online: 0, callsToday: 0, callIn: 0,
                                  callOut: 0, callMissed: 0, smsToday: 0, smsIn: 0,
                                  smsOut: 0, tasksToday: 0, tasksOK: 0,
                                  tasksFailed: 0, blockedToday: 0)
}

// MARK: - 读写

enum WidgetSnapshotStore {

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetShared.appGroup)
    }

    /// App 侧调用。写完立刻让 WidgetKit 重画，
    /// 不然要等下一次系统排期（可能十几分钟），用户会以为小组件坏了。
    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: WidgetShared.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: WidgetShared.storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// 退出登录时清掉：桌面还留着上一台服务器的设备状态很奇怪
    static func clear() {
        defaults?.removeObject(forKey: WidgetShared.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - 占位数据
//
// 小组件库里的预览、以及首次安装还没打开 App 时用它，
// 保证任何时刻都有内容可画，不会出现一片空白。

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        updatedAt: .now,
        serverHost: "panel.example.com",
        device: WidgetDevice(id: "1", name: "客厅 · Air724", online: true,
                             battery: 62, charging: false, voltage: 3.87,
                             temperature: 33.8, csq: 18, estHours: 18),
        devices: [
            WidgetDevice(id: "1", name: "客厅 · Air724", online: true,
                         battery: 62, charging: false, voltage: 3.87,
                         temperature: 33.8, csq: 18, estHours: 18),
            WidgetDevice(id: "2", name: "工作室备用机", online: false,
                         battery: 41, charging: false, voltage: 3.72,
                         temperature: 28.4, csq: 12, estHours: 0)
        ],
        calls: [
            WidgetEvent(id: "c1", title: "138 0013 8000", detail: "通话 1 分 12 秒",
                        date: .now.addingTimeInterval(-600), tone: .incoming, flagged: false),
            WidgetEvent(id: "c2", title: "未知号码", detail: "未接来电",
                        date: .now.addingTimeInterval(-3600), tone: .missed, flagged: true),
            WidgetEvent(id: "c3", title: "139 1234 5678", detail: "通话 26 秒",
                        date: .now.addingTimeInterval(-7200), tone: .outgoing, flagged: false)
        ],
        sms: [
            WidgetEvent(id: "s1", title: "10086", detail: "您本月流量已使用 8.2GB",
                        date: .now.addingTimeInterval(-300), tone: .incoming, flagged: false),
            WidgetEvent(id: "s2", title: "95588", detail: "尾号 3721 账户收入 1,200.00 元",
                        date: .now.addingTimeInterval(-5400), tone: .incoming, flagged: false),
            WidgetEvent(id: "s3", title: "1069 8888", detail: "【优惠】点击领取 20 元话费券",
                        date: .now.addingTimeInterval(-9000), tone: .incoming, flagged: true)
        ],
        stats: WidgetStats(devices: 2, online: 1, callsToday: 12, callIn: 8, callOut: 3,
                           callMissed: 4, smsToday: 9, smsIn: 7, smsOut: 2,
                           tasksToday: 6, tasksOK: 5, tasksFailed: 1, blockedToday: 3),
        accent: "blue"
    )
}

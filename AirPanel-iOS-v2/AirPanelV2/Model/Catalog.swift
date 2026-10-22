import SwiftUI

// MARK: - 指令元数据类型

enum CommandGroup: String, CaseIterable, Hashable {
    case query = "查询"
    case comms = "通信"
    case system = "配置与系统"
}

struct FieldOption: Hashable {
    var value: String
    var label: String
}

enum FieldKind: Hashable {
    case text
    case multiline
    case select([FieldOption])
}

struct CommandField: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var label: String
    var placeholder: String
    var kind: FieldKind = .text
    var defaultValue: String = ""
    var required: Bool = true
}

struct Command: Identifiable, Hashable {
    var id: String
    var label: String
    var symbol: String
    var group: CommandGroup
    var summary: String
    var fields: [CommandField]
    var tint: Color

    var needsForm: Bool { !fields.isEmpty }
}

// MARK: - 指令目录
//
// 与 server-go-v2/static/js/pages/tasks.js 的 TASKS 一一对应：18 条远程命令。
// 这是纯静态元数据（标签、图标、参数字段），不来自接口——
// 服务端只接受 imei + task + 任意参数，没有「列出支持哪些命令」的端点。

enum Catalog {

    static let all: [Command] = [
        // 查询
        Command(id: "get_temperature", label: "查询温度", symbol: "thermometer.medium", group: .query,
                summary: "读取模组芯片温度", fields: [], tint: Theme.cyan),
        Command(id: "get_status", label: "查询状态", symbol: "waveform.path.ecg", group: .query,
                summary: "电压 / 温度 / 信号 / 运营商", fields: [], tint: Theme.cyan),
        Command(id: "get_device_info", label: "设备信息", symbol: "cpu", group: .query,
                summary: "IMEI / SN / ICCID / 版本", fields: [], tint: Theme.cyan),
        Command(id: "get_config", label: "读取配置", symbol: "doc.text.magnifyingglass", group: .query,
                summary: "返回 nvm_para.lua 全文", fields: [], tint: Theme.cyan),
        Command(id: "query_traffic", label: "查询流量", symbol: "antenna.radiowaves.left.and.right", group: .query,
                summary: "向运营商发查询短信", fields: [], tint: Theme.cyan),

        // 通信
        Command(id: "send_sms", label: "发送短信", symbol: "message.badge", group: .comms,
                summary: "通过设备 SIM 卡发短信", fields: [
                    CommandField(key: "rcv_phone", label: "接收号码", placeholder: "13800138000"),
                    CommandField(key: "content", label: "短信内容", placeholder: "最多 70 个字，超出按多条计费", kind: .multiline)
                ], tint: Theme.accent),
        Command(id: "dial_call", label: "拨打电话", symbol: "phone.arrow.up.right", group: .comms,
                summary: "设备拨打指定号码", fields: [
                    CommandField(key: "phone", label: "被叫号码", placeholder: "13912345678")
                ], tint: Theme.accent),
        Command(id: "hang_up", label: "挂断通话", symbol: "phone.down", group: .comms,
                summary: "结束当前通话", fields: [], tint: Theme.accent),
        Command(id: "send_dtmf", label: "发送按键", symbol: "circle.grid.3x3", group: .comms,
                summary: "通话中发送 DTMF 按键", fields: [
                    CommandField(key: "dtmf", label: "按键串", placeholder: "123")
                ], tint: Theme.accent),
        Command(id: "tts_speak", label: "语音播报", symbol: "speaker.wave.2", group: .comms,
                summary: "扬声器 TTS 朗读", fields: [
                    CommandField(key: "text", label: "朗读文本", placeholder: "快递已到，请下楼取件", kind: .multiline)
                ], tint: Theme.accent),
        Command(id: "set_ccfc", label: "设置呼转", symbol: "arrow.turn.up.right", group: .comms,
                summary: "无条件呼叫转移", fields: [
                    CommandField(key: "phone", label: "呼转号码（0=取消）", placeholder: "13800138000")
                ], tint: Theme.accent),
        Command(id: "ussd_query", label: "USSD 查询", symbol: "terminal", group: .comms,
                summary: "查话费 / 余额", fields: [
                    CommandField(key: "code", label: "USSD 查询码", placeholder: "*108#")
                ], tint: Theme.accent),

        // 配置与系统
        Command(id: "set_config", label: "写入配置", symbol: "square.and.arrow.down", group: .system,
                summary: "整体覆盖 nvm_para.lua", fields: [], tint: Theme.violet),
        Command(id: "edit_config", label: "编辑配置", symbol: "pencil.line", group: .system,
                summary: "读取后在线修改保存", fields: [], tint: Theme.violet),
        Command(id: "set_volume", label: "设置音量", symbol: "speaker.wave.3", group: .system,
                summary: "扬声器与通话音量", fields: [
                    CommandField(key: "vol", label: "音量 (0-10)", placeholder: "6", defaultValue: "6")
                ], tint: Theme.violet),
        Command(id: "set_gpio", label: "GPIO 控制", symbol: "switch.2", group: .system,
                summary: "设置引脚输出电平", fields: [
                    CommandField(key: "pin", label: "GPIO 引脚编号", placeholder: "1"),
                    CommandField(key: "level", label: "电平", placeholder: "",
                                 kind: .select([FieldOption(value: "1", label: "1 · 高电平"),
                                                FieldOption(value: "0", label: "0 · 低电平")]),
                                 defaultValue: "1")
                ], tint: Theme.violet),
        Command(id: "switch_sim", label: "切换 SIM", symbol: "simcard.2", group: .system,
                summary: "主副卡槽切换并重启", fields: [], tint: Theme.violet),
        Command(id: "reboot", label: "重启设备", symbol: "arrow.clockwise", group: .system,
                summary: "软重启设备", fields: [], tint: Theme.violet)
    ]

    static func command(_ id: String) -> Command? {
        all.first { $0.id == id }
    }

    /// 首页快捷入口
    static let quick: [String] = ["send_sms", "dial_call", "get_status", "reboot"]

    /// 任务页「常用指令」：跨越三个分组，选真正高频的六条
    static let primary: [String] = [
        "send_sms", "dial_call", "get_status",
        "get_config", "set_config", "reboot"
    ]
}

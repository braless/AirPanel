import SwiftUI

// MARK: - 设计令牌
//
// 所有间距 / 圆角 / 字重都从这里取，页面里不写魔法数字。
// 颜色走动态色，浅色深色各一套；原型默认以深色为主视觉。

enum Theme {

    // MARK: 颜色

    /// 画布底色。比纯黑略亮一点点，让玻璃材质有层次可折射。
    static let canvas = Color(light: 0xF2F2F6, dark: 0x08080B)

    /// 主文字
    static let ink = Color(light: 0x0A0A0C, dark: 0xF7F7F9)
    /// 次要文字（说明、时间戳）
    static let ink2 = Color(light: 0x60606A, dark: 0x9C9CA6)
    /// 三级文字（标签、单位）
    static let ink3 = Color(light: 0x8C8C96, dark: 0x6B6B76)

    /// 品牌主色（设置里可换：蓝/紫/青/绿/橙/粉）
    /// 走计算属性而不是 `static let`：切换配色要能立刻反映到所有页面。
    static var accent: Color { AccentTheme.shared.choice.color }
    /// 在线 / 成功
    static let online = Color(light: 0x1DA34C, dark: 0x30D158)
    /// 警告（低电量、信号弱）
    static let warn = Color(light: 0xD97706, dark: 0xFF9F0A)
    /// 危险（删除、离线、垃圾标记）
    static let danger = Color(light: 0xD92D20, dark: 0xFF453A)
    /// 自动化 / 配置类任务
    static let violet = Color(light: 0x8E44D0, dark: 0xBF5AF2)
    /// 查询 / 信息类
    static let cyan = Color(light: 0x0A84C8, dark: 0x64D2FF)

    /// 玻璃卡片上的高光描边：上沿受光、下沿收敛
    static let hairlineTop = Color.white.opacity(0.14)
    static let hairlineBottom = Color.white.opacity(0.04)

    // MARK: 间距

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 26
        static let xxl: CGFloat = 34
        /// 页面左右安全边距
        static let page: CGFloat = 20
    }

    // MARK: 圆角

    enum Radius {
        static let chip: CGFloat = 13
        static let tile: CGFloat = 18
        static let card: CGFloat = 26
        static let sheet: CGFloat = 34
        static let capsule: CGFloat = 999
    }

    // MARK: 字号
    //
    // 大字号收紧字距、小字号放开，标题靠字重建立层级而不是只靠字号。
    // 数字统一走等宽数字，避免数值跳动时宽度抖动。

    static func display(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .semibold)
    }

    static let title = Font.system(size: 22, weight: .semibold)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let bodyStrong = Font.system(size: 15, weight: .medium)
    static let callout = Font.system(size: 14, weight: .regular)
    static let caption = Font.system(size: 12, weight: .medium)
    static let micro = Font.system(size: 11, weight: .semibold)

    /// 等宽数字：电量、时长、信号这类会变的值
    static func metric(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// 终端 / 配置文本
    static let mono = Font.system(size: 11.5, weight: .regular, design: .monospaced)
}

// MARK: - 动态色构造

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    /// 固定色（不随外观变化），用于灯光色块这类「真实颜色」。
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

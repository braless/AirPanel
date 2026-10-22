import SwiftUI

// MARK: - 外观
//
// 白天 / 黑夜 / 跟随系统。
//
// 存的是字符串（UserDefaults），不是 ColorScheme：ColorScheme 没有
// 「跟随系统」这一档，`nil` 又不能直接落盘。所以自己定义一个三态枚举，
// 由根视图把它翻译成 `preferredColorScheme`。
//
// 注意 `Theme` 里的颜色全是 `Color(light:dark:)` 动态色，
// 所以切换外观不需要重设任何颜色，系统会自己换一套。

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "自动"
        case .light: return "白天"
        case .dark: return "黑夜"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` = 跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var hint: String {
        switch self {
        case .system: return "跟随系统设置，白天浅色、夜间深色"
        case .light: return "始终使用浅色外观"
        case .dark: return "始终使用深色外观"
        }
    }

    /// UserDefaults 的 key
    static let storageKey = "appearance"
}

// MARK: - 主题配色
//
// 只换「主色」（按钮、链接、选中态、图表主线），不动在线/警告/危险这三档语义色——
// 语义色要是能改，红色就不代表危险了，界面会开始撒谎。
//
// 每个选项都备了浅色/深色两个值：深色底上饱和度要降、亮度要提高，
// 直接复用浅色值会显得脏。

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, violet, teal, green, orange, pink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blue: return "蓝"
        case .violet: return "紫"
        case .teal: return "青"
        case .green: return "绿"
        case .orange: return "橙"
        case .pink: return "粉"
        }
    }

    var color: Color {
        switch self {
        case .blue: return Color(light: 0x0071E3, dark: 0x0A84FF)
        case .violet: return Color(light: 0x6E3AD6, dark: 0xBF5AF2)
        case .teal: return Color(light: 0x0E8C9E, dark: 0x40C8E0)
        case .green: return Color(light: 0x1DA34C, dark: 0x30D158)
        case .orange: return Color(light: 0xC96A00, dark: 0xFF9F0A)
        case .pink: return Color(light: 0xC2185B, dark: 0xFF375F)
        }
    }

    static let storageKey = "accentTheme"
}

/// 当前主题配色。
///
/// 用 `@Observable` 而不是让 `Theme.accent` 每次去读 UserDefaults：
/// 读 UserDefaults 拿不到「值变了」的通知，界面不会重画。
/// 视图 body 里访问 `Theme.accent` 就会读到这里的 `choice`，
/// 观察系统自动把依赖记上，切换配色时整个界面跟着换。
@Observable
final class AccentTheme {
    static let shared = AccentTheme()

    var choice: AccentChoice {
        didSet {
            UserDefaults.standard.set(choice.rawValue, forKey: AccentChoice.storageKey)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: AccentChoice.storageKey)
        choice = AccentChoice(rawValue: saved ?? "") ?? .blue
    }
}

import SwiftUI

// MARK: - 动效常量
//
// 决策顺序：先问「要不要动」，再问「为什么动」，最后才定时长。
//  - 高频操作（切 Tab、列表滚动）不动画，或只做 120ms 的颜色渐变。
//  - 布局变化用临界阻尼弹簧（不过冲），因为界面里没有物理抛掷。
//  - 只有带手势速度的落位（下拉刷新回弹、抽屉收起）才允许轻微过冲。
//  - 所有动画都在 300ms 内收尾。

enum Motion {
    /// 布局 / 状态切换：临界阻尼，优雅不过冲
    static let layout = Animation.spring(response: 0.34, dampingFraction: 1.0)
    /// 手势带速度后的落位：damping 0.8 允许一点点回弹
    static let momentum = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// 按压反馈：短、快、ease-out
    static let press = Animation.easeOut(duration: 0.12)
    /// 颜色 / 透明度渐变
    static let fade = Animation.easeOut(duration: 0.18)
    /// 内容进场（列表项、卡片）：稍慢一点点，用于错峰
    static let enter = Animation.spring(response: 0.42, dampingFraction: 1.0)
}

// MARK: - 尊重「减弱动态效果」
//
// 减弱动态效果不是「什么都不动」，而是把位移换成更短的透明度过渡。
// 这里统一接管，页面里写 .motion(...) 就自动获得该行为。

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.fade : animation, value: value)
    }
}

extension View {
    /// 替代裸 `.animation(_:value:)`，自动处理减弱动态效果。
    func motion<V: Equatable>(_ animation: Animation = Motion.layout, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

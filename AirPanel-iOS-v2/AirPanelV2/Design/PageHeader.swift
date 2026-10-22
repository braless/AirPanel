import SwiftUI

// MARK: - 页面标题
//
// 每个 Tab 的顶部：大标题 + 一行说明 + 右侧动作。
// 标题用负字距（大字号需要收紧），说明用次级灰，右侧只放一个主操作，
// 避免顶栏堆按钮。
//
// `titleAccessory` 是贴在标题右边的挂件（概览用它挂服务端运行时长），
// 和标题上下居中——按基线对齐小字会沉到标题脚下，看着像两行。

struct PageHeader<TitleAccessory: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var titleAccessory: TitleAccessory
    var trailing: Trailing

    init(_ title: String,
         subtitle: String? = nil,
         @ViewBuilder titleAccessory: () -> TitleAccessory,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.titleAccessory = titleAccessory()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 3) {
                // 挂件跟标题**上下居中**对齐：按基线对齐时小字会整体沉下去一截，
                // 看起来像贴在标题脚下。center 让图标/时长跟大标题视觉居中。
                HStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(Theme.display(30))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                    titleAccessory
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension PageHeader where TitleAccessory == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle: subtitle, titleAccessory: { EmptyView() }, trailing: trailing)
    }
}

extension PageHeader where TitleAccessory == EmptyView, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle, titleAccessory: { EmptyView() }, trailing: { EmptyView() })
    }
}

// MARK: - 圆形玻璃按钮（顶栏 / 快捷操作共用）

struct GlassIconButton: View {
    let symbol: String
    var size: CGFloat = 40
    var tint: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - 状态胶囊

struct StatusPill: View {
    let isOnline: Bool
    var text: String?

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(color: isOnline ? Theme.online : Theme.ink3, size: 6)
            Text(text ?? (isOnline ? "在线" : "离线"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isOnline ? Theme.online : Theme.ink2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill((isOnline ? Theme.online : Theme.ink3).opacity(0.13))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder((isOnline ? Theme.online : Theme.ink3).opacity(0.22), lineWidth: 0.75)
        }
    }
}

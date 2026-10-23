import SwiftUI
import WidgetKit

// MARK: - 小组件预览（仅 Debug）
//
// 本机没有辅助功能权限，模拟不了「长按桌面 → 编辑小组件」这套操作，
// 所以把小组件的**同一套视图**搬进 App 里按真实尺寸渲染一遍：
// 小 158×158、中 338×158，配同样的底板与内边距。
//
// 数据优先读 App Group 里的真实快照（能顺便验证 App → 小组件这条链路），
// 读不到才退回占位数据。

struct WidgetPreviewScreen: View {
    @Environment(PanelStore.self) private var store
    @State private var snapshot: WidgetSnapshot?

    private let small = CGSize(width: 158, height: 158)
    private let medium = CGSize(width: 338, height: 158)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    section("小尺寸", family: .systemSmall, size: small, horizontal: true)
                    section("中尺寸", family: .systemMedium, size: medium, horizontal: false)

                    Text(snapshot == nil ? "当前展示的是占位数据" : "数据来自 App Group 快照")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
                .padding(Theme.Space.page)
            }
            .background(AppBackground())
            .task { snapshot = WidgetSnapshotStore.load() }
            // 首屏数据回来后会写一次快照，跟着刷新一下预览
            .onChange(of: store.lastRefresh) { _, _ in
                snapshot = WidgetSnapshotStore.load()
            }
            // 截图用：-wg sms 直接把对应那张中尺寸卡片滚到屏幕上方
            .onAppear {
                guard let focus = Self.focusKind else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { proxy.scrollTo("medium-\(focus.rawValue)", anchor: .top) }
                }
            }
        }
    }

    private static var focusKind: WidgetKind? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-wg"), i + 1 < args.count else { return nil }
        return WidgetKind(rawValue: args[i + 1])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("桌面小组件")
                .font(Theme.display(28))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
            Text("长按桌面小组件 →「编辑小组件」可切换显示内容")
                .font(Theme.caption)
                .foregroundStyle(Theme.ink3)
        }
    }

    /// 小尺寸横向排（一屏能看到三个，暗示还能滑），
    /// 中尺寸一张 338 宽，两张并排会超出屏幕，改成竖向一张一行。
    private func section(_ title: String, family: WidgetFamily, size: CGSize, horizontal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.micro)
                .foregroundStyle(Theme.ink3)

            if horizontal {
                // 小尺寸两张并排刚好放下（158 × 2 + 间距 < 屏宽），
                // 四张一屏看完，不用滑。
                LazyVGrid(columns: [GridItem(.fixed(size.width), spacing: 12),
                                    GridItem(.fixed(size.width), spacing: 12)],
                          alignment: .leading, spacing: 14) {
                    ForEach(WidgetKind.allCases) { kind in
                        card(kind, family: family, size: size)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(WidgetKind.allCases) { kind in
                        card(kind, family: family, size: size)
                            .id("medium-\(kind.rawValue)")
                    }
                }
            }
        }
    }

    private func card(_ kind: WidgetKind, family: WidgetFamily, size: CGSize) -> some View {
        VStack(spacing: 6) {
            WidgetContent(snapshot: snapshot, kind: kind, familyOverride: family)
                .frame(width: size.width, height: size.height)
                .background {
                    WidgetBackground(accent: WidgetTheme.accent(snapshot?.accent ?? "blue"))
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

            Text(kind.title)
                .font(Theme.micro)
                .foregroundStyle(Theme.ink3)
        }
    }
}

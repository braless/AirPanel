import SwiftUI

// MARK: - 按压反馈
//
// 按下即反馈（不等抬起），0.12s ease-out，缩放 0.97。
// 减弱动态效果时保留透明度变化、去掉缩放——反馈还在，只是不位移。

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97
    var dimmed: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? dimmed : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(scale: CGFloat) -> PressableStyle { PressableStyle(scale: scale) }
}

// MARK: - 玻璃卡片
//
// 页面主容器。玻璃负责「浮起一层」，所以里面不要再叠第二层玻璃——
// 内嵌区域用 SolidPanel（半透明实色），否则可读性会塌。

struct GlassCard<Content: View>: View {
    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat = Theme.Space.l
    var content: Content

    init(
        radius: CGFloat = Theme.Radius.card,
        padding: CGFloat = Theme.Space.l,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Color.white.opacity(0.05)), in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.hairlineTop, Theme.hairlineBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
    }
}

/// 卡片内部的次级容器：半透明实色，不用玻璃，保证文字对比度。
struct SolidPanel<Content: View>: View {
    var radius: CGFloat = Theme.Radius.tile
    var fill: Color = Color.primary.opacity(0.055)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            )
    }
}

// MARK: - 分区标题

struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(Theme.caption)
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, Theme.Space.xs)
    }
}

// MARK: - 状态点

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(color.opacity(0.28), lineWidth: 3.5)
            }
    }
}

// MARK: - 图标徽章

struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(tint.opacity(0.15))
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 0.75)
            }
    }
}

// MARK: - 指标小卡

struct StatTile: View {
    let value: String
    let unit: String?
    let label: String
    var tint: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.metric(24))
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ink3)
                }
            }
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

// MARK: - 分段控制器（玻璃胶囊 + 滑动指示块）
//
// 指示块用 matchedGeometryEffect 在选项间移动，比逐个改背景色更连贯；
// 只有选中项变化时才动，切换本身很频繁所以时长压到 0.28s。

struct GlassSegmented<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let isOn = item.value == selection
                Button {
                    guard !isOn else { return }
                    withAnimation(Motion.layout) { selection = item.value }
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? Theme.ink : Theme.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isOn {
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.13))
                                    .matchedGeometryEffect(id: "seg", in: indicator)
                            }
                        }
                }
                .buttonStyle(.pressable(scale: 0.98))
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous).fill(Color.primary.opacity(0.05))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Theme.hairlineBottom, lineWidth: 0.75)
        }
    }
}

// MARK: - 迷你折线图
//
// 只画线 + 面积渐变，不做交互。数据点少时用二次曲线平滑，
// 避免出现锯齿状「假精确」。

struct Sparkline: View {
    var values: [Double]
    var tint: Color
    var lineWidth: CGFloat = 2
    var fillArea: Bool = true

    var body: some View {
        GeometryReader { geo in
            let pts = normalized(in: geo.size)
            ZStack {
                if fillArea, pts.count > 1 {
                    smoothPath(pts, closedIn: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.26), tint.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                smoothPath(pts, closedIn: nil)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                if let last = pts.last {
                    Circle()
                        .fill(tint)
                        .frame(width: lineWidth * 2.4, height: lineWidth * 2.4)
                        .position(last)
                        .shadow(color: tint.opacity(0.6), radius: 4)
                }
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1,
              let lo = values.min(), let hi = values.max()
        else { return [] }
        // 全部相等时（比如信号一直是满格）min-max 归一化会退化成 0，
        // 曲线贴在最底部看起来像「没有数据」。这种情况画中线。
        let flat = hi - lo < 0.0001
        let span = max(hi - lo, 0.0001)
        let inset = lineWidth
        let h = max(size.height - inset * 2, 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            let ratio = flat ? 0.5 : (v - lo) / span
            let y = inset + h - CGFloat(ratio) * h
            return CGPoint(x: CGFloat(idx) * step, y: y)
        }
    }

    private func smoothPath(_ pts: [CGPoint], closedIn size: CGSize?) -> Path {
        var path = Path()
        guard let first = pts.first, let last = pts.last else { return path }
        if let size {
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
        } else {
            path.move(to: first)
        }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            path.addQuadCurve(to: mid, control: p0)
            if i == pts.count - 2 {
                path.addQuadCurve(to: p1, control: mid)
            }
        }
        if let size {
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - 环形电量
//
// 进度环用 trim 画，数值变化时只动 trim 的 end 值，走临界阻尼弹簧。

struct RingGauge: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 9
    var size: CGFloat = 96
    var content: AnyView?

    init(
        progress: Double,
        tint: Color,
        lineWidth: CGFloat = 9,
        size: CGFloat = 96,
        @ViewBuilder content: () -> some View = { EmptyView() }
    ) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
        self.size = size
        self.content = AnyView(content())
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .motion(Motion.layout, value: progress)
            if let content {
                content
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 空状态
//
// 空状态不是「什么都不显示」。给一句下一步该做什么，比画个空盒子有用。

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.ink3)
                .frame(width: 54, height: 54)
                .background(
                    Circle().fill(Color.primary.opacity(0.05))
                )
            VStack(spacing: 5) {
                Text(title)
                    .font(Theme.bodyStrong)
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action.title) { action.run() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.pressable)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .padding(.horizontal, Theme.Space.l)
    }
}

// MARK: - 首次加载占位
//
// 和 EmptyState 长得很像，但说的是「正在取数据」。
// 公网服务端单次往返接近 2 秒，首屏那几秒必须和「真的没有数据」区分开，
// 否则用户会以为设备根本没上报过。

struct LoadingState: View {
    var title: String = "正在读取…"
    var message: String = "首次加载要和服务端对一遍数据，稍等一下。"

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.ink2)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.primary.opacity(0.05)))
            VStack(spacing: 5) {
                Text(title)
                    .font(Theme.bodyStrong)
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .padding(.horizontal, Theme.Space.l)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - 空态 / 加载态
//
// 列表为空时到底该说什么，取决于「这一块数据到了没有」。首屏还在拉的时候说
// 「还没有记录」是错的——用户会以为设备真的没上报过。
//
// 判断依据是 store 里「这一段有没有加载过」，而不是「整体刷新有没有结束」：
// 某个接口偶尔要 30 秒（服务端在等设备回执时会卡住），
// 不能让一个慢接口把所有页面都拖成转圈。

struct EmptyOrLoading: View {
    let symbol: String
    let title: String
    let message: String

    /// 这一段数据还在路上
    var isLoading = false
    /// 加载中的文案，默认跟着空态标题走：「还没有执行记录」→「正在读取执行记录…」
    var loadingTitle: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        if isLoading {
            LoadingState(title: loadingTitle ?? Self.loadingText(for: title))
        } else {
            EmptyState(symbol: symbol, title: title, message: message, action: action)
        }
    }

    /// 「还没有执行记录」→「正在读取执行记录…」；套不上就退回通用文案
    private static func loadingText(for title: String) -> String {
        var t = title
        for prefix in ["还没有", "暂无", "没有"] where t.hasPrefix(prefix) {
            t.removeFirst(prefix.count)
            break
        }
        return t.isEmpty ? "正在读取…" : "正在读取\(t)…"
    }
}

// MARK: - 行内分隔线
//
// 比 1px 边框轻：只用一条 0.5pt 的低对比线，且左右留白跟内容对齐。

struct RowDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - 页面背景
//
// 玻璃需要有东西可折射。底色之外放两团很淡的环境光（静态，不循环运动），
// 设备在线时偏绿、离线时偏灰，让「状态」在整页氛围上也能感知到。

struct AppBackground: View {
    var accent: Color = Theme.accent
    var glow: Color = Theme.online

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.canvas
                Circle()
                    .fill(accent.opacity(0.30))
                    .frame(width: 460, height: 460)
                    .blur(radius: 120)
                    .position(x: geo.size.width * 0.18, y: 40)
                Circle()
                    .fill(glow.opacity(0.20))
                    .frame(width: 380, height: 380)
                    .blur(radius: 110)
                    .position(x: geo.size.width * 0.92, y: 210)
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 420, height: 420)
                    .blur(radius: 130)
                    .position(x: geo.size.width * 0.55, y: geo.size.height * 0.98)
            }
        }
        .ignoresSafeArea()
        .motion(Motion.fade, value: glow)
    }
}

// MARK: - 通知状态胶囊
//
// 「已通知 / 通知失败 / 排队中 / 已屏蔽 / 未通知」，通话与短信共用。
// 正常投递（已通知）用最轻的样式：每条都跳出来会盖住真正要看的信息，
// 只有异常状态（失败、屏蔽、排队）才用重色。

extension NotifyState {
    var tint: Color {
        switch self {
        case .sent: return Theme.accent
        case .failed: return Theme.danger
        case .blocked: return Theme.violet
        case .queued: return Theme.warn
        case .none: return Theme.ink3
        }
    }

    var symbol: String {
        switch self {
        case .sent: return "bell.fill"
        case .failed: return "bell.slash.fill"
        case .blocked: return "hand.raised.fill"
        case .queued: return "clock.fill"
        case .none: return "bell"
        }
    }
}

struct NotifyChip: View {
    let state: NotifyState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: state.symbol)
                .font(.system(size: 7.5, weight: .bold))
            Text(state.label)
                .font(.system(size: 9, weight: .semibold))
                .fixedSize()
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(state.tint.opacity(state == .sent ? 0.10 : 0.16)))
        .accessibilityLabel("通知状态 \(state.label)")
    }
}

// MARK: - 头像
//
// 服务端 `brand.avatar` 存的是一个字符串，三种可能都有：
//   · 图床直链 `https://…`（最常见，用户在网页端填的）
//   · 站内相对路径 `/static/…`（按当前服务器地址补全）
//   · 旧版 base64（可能带 `data:image/…` 前缀）
//
// `AsyncImage` 只认 http(s)，data URI 会直接失败，所以这里统一走一个加载器；
// 加载中/失败都保持「首字母」兜底，不会出现空白圆圈。

struct AvatarView: View {
    let raw: String
    /// 没图时显示的首字母
    let fallback: String
    var size: CGFloat = 48
    /// 站内相对路径要拼在服务器地址后面
    var base: URL?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Theme.accent.opacity(0.9), Theme.violet.opacity(0.8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Text(fallback)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(image == nil ? 1 : 0)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Theme.hairlineTop, lineWidth: 0.75))
        .task(id: raw) { await load() }
    }

    private func load() async {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            image = nil
            return
        }
        if let cached = AvatarCache.shared.get(key) {
            image = cached
            return
        }

        var data: Data?
        if key.hasPrefix("data:"), let comma = key.firstIndex(of: ",") {
            data = Data(base64Encoded: String(key[key.index(after: comma)...]))
        } else if let url = resolve(key) {
            data = try? await URLSession.shared.data(from: url).0
        }

        guard !Task.isCancelled, let data, let decoded = UIImage(data: data) else { return }
        AvatarCache.shared.set(key, decoded)
        withAnimation(Motion.fade) { image = decoded }
    }

    private func resolve(_ raw: String) -> URL? {
        if let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        // 站内相对路径：/static/avatar.png → 拼到服务器地址上
        if raw.hasPrefix("/"), let base {
            return URL(string: raw, relativeTo: base)?.absoluteURL
        }
        return nil
    }
}

/// 头像下载缓存：切页面回来不该再打一次网络
private final class AvatarCache {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, UIImage>()

    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ key: String, _ value: UIImage) { cache.setObject(value, forKey: key as NSString) }
}

// MARK: - 左滑删除
//
// 列表不是 `List`（卡片 + 玻璃 + 按天分组），用不了系统 `.swipeActions`，
// 所以自己接一个水平拖拽：
//   · 短滑（> 0.6 个按钮宽）停在「删除」按钮上，点一下才删
//   · 长滑（> 150pt）直接删，符合「一划就没」的直觉
//
// 两个坑都是踩过才知道的：
//
// 1. **行里不能放 `Button`**。Button 的点击在拖拽抬手时照样会触发，
//    于是左滑会顺带打开详情，上下滚动也会莫名进详情页。
//    改成 `onTapGesture`（手指移动超过阈值就不算点击），从根上没这问题。
//
// 2. **手势必须先判方向再接管**。原来每一帧都写 `offset`，竖直滚动时
//    行会跟着手指抖，ScrollView 也像被卡住——现在先锁轴，判成竖直就彻底不碰。
//
// 红色底只在「行让出来的空间」里出现（宽度 = -offset），
// 这样不用给行加不透明背景，卡片本身的玻璃质感不会被破坏。

struct SwipeToDelete<Content: View>: View {
    /// 点行本身做什么（打开详情）。左滑展开状态下点行是「收起」，不会走这里。
    var onTap: (() -> Void)?
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = SwipeToDelete.debugOpenOffset
    @State private var isOpen = SwipeToDelete.debugOpenOffset < 0
    /// 方向锁：nil = 还没判定，判定后整个手势只认一个方向
    @State private var axis: Axis?
    /// 已请求删除，用来做「删失败就弹回去」的兜底
    @State private var didRequestDelete = false

    private let actionWidth: CGFloat = 78
    private let fullSwipe: CGFloat = 150

    /// 截图 / 联调用：`-swipeopen` 把所有行停在「已左滑」的状态，方便核对红色底的对齐
    static var debugOpenOffset: CGFloat {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-swipeopen") ? -78 : 0
        #else
        return 0
        #endif
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // 红色底：宽度跟着「让出来的空间」走，不铺满整行
            Rectangle()
                .fill(Theme.danger)
                .frame(width: max(0, -offset))
                .overlay(alignment: .trailing) {
                    Button(action: requestDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: actionWidth, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isOpen ? 1 : 0)
                    .allowsHitTesting(isOpen)
                }

            // 点击只挂在「行内容」上，不挂整行：
            // 展开时露出来的红色区域归删除按钮，两边各管一块，不会互相抢事件
            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 展开时点行 = 收起，不打开详情（和系统列表一致）
                    if isOpen { close() } else { onTap?() }
                }
        }
        .clipped()
        .simultaneousGesture(drag)
        .accessibilityAction(named: "删除") { requestDelete() }
        .task(id: didRequestDelete) {
            // 删除失败时这一行不会被移除：给 1.2 秒，还在就弹回原位，
            // 否则会留下一条看不见但占位的「幽灵行」。
            guard didRequestDelete else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, offset < -1 else { return }
            close()
            didRequestDelete = false
        }
    }

    private func close() {
        withAnimation(Motion.layout) { offset = 0 }
        isOpen = false
    }

    private func requestDelete() {
        isOpen = false
        didRequestDelete = true
        onDelete()
    }

    private var drag: some Gesture {
        // 18pt 起步：比系统滑动阈值大一点，避免点按被误判成滑动
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if axis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) > 4 else { return }
                    axis = dx > dy ? .horizontal : .vertical
                }
                // 竖直方向一律不接管，滚动留给外层 ScrollView
                guard axis == .horizontal else { return }
                let base = isOpen ? -actionWidth : 0
                offset = min(0, base + value.translation.width)
            }
            .onEnded { value in
                let locked = axis
                axis = nil
                guard locked == .horizontal else { return }

                let base = isOpen ? -actionWidth : 0
                let end = base + value.translation.width

                if end < -fullSwipe {
                    // 长滑：直接交给列表做删除动画。
                    // 原来先 offset = -420 再删，两层动画叠着，看起来一顿一顿的。
                    requestDelete()
                } else if end < -actionWidth * 0.6 {
                    withAnimation(Motion.layout) { offset = -actionWidth }
                    isOpen = true
                } else {
                    close()
                }
            }
    }
}

import SwiftUI

// MARK: - 玻璃拟态卡片

struct GlassCard<Content: View>: View {
    var padding: CGFloat
    var cornerRadius: CGFloat
    @ViewBuilder var content: Content

    init(padding: CGFloat = 14, cornerRadius: CGFloat = 20,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.stroke.opacity(0.6), Theme.stroke.opacity(0.12)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }
}

// MARK: - 指标卡（概览用）

struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let subtitle: String?
    let color: Color
    var pill: String? = nil
    var pillColor: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 27, weight: .bold)).foregroundColor(Theme.text)
                Text(unit).font(.system(size: 12)).foregroundColor(Theme.text.opacity(0.5))
            }
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.45)).lineLimit(1)
            }
            if let pill {
                Text(pill).font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(pillColor.opacity(0.22), in: Capsule())
                    .foregroundColor(pillColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(LinearGradient(colors: [color.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - 列表行（玻璃行，可带图标与尾部）

struct GlassRow: View {
    var icon: String = "circle.fill"
    var color: Color = Theme.accent
    var title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var trailingColor: Color = Theme.text
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.text)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.text.opacity(0.5))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.system(size: 13, weight: .semibold)).foregroundColor(trailingColor)
            }
            if showChevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.text.opacity(0.4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - 状态胶囊

struct StatusPill: View {
    let text: String
    var color: Color = .green

    var body: some View {
        Text(text).font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundColor(color)
    }
}

// MARK: - 分段控件（玻璃风格）

struct GlassSegmented<Item: Hashable>: View {
    @Binding var selection: Item
    let items: [(Item, String)]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.0) { item, label in
                Button {
                    selection = item
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selection == item ? Theme.text : Theme.text.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selection == item
                                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.37, green: 0.78, blue: 1.0),
                                                                         Color(red: 0.18, green: 0.55, blue: 1.0)],
                                                                startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - 状态视图

struct LoadingView: View {
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.text)
            Text(text).font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundColor(Theme.orange)
            Text(message).font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.6)).multilineTextAlignment(.center)
            Button("重试", action: retry)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Theme.accent.opacity(0.3), in: Capsule())
                .foregroundColor(Theme.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 28)).foregroundColor(Theme.text.opacity(0.3))
            Text(text).font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 渐变主按钮

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var color: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(colors: [color.opacity(0.9), color.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: color.opacity(0.4), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 玻璃输入框

struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .keyboardType(keyboard)
        .font(.system(size: 15))
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .foregroundColor(Theme.text)
    }
}

// MARK: - 键盘处理

/// 收起当前键盘（全局工具）
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// 输入界面键盘上方统一的"完成"收起栏
struct KeyboardDismissToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                hideKeyboard()
            } label: {
                Text("完成").font(.system(size: 15, weight: .semibold))
            }
        }
    }
}

// MARK: - 脱敏

/// IMEI 脱敏：保留前 6 位与后 2 位，中间以 **** 隐藏
func maskedIMEI(_ s: String) -> String {
    guard s.count >= 10 else { return s }
    return String(s.prefix(6)) + "****" + String(s.suffix(2))
}

/// 本机号码脱敏：保留前 3 位与后 4 位（如 138****8000）
func maskedPhone(_ s: String) -> String {
    guard s.count >= 7 else { return s }
    return String(s.prefix(3)) + "****" + String(s.suffix(4))
}

import SwiftUI

// MARK: - 指令执行面板
//
// 首页快捷入口与「自动化 › 任务」共用同一个执行面板：
// 上半是参数表单，下半是控制台。下发后控制台立刻出现「已发送」，
// 回执到达时再追加一行——等待过程是可见的，而不是转个圈就结束。

struct CommandRunnerSheet: View {
    let command: Command

    @Environment(PanelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var params: [String: String] = [:]
    @State private var didSend = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                intro
                if command.needsForm {
                    form
                }
                consoleBlock
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, 90)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            sendBar
        }
        .background(Color.clear)
        .onAppear {
            for f in command.fields {
                params[f.key] = f.defaultValue
            }
        }
    }

    // MARK: 说明

    private var intro: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            IconBadge(symbol: command.symbol, tint: command.tint, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(command.label)
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                Text(command.summary)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.ink2)
                Text("cmd/\(store.activeDevice?.id ?? "—")")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.pressable)
        }
        .padding(.top, Theme.Space.xxs)
    }

    // MARK: 表单

    private var form: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(spacing: Theme.Space.s) {
                ForEach(command.fields) { field in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(field.label)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.ink3)
                        fieldInput(field)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldInput(_ field: CommandField) -> some View {
        switch field.kind {
        case .text:
            TextField(field.placeholder, text: binding(field.key))
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .keyboardType(field.key.contains("phone") || field.key == "code" ? .default : .default)

        case .multiline:
            TextField(field.placeholder, text: binding(field.key), axis: .vertical)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(3...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

        case .select(let options):
            Menu {
                ForEach(options, id: \.value) { opt in
                    Button(opt.label) { params[field.key] = opt.value }
                }
            } label: {
                HStack {
                    Text(selectedLabel(field, options))
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
        }
    }

    private func selectedLabel(_ field: CommandField, _ options: [FieldOption]) -> String {
        let current = params[field.key] ?? field.defaultValue
        return options.first { $0.value == current }?.label ?? current
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(
            get: { params[key] ?? "" },
            set: { params[key] = $0 }
        )
    }

    // MARK: 控制台

    private var consoleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("控制台")
                    .font(Theme.caption)
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                if store.isSending {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("等待回执")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.warn)
                    }
                }
            }
            .padding(.horizontal, 4)

            ConsoleView(lines: store.console, maxHeight: 168)
        }
    }

    // MARK: 下发

    private var sendBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            Button {
                store.send(command, params: params)
                didSend = true
            } label: {
                HStack(spacing: 7) {
                    if store.isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(store.isSending ? "下发中…" : "下发任务")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(store.isSending ? Theme.ink3 : Theme.accent)
                )
            }
            .buttonStyle(.pressable(scale: 0.98))
            .disabled(store.isSending)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
        .sensoryFeedback(.success, trigger: didSend) { _, new in new }
    }
}

// MARK: - 控制台
//
// 等宽字体 + 前缀区分方向：› 下发，‹ 回执，! 错误。
// 行数上限 60，超出自动裁掉最早的，避免无限增长。

struct ConsoleView: View {
    let lines: [ConsoleLine]
    var maxHeight: CGFloat = 200

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(lines.suffix(60)) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(prefix(line.kind))
                                .font(Theme.mono)
                                .foregroundStyle(tint(line.kind))
                            Text(line.text)
                                .font(Theme.mono)
                                .foregroundStyle(line.kind == .error ? Theme.danger : Theme.ink2)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .id(line.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.hairlineBottom, lineWidth: 0.75)
            }
            .onChange(of: lines.count) {
                if let last = lines.last {
                    withAnimation(Motion.fade) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func prefix(_ kind: ConsoleLine.Kind) -> String {
        switch kind {
        case .sent: return "›"
        case .reply: return "‹"
        case .error: return "!"
        case .info: return "·"
        }
    }

    private func tint(_ kind: ConsoleLine.Kind) -> Color {
        switch kind {
        case .sent: return Theme.accent
        case .reply: return Theme.online
        case .error: return Theme.danger
        case .info: return Theme.ink3
        }
    }
}

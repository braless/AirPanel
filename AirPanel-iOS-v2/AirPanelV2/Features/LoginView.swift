import SwiftUI

// MARK: - 登录
//
// 一个面板类 App 的登录页只有三件事要说清楚：连哪台服务器、我是谁、记住我。
// 所以不做花活——一块玻璃卡，三个字段，一个主按钮。
// 唯一的设计主张是「服务器地址优先」：它是唯一会变的、也是最容易输错的东西，
// 放在第一行，并且给了常用地址的快捷入口。

struct LoginView: View {
    @Environment(PanelStore.self) private var store

    @State private var server = Credentials.server
    @State private var username = Credentials.username
    @State private var password = ""
    @State private var remember = Credentials.rememberPassword

    @FocusState private var focus: Field?
    private enum Field: Hashable { case server, username, password }

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.isEmpty && !password.isEmpty
            && !store.isLoggingIn
    }

    var body: some View {
        ZStack {
            AppBackground(glow: Theme.accent)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    brand
                    card
                    if let error = store.loginError { errorLine(error) }
                    submitButton
                    hint
                }
                .padding(.horizontal, Theme.Space.page)
                // 键盘弹起时把上方留白收紧，否则主按钮会被键盘压住
                .padding(.top, compact ? 8 : 48)
                .padding(.bottom, 60)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .motion(Motion.layout, value: focus)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if password.isEmpty { password = Credentials.savedPassword ?? "" }
            // 地址和账号都填好了就直接把光标放到密码上，少点一次
            focus = server.isEmpty ? .server : (password.isEmpty ? .password : nil)
        }
    }

    // MARK: 品牌

    /// 键盘弹起时收窄品牌区：让主按钮完整露在键盘上方，而不是被切一半
    private var compact: Bool { focus != nil }

    private var brand: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: compact ? 17 : 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 11 : 13, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.accent, Theme.violet],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)

                Text("AirPanel")
                    .font(Theme.display(compact ? 22 : 28))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
            }
            if !compact {
                Text("登录你的服务端，查看设备状态与通信记录")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, compact ? 0 : Theme.Space.xs)
        .motion(Motion.layout, value: compact)
    }

    // MARK: 表单

    private var card: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(spacing: Theme.Space.s) {
                field(title: "服务器地址",
                      placeholder: "192.168.1.9:9527",
                      text: $server,
                      field: .server,
                      keyboard: .URL,
                      contentType: .URL) {
                    if !Credentials.server.isEmpty && server != Credentials.server {
                        Button {
                            server = Credentials.server
                        } label: {
                            Text("用上次")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.pressable)
                    }
                }

                field(title: "账号",
                      placeholder: "admin",
                      text: $username,
                      field: .username,
                      keyboard: .default,
                      contentType: .username)

                field(title: "密码",
                      placeholder: "请输入登录密码",
                      text: $password,
                      field: .password,
                      keyboard: .default,
                      contentType: .password,
                      secure: true)

                RowDivider()

                Toggle(isOn: $remember) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("记住密码")
                            .font(Theme.bodyStrong)
                            .foregroundStyle(Theme.ink)
                        Text("密码存在系统钥匙串，仅本机可用")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .tint(Theme.accent)
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field target: Field,
        keyboard: UIKeyboardType,
        contentType: UITextContentType,
        secure: Bool = false,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.ink3)
                Spacer()
                accessory()
            }
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(Theme.body)
            .foregroundStyle(Theme.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .textContentType(contentType)
            .focused($focus, equals: target)
            .submitLabel(target == .password ? .go : .next)
            .onSubmit {
                switch target {
                case .server: focus = .username
                case .username: focus = .password
                case .password: submit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(focus == target ? Theme.accent.opacity(0.55) : Color.clear,
                                  lineWidth: 1.2)
            }
            .motion(Motion.fade, value: focus == target)
        }
    }

    // MARK: 错误

    private func errorLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 1)
            Text(text)
                .font(Theme.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: 提交

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if store.isLoggingIn {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(store.isLoggingIn ? "正在登录…" : "登录")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(canSubmit ? Color.white : Theme.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(canSubmit ? Theme.accent : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.pressable(scale: 0.98))
        .disabled(!canSubmit)
        .motion(Motion.fade, value: canSubmit)
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("局域网面板填 http:// 地址；公网域名自动走 https")
                    .font(Theme.micro)
            }
            .foregroundStyle(Theme.ink3)

            if !Credentials.username.isEmpty {
                Text("上次登录：\(Credentials.username) · \(Credentials.server)")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.ink3.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 4)
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task {
            await store.login(server: server, username: username, password: password, remember: remember)
        }
    }
}

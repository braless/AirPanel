import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @State private var baseURL = ""
    @State private var username = "admin"
    @State private var password = ""
    @State private var loading = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            background
            VStack(spacing: 18) {
                Spacer(minLength: 40)
                logo
                fields
                loginButton
                Spacer()
                hint
            }
            .padding(.horizontal, 24)
        }
        .toolbar { KeyboardDismissToolbar() }
        .alert("登录失败", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMsg ?? "")
        }
    }

    var background: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.purple.opacity(0.3), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 480).ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.3), .clear],
                           center: .topLeading, startRadius: 10, endRadius: 500).ignoresSafeArea()
        }
    }

    var logo: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.purple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                Text("A").font(.system(size: 40, weight: .heavy)).foregroundColor(Theme.text)
            }
            .shadow(color: Theme.accent.opacity(0.5), radius: 22, y: 10)
            Text("AirPanel").font(.system(size: 26, weight: .heavy))
            Text("远程管理你的 Air724UG 设备")
                .font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.55))
        }
    }

    var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("服务器地址")
            GlassField(placeholder: "http://192.168.1.1:9527",
                       text: $baseURL, keyboard: .URL)
                .onAppear { if baseURL.isEmpty { baseURL = store.baseURLText } }
            label("账号")
            GlassField(placeholder: "admin", text: $username)
            label("密码")
            GlassField(placeholder: "密码", text: $password, secure: true)
        }
    }

    func label(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
    }

    var loginButton: some View {
        Button {
            Task { await login() }
        } label: {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(Theme.text)
                } else {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 16, weight: .semibold))
                }
                Text(loading ? "登录中…" : "登录")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(colors: [Theme.accent.opacity(0.95), Theme.accent.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    var hint: some View {
        Text("连接即表示你拥有该服务器的访问权限")
            .font(.system(size: 11.5)).foregroundColor(Theme.text.opacity(0.35))
    }

    @MainActor
    func login() async {
        guard !baseURL.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMsg = "请填写完整的服务器地址、账号与密码"
            return
        }
        loading = true
        do {
            try await store.login(username: username, password: password, baseURL: baseURL)
        } catch {
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

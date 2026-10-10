import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var batteryMah = "1800"
    @State private var avgCurrentMa = "0"
    @State private var channels: [NotifyChannel] = []
    @State private var showChangePwd = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("通知").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text.opacity(0.7))
                notifyCard
                Text("续航估算").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text.opacity(0.7))
                batteryCard
                Text("外观").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text.opacity(0.7))
                appearanceCard
                Text("账号与服务器").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text.opacity(0.7))
                accountCard
                Text("其他").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text.opacity(0.7))
                otherCard
                PrimaryButton(title: "退出登录", systemImage: "rectangle.portrait.and.arrow.right", color: Theme.red) {
                    Task { await store.logout() }
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("设置")
        .toolbar { KeyboardDismissToolbar() }
        .task { await loadChannels() }
        .onAppear(perform: prefillBattery)
        .sheet(isPresented: $showChangePwd) { ChangePasswordView() }
        .overlay {
            if let t = toast {
                VStack { Text(t).font(.system(size: 13)).foregroundColor(Theme.text)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule()) }
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 40)
            }
        }
    }

    var appearanceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("主题").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                Picker("外观", selection: Binding(get: { store.appearance }, set: { store.setAppearance($0) })) {
                    ForEach(Appearance.allCases) { a in
                        Text(a.label).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 13))
            }
            .padding(14)
        }
    }

    var notifyCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                ForEach(channels) { ch in
                    HStack {
                        Image(systemName: ch.channel == "bark" ? "bell.fill" : "bell")
                            .font(.system(size: 14)).foregroundColor(Theme.text)
                            .frame(width: 30, height: 30).background(ch.enabled ? Theme.accent.opacity(0.25) : Theme.fill, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.channel.uppercased()).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                            Text(ch.enabled ? "已启用" : "未启用").font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.45))
                        }
                        Spacer()
                        StatusPill(text: ch.enabled ? "开" : "关", color: ch.enabled ? Theme.green : .gray)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    var batteryCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("电池容量 (mAh)").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        GlassField(placeholder: "1800", text: $batteryMah, keyboard: .numberPad)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("平均电流 (mA)").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        GlassField(placeholder: "0（自动）", text: $avgCurrentMa, keyboard: .numberPad)
                    }
                }
                PrimaryButton(title: "保存估算配置", systemImage: "checkmark") {
                    Task { await saveBattery() }
                }
                Text("当前电流按功耗模型估算；填平均电流可覆盖").font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
            }
        }
    }

    var accountCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                GlassRow(icon: "person.crop.circle", color: Theme.accent, title: "账号", subtitle: "登录用户名", trailing: "admin")
                Divider().overlay(Theme.stroke)
                GlassRow(icon: "server.rack", color: Theme.teal, title: "服务器", subtitle: "API 地址", trailing: store.baseURLText)
                Divider().overlay(Theme.stroke)
                Button {
                    showChangePwd = true
                } label: {
                    HStack {
                        Image(systemName: "key.fill").font(.system(size: 15)).foregroundColor(Theme.text)
                            .frame(width: 34, height: 34).background(Theme.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                        Text("修改密码").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.text.opacity(0.4))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var otherCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                NavigationLink {
                    BlockRulesView()
                } label: {
                    HStack {
                        Image(systemName: "shield.fill").font(.system(size: 15)).foregroundColor(Theme.text)
                            .frame(width: 34, height: 34).background(Theme.purple.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                        Text("屏蔽配置").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.text.opacity(0.4))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.stroke)
                GlassRow(icon: "info.circle", color: Theme.purple, title: "关于", subtitle: "AirPanel iOS 客户端", trailing: "v1.0")
            }
        }
    }

    func prefillBattery() {
        if batteryMah == "1800" && avgCurrentMa == "0" {
            Task {
                let s = try? await store.api.settings()
                if let m = s?["battery_mah"] { batteryMah = "\(m)" }
                if let a = s?["avg_current_ma"] { avgCurrentMa = "\(a)" }
            }
        }
    }

    @MainActor
    func loadChannels() async {
        channels = (try? await store.api.notifyChannels()) ?? []
    }
    @MainActor
    func testNotify() async {
        do { try await store.api.testNotify(); toast = "已发送测试通知" }
        catch { toast = (error as? APIError)?.message ?? "发送失败" }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = nil
        }
    }
    @MainActor
    func saveBattery() async {
        do {
            try await store.api.saveOverviewConfig(batteryMah: Int(batteryMah) ?? 1800,
                                                   avgCurrentMa: Int(avgCurrentMa) ?? 0)
            toast = "已保存"
            Task { try? await Task.sleep(nanoseconds: 2_000_000_000); toast = nil }
        } catch {
            toast = (error as? APIError)?.message ?? "保存失败"
        }
    }
}

// MARK: - 修改密码

struct ChangePasswordView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var old = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("旧密码").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        GlassField(placeholder: "旧密码", text: $old, secure: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("新密码").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        GlassField(placeholder: "新密码", text: $new, secure: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("确认新密码").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        GlassField(placeholder: "确认新密码", text: $confirm, secure: true)
                    }
                    PrimaryButton(title: saving ? "保存中…" : "保存", systemImage: "checkmark") {
                        Task { await save() }
                    }.disabled(saving)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KeyboardDismissToolbar(); ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            } }
            .alert("提示", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("好") {}
            } message: { Text(errorMsg ?? "") }
        }
        .presentationDetents([.medium])
    }

    @MainActor
    func save() async {
        guard !old.isEmpty, !new.isEmpty else { errorMsg = "请填写密码"; return }
        guard new == confirm else { errorMsg = "两次新密码不一致"; return }
        saving = true
        do {
            try await store.api.changeUserInfo(oldPassword: old, newPassword: new)
            errorMsg = "密码已更新，请重新登录"
            dismiss()
        } catch {
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

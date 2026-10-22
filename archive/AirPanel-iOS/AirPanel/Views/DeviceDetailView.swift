import SwiftUI

struct DeviceDetailView: View {
    let device: Device
    @EnvironmentObject var store: AppStore

    @State private var activeSheet: SheetKind?
    @State private var resultMsg: String?
    @State private var confirmDelete = false
    @State private var running = false

    enum SheetKind: Identifiable {
        case dial, sms, writeConfig, gpio
        var id: Int {
            switch self {
            case .dial: return 0
            case .sms: return 1
            case .writeConfig: return 2
            case .gpio: return 3
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                infoCard
                quickActions
                dangerZone
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(device.name.isEmpty ? maskedIMEI(device.imei) : device.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            TaskFormSheet(kind: sheet, device: device)
        }
        .alert("任务结果", isPresented: Binding(get: { resultMsg != nil }, set: { if !$0 { resultMsg = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(resultMsg ?? "") }
        .confirmationDialog("确认删除设备 \(maskedIMEI(device.imei))？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await removeDevice() } }
            Button("取消", role: .cancel) {}
        }
        .overlay {
            if running { LoadingView(text: "执行中…") }
        }
    }

    var infoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("设备信息").font(.system(size: 14, weight: .bold))
                    Spacer()
                    StatusPill(text: device.connected ? "在线" : "离线", color: device.connected ? Theme.green : .gray)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    infoCell("IMEI", maskedIMEI(device.imei))
                    infoCell("号码", maskedPhone(device.phone))
                    infoCell("备注", device.name.isEmpty ? "-" : device.name)
                    infoCell("首次接入", Fmt.time(device.firstSeen))
                    infoCell("最后在线", Fmt.time(device.lastSeen))
                    infoCell("状态", device.connected ? "在线" : "离线")
                }
            }
        }
    }

    func infoCell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.45))
            Text(v).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text).lineLimit(1)
        }
    }

    var quickActions: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("快捷操作").font(.system(size: 14, weight: .bold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                    actionCell("箭头.clockwise", Theme.accent, "重启设备") { run("reboot", [:]) }
                    actionCell("phone.fill", Theme.green, "拨打电话") { activeSheet = .dial }
                    actionCell("message.fill", Theme.purple, "发送短信") { activeSheet = .sms }
                    actionCell("thermometer.medium", Theme.orange, "查询温度") { run("get_temperature", [:]) }
                    actionCell("doc.text", Theme.teal, "读取配置") { run("get_config", [:]) }
                    actionCell("pencil", Theme.purple, "写入配置") { activeSheet = .writeConfig }
                    actionCell("slider.horizontal.3", Theme.teal, "GPIO 控制") { activeSheet = .gpio }
                    actionCell("shield", Theme.accent, "屏蔽设置") {
                        store.selectedIMEI = device.imei
                    }
                }
            }
        }
    }

    func actionCell(_ icon: String, _ color: Color, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(Theme.text)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var dangerZone: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "删除设备", systemImage: "trash", color: Theme.red) {
                confirmDelete = true
            }
        }
    }

    @MainActor
    func run(_ task: String, _ extra: [String: Any]) {
        running = true
        Task {
            do {
                let r = try await store.api.executeTask(imei: device.imei, task: task, extra: extra)
                resultMsg = r.result?.isEmpty == false ? r.result! : (r.message ?? "已下发")
            } catch {
                resultMsg = (error as? APIError)?.message ?? error.localizedDescription
            }
            running = false
        }
    }

    @MainActor
    func removeDevice() async {
        do {
            try await store.api.deleteDevice(imei: device.imei)
            await store.refreshDevices()
        } catch {
            resultMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

// MARK: - 任务参数表单

struct TaskFormSheet: View {
    let kind: DeviceDetailView.SheetKind
    let device: Device
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var content = ""
    @State private var config = ""
    @State private var pin = "1"
    @State private var value = "0"
    @State private var sending = false
    @State private var resultMsg: String?

    var title: String {
        switch kind {
        case .dial: return "拨打电话"
        case .sms: return "发送短信"
        case .writeConfig: return "写入配置"
        case .gpio: return "GPIO 控制"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    switch kind {
                    case .dial:
                        field("手机号", $number, .phonePad)
                    case .sms:
                        field("手机号", $number, .phonePad)
                        Text("短信内容").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
                        TextEditor(text: $content)
                            .frame(minHeight: 90)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
                    case .writeConfig:
                        Text("配置内容（Lua 文本）").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
                        TextEditor(text: $config)
                            .frame(minHeight: 120)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
                    case .gpio:
                        field("引脚", $pin, .numberPad)
                        field("电平值 (0/1)", $value, .numberPad)
                    }
                    PrimaryButton(title: sending ? "发送中…" : "执行") {
                        Task { await send() }
                    }
                    .disabled(sending)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KeyboardDismissToolbar(); ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            } }
            .alert("结果", isPresented: Binding(get: { resultMsg != nil }, set: { if !$0 { resultMsg = nil } })) {
                Button("好") { dismiss() }
            } message: { Text(resultMsg ?? "") }
        }
        .presentationDetents([.medium, .large])
    }

    func field(_ label: String, _ binding: Binding<String>, _ keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
            GlassField(placeholder: label, text: binding, keyboard: keyboard)
        }
    }

    @MainActor
    func send() async {
        sending = true
        var extra: [String: Any]
        var task: String
        switch kind {
        case .dial:
            guard !number.isEmpty else { resultMsg = "请输入手机号"; sending = false; return }
            task = "dial_call"; extra = ["phone": number]
        case .sms:
            guard !number.isEmpty, !content.isEmpty else { resultMsg = "请填写号码与内容"; sending = false; return }
            task = "send_sms"; extra = ["rcv_phone": number, "content": content]
        case .writeConfig:
            guard !config.isEmpty else { resultMsg = "请输入配置"; sending = false; return }
            task = "set_config"; extra = ["configText": config]
        case .gpio:
            task = "set_gpio"; extra = ["pin": pin, "level": value]
        }
        do {
            let r = try await store.api.executeTask(imei: device.imei, task: task, extra: extra)
            resultMsg = r.result?.isEmpty == false ? r.result! : (r.message ?? "已下发")
        } catch {
            resultMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        sending = false
    }
}

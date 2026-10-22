import SwiftUI

struct TaskHubView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case command = "指挥台", schedule = "定时任务"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .command

    var body: some View {
        VStack(spacing: 12) {
            GlassSegmented(selection: $mode, items: Mode.allCases.map { ($0, $0.rawValue) })
                .padding(.horizontal, 16).padding(.top, 6)
            switch mode {
            case .command: TaskCommandView()
            case .schedule: SchedulesView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("任务")
    }
}

// MARK: - 任务类型定义

struct TaskType: Identifiable, Hashable {
    let id: String          // task 值，与服务端一致
    let title: String
    let desc: String
    let icon: String
    let color: Color
    let needsParams: Bool

    static let all: [TaskType] = [
        TaskType(id: "send_sms", title: "发送短信", desc: "设备代发短信", icon: "message.fill", color: Theme.accent, needsParams: true),
        TaskType(id: "dial_call", title: "拨打电话", desc: "SIM 卡向外拨号", icon: "phone.fill", color: Theme.green, needsParams: true),
        TaskType(id: "get_temperature", title: "查询温度", desc: "读取模组温度", icon: "thermometer.medium", color: Theme.orange, needsParams: false),
        TaskType(id: "get_status", title: "查询状态", desc: "模组状态", icon: "gauge", color: Theme.teal, needsParams: false),
        TaskType(id: "get_config", title: "读取配置", desc: "nvm_para.lua", icon: "doc.text", color: Theme.purple, needsParams: false),
        TaskType(id: "set_config", title: "写入配置", desc: "下发配置文本", icon: "pencil", color: Theme.purple, needsParams: true),
        TaskType(id: "set_gpio", title: "GPIO 控制", desc: "设置引脚电平", icon: "slider.horizontal.3", color: Theme.teal, needsParams: true),
        TaskType(id: "reboot", title: "重启设备", desc: "软重启模组", icon: "arrow.clockwise", color: Theme.red, needsParams: false),
        TaskType(id: "__custom__", title: "自定义命令", desc: "高级 / USSD", icon: "terminal", color: Theme.orange, needsParams: true),
    ]
}

/// 任务类型 ID → 中文显示名（找不到时原样返回）
func taskDisplayName(_ id: String) -> String {
    TaskType.all.first(where: { $0.id == id })?.title ?? id
}

// MARK: - 任务指挥台

struct TaskCommandView: View {
    @EnvironmentObject var store: AppStore
    @State private var taskType: TaskType = TaskType.all[0]
    @State private var number = ""
    @State private var content = ""
    @State private var config = ""
    @State private var pin = "1"
    @State private var value = "0"
    @State private var command = ""
    @State private var extraJSON = ""
    @State private var resultMsg: String?
    @State private var sending = false
    @State private var tasks: [TaskRecord] = []
    @State private var taskPage = 1
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                deviceSelect
                Text("任务类型").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text.opacity(0.7))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                    ForEach(TaskType.all) { t in
                        taskCell(t)
                    }
                }
                if taskType.needsParams {
                    paramsCard
                }
                PrimaryButton(title: sending ? "下发中…" : "下发任务", systemImage: "paperplane.fill") {
                    Task { await send() }
                }
                .disabled(sending)

                Text("任务记录").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text.opacity(0.7))
                records
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: applyPendingTask)
        .task { await loadTasks() }
        .toolbar { KeyboardDismissToolbar() }
        .refreshable { await loadTasks() }
        .alert("任务结果", isPresented: Binding(get: { resultMsg != nil }, set: { if !$0 { resultMsg = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(resultMsg ?? "") }
        .overlay { if loading { LoadingView(text: "加载任务…") } }
    }

    var deviceSelect: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("目标设备").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                Menu {
                    ForEach(store.devices) { d in
                        Button(d.name.isEmpty ? maskedIMEI(d.imei) : "\(d.name) · \(maskedIMEI(d.imei))") {
                            store.select(imei: d.imei)
                        }
                    }
                } label: {
                    HStack {
                        Text(store.selectedDevice?.name.isEmpty == false ? store.selectedDevice!.name : (store.selectedDevice.map { maskedIMEI($0.imei) } ?? "选择设备"))
                            .font(.system(size: 14)).foregroundColor(Theme.text)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.text.opacity(0.5))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    func taskCell(_ t: TaskType) -> some View {
        Button {
            taskType = t
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: t.icon).font(.system(size: 15)).foregroundColor(Theme.text)
                    .frame(width: 30, height: 30)
                    .background(t.color.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(t.title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                Text(t.desc).font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.45)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(taskType.id == t.id ? t.color.opacity(0.22) : Theme.fill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(taskType.id == t.id ? t.color.opacity(0.6) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var paramsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("参数").font(.system(size: 13, weight: .bold))
                switch taskType.id {
                case "send_sms":
                    field("手机号", $number, .phonePad)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("短信内容").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        TextEditor(text: $content).frame(minHeight: 70).padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
                    }
                case "dial_call":
                    field("手机号", $number, .phonePad)
                case "set_config":
                    VStack(alignment: .leading, spacing: 5) {
                        Text("配置内容").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        TextEditor(text: $config).frame(minHeight: 100).font(.system(size: 12, design: .monospaced)).padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
                    }
                case "set_gpio":
                    field("引脚", $pin, .numberPad)
                    field("电平值 (0/1)", $value, .numberPad)
                default: // custom
                    field("命令名", $command, .default)
                    field("附加参数 JSON", $extraJSON, .default)
                }
            }
        }
    }

    func field(_ label: String, _ binding: Binding<String>, _ keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
            GlassField(placeholder: label, text: binding, keyboard: keyboard)
        }
    }

    var records: some View {
        VStack(spacing: 0) {
            if tasks.isEmpty {
                EmptyState(text: "暂无任务记录")
            } else {
                ForEach(tasks) { t in
                    taskRow(t)
                    if t.id != tasks.last?.id { Divider().overlay(Theme.stroke) }
                }
            }
        }
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    func taskRow(_ t: TaskRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon(t.status)).font(.system(size: 14)).foregroundColor(statusColor(t.status))
                .frame(width: 30, height: 30).background(statusColor(t.status).opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(t.task).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    Spacer()
                    Text(Fmt.time(t.createdAt)).font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
                }
                if let r = t.result, !r.isEmpty {
                    Text(r).font(.system(size: 11.5)).foregroundColor(Theme.text.opacity(0.6)).lineLimit(3)
                }
                if let e = t.error, !e.isEmpty {
                    Text(e).font(.system(size: 11.5)).foregroundColor(Theme.red).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    func statusIcon(_ s: String) -> String {
        s == "success" ? "checkmark.circle.fill" : (s == "failed" || s == "error" ? "xmark.circle.fill" : "clock.fill")
    }
    func statusColor(_ s: String) -> Color {
        s == "success" ? Theme.green : (s == "failed" || s == "error" ? Theme.red : Theme.orange)
    }

    /// 小组件快捷命令预选任务类型
    func applyPendingTask() {
        guard let t = store.pendingTask, let tt = TaskType.all.first(where: { $0.id == t }) else { return }
        taskType = tt
        store.pendingTask = nil
    }

    @MainActor
    func send() async {
        guard let imei = store.selectedDevice?.imei else { resultMsg = "请选择设备"; return }
        var extra: [String: Any] = [:]
        switch taskType.id {
        case "send_sms":
            guard !number.isEmpty, !content.isEmpty else { resultMsg = "请填写号码与内容"; return }
            extra = ["rcv_phone": number, "content": content]
        case "dial_call":
            guard !number.isEmpty else { resultMsg = "请填写手机号"; return }
            extra = ["phone": number]
        case "set_config":
            guard !config.isEmpty else { resultMsg = "请填写配置"; return }
            extra = ["configText": config]
        case "set_gpio":
            extra = ["pin": pin, "level": value]
        case "__custom__":
            guard !command.isEmpty else { resultMsg = "请填写命令名"; return }
            let task = command.trimmingCharacters(in: .whitespaces)
            if !extraJSON.trimmingCharacters(in: .whitespaces).isEmpty,
               let data = extraJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                extra = obj
            } else {
                extra = [:]
            }
            do {
                let r = try await store.api.executeTask(imei: imei, task: task, extra: extra)
                resultMsg = r.result?.isEmpty == false ? r.result! : (r.message ?? "已下发")
            } catch {
                resultMsg = (error as? APIError)?.message ?? error.localizedDescription
            }
            await loadTasks()
            return
        default:
            break
        }
        sending = true
        do {
            let r = try await store.api.executeTask(imei: imei, task: taskType.id, extra: extra)
            resultMsg = r.result?.isEmpty == false ? r.result! : (r.message ?? "已下发")
        } catch {
            resultMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        sending = false
        await loadTasks()
    }

    @MainActor
    func loadTasks() async {
        do {
            let r = try await store.api.tasks(page: taskPage)
            tasks = r.tasks
        } catch {
            // 静默
        }
    }
}

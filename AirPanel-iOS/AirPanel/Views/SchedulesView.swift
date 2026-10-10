import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject var store: AppStore
    @State private var schedules: [Schedule] = []
    @State private var total = 0
    @State private var page = 1
    @State private var loading = false
    @State private var showForm = false
    @State private var editing: Schedule?
    @State private var errorMsg: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                list
                PrimaryButton(title: "新建定时任务", systemImage: "plus") {
                    editing = nil
                    showForm = true
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showForm) {
            ScheduleFormView(existing: editing)
        }
        .overlay { if loading { LoadingView(text: "加载定时任务…") } }
        .alert("加载失败", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMsg ?? "") }
    }

    var header: some View {
        HStack {
            Text("共 \(total) 个任务 · 第 \(page) 页")
                .font(.system(size: 12)).foregroundColor(Theme.text.opacity(0.5))
            Spacer()
            Button { Task { await load() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 14)).foregroundColor(Theme.text.opacity(0.7))
            }
        }
    }

    var list: some View {
        VStack(spacing: 0) {
            if schedules.isEmpty && !loading {
                EmptyState(text: "暂无定时任务")
            } else {
                ForEach(schedules) { s in
                    scheduleRow(s)
                    if s.id != schedules.last?.id { Divider().overlay(Theme.stroke) }
                }
            }
        }
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    func scheduleRow(_ s: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                Toggle("", isOn: Binding(get: { s.enabled }, set: { new in Task { await toggle(s.id, new) } }))
                    .labelsHidden().tint(Theme.green)
            }
            HStack(spacing: 5) {
                Text(taskDisplayName(s.task))
                Text("·").opacity(0.3)
                Text(specText(s))
            }.font(.system(size: 11.5)).foregroundColor(Theme.text.opacity(0.5))
            if let dn = s.deviceName, !dn.isEmpty {
                Text("设备：\(dn)").font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
            }
            HStack(spacing: 10) {
                Button { Task { await run(s.id) } } label: {
                    Label("立即执行", systemImage: "play.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.text).padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.25), in: Capsule())
                }.buttonStyle(.plain)
                Button { editing = s; showForm = true } label: {
                    Label("编辑", systemImage: "pencil").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.text).padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Theme.fill, in: Capsule())
                }.buttonStyle(.plain)
                Button { Task { await delete(s.id) } } label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundColor(Theme.red)
                        .padding(7).background(Theme.fill, in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    func specText(_ s: Schedule) -> String {
        guard let sp = s.spec, let type = sp.type else { return "—" }
        let hm = "\(sp.hour ?? 0) 点 \(sp.minute ?? 0) 分"
        switch type {
        case "daily": return "每天 \(hm)"
        case "hourly": return "每小时"
        case "weekly":
            let d = sp.weekday ?? 0
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return "每周\(d >= 0 && d < 7 ? names[d] : "?") \(hm)"
        case "monthly": return "每月 \(sp.day ?? 1) 日 \(hm)"
        case "interval": return "每 \(sp.n ?? 0) \(sp.unit ?? "分钟")"
        default: return type
        }
    }

    @MainActor
    func load() async {
        loading = true
        do {
            let r = try await store.api.schedules(page: page)
            schedules = r.schedules; total = r.total
            errorMsg = nil
        } catch {
            if isCancelError(error) { loading = false; return }
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    @MainActor
    func toggle(_ id: Int64, _ on: Bool) async {
        try? await store.api.toggleSchedule(id: id, enabled: on)
        await load()
    }
    @MainActor
    func delete(_ id: Int64) async {
        try? await store.api.deleteSchedule(id: id)
        await load()
    }
    @MainActor
    func run(_ id: Int64) async {
        try? await store.api.runSchedule(id: id)
    }
}

// MARK: - 定时任务表单

struct ScheduleFormView: View {
    let existing: Schedule?
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var taskID = "send_sms"
    @State private var number = ""
    @State private var content = ""
    @State private var config = ""
    @State private var pin = "1"
    @State private var value = "0"
    @State private var command = ""
    @State private var extraJSON = ""
    @State private var specType = "daily"
    @State private var hour = 8
    @State private var weekday = 1
    @State private var day = 1
    @State private var minute = 10
    @State private var enabled = true
    @State private var saving = false
    @State private var errorMsg: String?

    let specTypes: [(String, String)] = [("daily", "每天"), ("hourly", "每小时"),
                                         ("weekly", "每周"), ("monthly", "每月")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("任务名称", $name)
                    devicePicker
                    taskPicker
                    paramsSection
                    specSection
                    Toggle("启用", isOn: $enabled).tint(Theme.green)
                        .padding(.vertical, 6)
                    PrimaryButton(title: saving ? "保存中…" : "保存", systemImage: "checkmark") {
                        Task { await save() }
                    }.disabled(saving)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(existing == nil ? "新建定时任务" : "编辑定时任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KeyboardDismissToolbar(); ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            } }
            .onAppear(perform: prefill)
            .alert("错误", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("好") {}
            } message: { Text(errorMsg ?? "") }
        }
        .presentationDetents([.large])
    }

    func prefill() {
        guard let e = existing else { return }
        name = e.name
        taskID = e.task
        enabled = e.enabled
        if let sp = e.spec {
            if let t = sp.type { specType = t }
            if let h = sp.hour { hour = h }
            if let w = sp.weekday { weekday = w }
            if let d = sp.day { day = d }
            if let m = sp.minute { minute = m }
        }
        if let p = e.params?.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: p) as? [String: Any] {
            number = obj["rcv_phone"] as? String ?? obj["phone"] as? String ?? ""
            content = obj["content"] as? String ?? ""
            config = obj["configText"] as? String ?? ""
            pin = obj["pin"] as? String ?? "1"
            value = obj["level"] as? String ?? "0"
            command = obj["command"] as? String ?? ""
        }
    }

    var devicePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("目标设备").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
            Menu {
                ForEach(store.devices) { d in
                    Button(d.name.isEmpty ? maskedIMEI(d.imei) : "\(d.name) · \(maskedIMEI(d.imei))") { store.select(imei: d.imei) }
                }
            } label: {
                HStack {
                    Text(store.selectedDevice?.name.isEmpty == false ? store.selectedDevice!.name : (store.selectedDevice.map { maskedIMEI($0.imei) } ?? "选择设备"))
                        .font(.system(size: 14)).foregroundColor(Theme.text)
                    Spacer(); Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.text.opacity(0.5))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    var taskPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("任务类型").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
            Menu {
                ForEach(TaskType.all) { t in Button(t.title) { taskID = t.id } }
            } label: {
                HStack {
                    Text(TaskType.all.first { $0.id == taskID }?.title ?? taskID).font(.system(size: 14)).foregroundColor(Theme.text)
                    Spacer(); Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.text.opacity(0.5))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    var paramsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("参数").font(.system(size: 13, weight: .bold))
                switch taskID {
                case "send_sms":
                    field("手机号", $number, .phonePad)
                    field("短信内容", $content, .default)
                case "dial_call":
                    field("手机号", $number, .phonePad)
                case "set_config":
                    field("配置内容", $config, .default)
                case "set_gpio":
                    field("引脚", $pin, .numberPad)
                    field("电平值", $value, .numberPad)
                case "__custom__":
                    field("命令名", $command, .default)
                    field("附加参数 JSON", $extraJSON, .default)
                default:
                    EmptyView()
                }
            }
        }
    }

    var specSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("执行周期").font(.system(size: 13, weight: .bold))
                Picker("周期", selection: $specType) {
                    ForEach(specTypes, id: \.0) { t in Text(t.1).tag(t.0) }
                }
                .pickerStyle(.segmented)
                switch specType {
                case "daily", "monthly":
                    HStack(spacing: 12) {
                        stepperField("小时", $hour, 0...23)
                        if specType == "monthly" { stepperField("日期", $day, 1...28) }
                    }
                case "weekly":
                    HStack(spacing: 12) {
                        Picker("星期", selection: $weekday) {
                            ForEach(Array(["日","一","二","三","四","五","六"].enumerated()), id: \.offset) { i, d in Text("周\(d)").tag(i) }
                        }
                        stepperField("小时", $hour, 0...23)
                    }
                case "hourly":
                    EmptyView()
                default:
                    EmptyView()
                }
            }
        }
    }

    func stepperField(_ label: String, _ binding: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
            Stepper("\(binding.wrappedValue)", value: binding, in: range)
                .font(.system(size: 14))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
    }

    func field(_ label: String, _ binding: Binding<String>, _ keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
            GlassField(placeholder: label, text: binding, keyboard: keyboard)
        }
    }

    @MainActor
    func save() async {
        guard !name.isEmpty else { errorMsg = "请输入任务名称"; return }
        guard let imei = store.selectedDevice?.imei else { errorMsg = "请选择设备"; return }
        var params: [String: Any] = [:]
        switch taskID {
        case "send_sms": params = ["rcv_phone": number, "content": content]
        case "dial_call": params = ["phone": number]
        case "set_config": params = ["configText": config]
        case "set_gpio": params = ["pin": pin, "level": value]
        case "__custom__":
            if let data = extraJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                params = obj
            }
        default: break
        }
        var spec: [String: Any] = ["type": specType]
        switch specType {
        case "daily": spec["hour"] = hour
        case "weekly": spec["weekday"] = weekday; spec["hour"] = hour
        case "monthly": spec["day"] = day; spec["hour"] = hour
        default: break
        }
        saving = true
        do {
            if let existing {
                try await store.api.updateSchedule(id: existing.id, name: name, imei: imei,
                                                   task: taskID, params: params, spec: spec, enabled: enabled)
            } else {
                try await store.api.addSchedule(name: name, imei: imei, task: taskID,
                                                params: params, spec: spec, enabled: enabled)
            }
            dismiss()
        } catch {
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

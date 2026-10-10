import SwiftUI

struct BlockRulesView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case keyword = "关键字", number = "号码"
        var id: String { rawValue }
    }

    @EnvironmentObject var store: AppStore
    @State private var kind: Kind = .keyword
    @State private var rules: [BlockRule] = []
    @State private var search = ""
    @State private var loading = false
    @State private var showAdd = false
    @State private var errorMsg: String?

    var filtered: [BlockRule] {
        guard !search.isEmpty else { return rules }
        return rules.filter { $0.value.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GlassSegmented(selection: $kind, items: Kind.allCases.map { ($0, $0.rawValue) })
                searchBar
                list
                PrimaryButton(title: "添加规则", systemImage: "plus") { showAdd = true }
                Button {
                    Task { await reset() }
                } label: {
                    Label("恢复内置默认", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("屏蔽配置")
        .toolbar { KeyboardDismissToolbar() }
        .task(id: kind) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) { AddRuleForm(kind: kind) }
        .overlay { if loading { LoadingView(text: "加载规则…") } }
        .alert("提示", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("好") {}
        } message: { Text(errorMsg ?? "") }
    }

    var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.4))
            TextField("搜索规则…", text: $search)
                .font(.system(size: 14)).foregroundColor(Theme.text)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
    }

    var list: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty && !loading {
                EmptyState(text: "暂无\(kind.rawValue)规则")
            } else {
                ForEach(filtered) { r in
                    ruleRow(r)
                    if r.id != filtered.last?.id { Divider().overlay(Theme.stroke) }
                }
            }
        }
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    func ruleRow(_ r: BlockRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.ruleType == "keyword" ? "text.quote" : "phone.fill")
                .font(.system(size: 14)).foregroundColor(Theme.text)
                .frame(width: 32, height: 32).background(r.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.value).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                HStack(spacing: 6) {
                    Text(matchText(r.matchMode)).font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.5))
                    if r.source == "builtin" {
                        StatusPill(text: "内置", color: Theme.orange)
                    } else {
                        StatusPill(text: "自定义", color: Theme.accent)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { r.enabled == 1 }, set: { new in Task { await toggle(r, new) } }))
                .labelsHidden().tint(Theme.green)
            Button { Task { await delete(r.id) } } label: {
                Image(systemName: "trash").font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    func matchText(_ m: String) -> String {
        m == "contains" ? "包含" : (m == "prefix" ? "前缀" : "精确")
    }

    @MainActor
    func load() async {
        loading = true
        do {
            let r = try await store.api.blockRules(type: kind == .keyword ? "keyword" : "number")
            rules = r.rules
        } catch {
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    @MainActor
    func toggle(_ r: BlockRule, _ on: Bool) async {
        try? await store.api.updateBlockRule(id: r.id, value: r.value, matchMode: r.matchMode,
                                             enabled: on ? 1 : 0, note: r.note ?? "")
        await load()
    }
    @MainActor
    func delete(_ id: Int64) async {
        try? await store.api.deleteBlockRule(id: id)
        await load()
    }
    @MainActor
    func reset() async {
        try? await store.api.resetBlockRules()
        await load()
    }
}

extension BlockRule {
    var color: Color {
        ruleType == "keyword" ? Theme.purple : Theme.teal
    }
}

// MARK: - 添加规则

struct AddRuleForm: View {
    let kind: BlockRulesView.Kind
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var matchMode = "contains"
    @State private var note = ""
    @State private var saving = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(kind == .keyword ? "关键字" : "号码").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        GlassField(placeholder: kind == .keyword ? "如：中奖、退订" : "如：1068（支持前缀）", text: $value)
                    }
                    if kind == .number {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("匹配方式").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                            Picker("匹配", selection: $matchMode) {
                                Text("前缀").tag("prefix")
                                Text("精确").tag("exact")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("备注（可选）").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text.opacity(0.5))
                        GlassField(placeholder: "备注", text: $note)
                    }
                    PrimaryButton(title: saving ? "保存中…" : "保存", systemImage: "checkmark") {
                        Task { await save() }
                    }.disabled(saving)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("添加\(kind.rawValue)规则")
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
        guard !value.isEmpty else { errorMsg = "请输入内容"; return }
        let ruleType = kind == .keyword ? "keyword" : "number"
        let mode = kind == .number ? matchMode : "contains"
        saving = true
        do {
            try await store.api.addBlockRule(ruleType: ruleType, value: value, matchMode: mode, note: note)
            dismiss()
        } catch {
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

import SwiftUI

struct RecordsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case calls = "通话", sms = "短信"
        var id: String { rawValue }
    }

    enum RangeFilter: String, CaseIterable, Identifiable {
        case all = "全部", today = "今天", week = "近7天"
        var id: String { rawValue }
    }

    @EnvironmentObject var store: AppStore
    @State private var tab: Tab = .calls
    @State private var range: RangeFilter = .all
    @State private var calls: [CallRecord] = []
    @State private var sms: [SmsRecord] = []
    @State private var callPage = 1
    @State private var smsPage = 1
    @State private var callTotal = 0
    @State private var smsTotal = 0
    @State private var state: LoadState = .idle
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GlassSegmented(selection: $tab, items: Tab.allCases.map { ($0, $0.rawValue) })
                filterBar
                list
                footer
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("记录")
        .task(id: tab) { await reload() }
        .onChange(of: range) { Task { await reload() } }
        .refreshable { await reload() }
        .overlay {
            switch state {
            case .loading: LoadingView(text: "加载记录…")
            case .failed(let msg): ErrorView(message: msg) { Task { await reload() } }
            case .idle, .loaded: EmptyView()
            }
        }
        .confirmationDialog("确认清理 \(tab == .calls ? "通话" : "短信")记录？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清理全部", role: .destructive) { Task { await clearAll() } }
            Button("取消", role: .cancel) {}
        }
    }

    var filterBar: some View {
        HStack {
            Menu {
                ForEach(RangeFilter.allCases) { r in
                    Button(r.rawValue) { range = r }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 12))
                    Text(range.rawValue).font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(Theme.text)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Theme.fill, in: Capsule())
            }
            Spacer()
            Button {
                confirmClear = true
            } label: {
                Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.red)
                    .padding(8)
                    .background(Theme.fill, in: Circle())
            }
        }
    }

    @ViewBuilder
    var list: some View {
        if tab == .calls {
            if calls.isEmpty && state == .loaded {
                EmptyState(text: "暂无通话记录")
            } else {
                VStack(spacing: 0) {
                    ForEach(calls) { call in
                        callRow(call)
                        if call.id != calls.last?.id { Divider().overlay(Theme.stroke).padding(.leading, 60) }
                    }
                }
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }
        } else {
            if sms.isEmpty && state == .loaded {
                EmptyState(text: "暂无短信记录")
            } else {
                VStack(spacing: 0) {
                    ForEach(sms) { s in
                        smsRow(s)
                        if s.id != sms.last?.id { Divider().overlay(Theme.stroke).padding(.leading, 60) }
                    }
                }
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
    }

    var footer: some View {
        let total = tab == .calls ? callTotal : smsTotal
        let page = tab == .calls ? callPage : smsPage
        return VStack(spacing: 8) {
            if (page * 10) < total {
                Button {
                    Task { await loadMore() }
                } label: {
                    Text("加载更多").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text).padding(.vertical, 10).frame(maxWidth: .infinity)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Text("共 \(total) 条 · 第 \(page) 页")
                .font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
        }
    }

    // MARK: 通话行

    func callRow(_ c: CallRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(directionColor(c.direction).opacity(0.25)).frame(width: 34, height: 34)
                Image(systemName: c.direction == "outgoing" ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.number).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                    if c.spam == 1 { StatusPill(text: "垃圾", color: Theme.red) }
                }
                HStack(spacing: 5) {
                    Text("\(c.direction == "outgoing" ? "去电" : "来电") · \(c.status)")
                    Text("·").opacity(0.3)
                    Text(Fmt.time(c.startedAt))
                }.font(.system(size: 11.5)).foregroundColor(Theme.text.opacity(0.5))
                if c.duration > 0 {
                    Text("通话 \(Fmt.duration(c.duration))").font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
                }
                if c.spam == 1, let rule = c.spamRule, !rule.isEmpty {
                    Text("命中：\(rule)").font(.system(size: 11)).foregroundColor(Theme.red).lineLimit(1)
                }
                if !c.notifyStatus.isEmpty {
                    Text("通知：\(notifyText(c.notifyStatus))").font(.system(size: 10.5)).foregroundColor(notifyColor(c.notifyStatus))
                }
            }
            Spacer()
            Button {
                Task { await deleteCall(c.id) }
            } label: {
                Image(systemName: "trash").font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: 短信行

    func smsRow(_ s: SmsRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(directionColor(s.direction).opacity(0.25)).frame(width: 34, height: 34)
                Image(systemName: s.direction == "outgoing" ? "paperplane.fill" : "arrow.down.left")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.number).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                    Spacer()
                    Text(Fmt.time(s.createdAt)).font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.4))
                }
                Text(s.content).font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.75)).lineLimit(3)
                HStack(spacing: 6) {
                    if s.spam == 1 { StatusPill(text: "垃圾", color: Theme.red) }
                    if !s.notifyStatus.isEmpty {
                        Text("通知：\(notifyText(s.notifyStatus))").font(.system(size: 10.5)).foregroundColor(notifyColor(s.notifyStatus))
                    }
                }
                if s.spam == 1, let rule = s.spamRule, !rule.isEmpty {
                    Text("命中：\(rule)").font(.system(size: 11)).foregroundColor(Theme.red).lineLimit(1)
                }
            }
            Button {
                Task { await deleteSms(s.id) }
            } label: {
                Image(systemName: "trash").font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    func directionColor(_ d: String) -> Color {
        d == "outgoing" ? Theme.accent : Theme.green
    }
    func notifyText(_ s: String) -> String {
        switch s {
        case "sent": return "已发送"
        case "queued": return "排队中"
        case "failed": return "失败"
        case "blocked": return "已屏蔽"
        default: return s
        }
    }
    func notifyColor(_ s: String) -> Color {
        s == "sent" ? Theme.green : (s == "blocked" ? Theme.orange : Theme.red)
    }

    func rangeFrom() -> Int64 {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        switch range {
        case .today:
            return Int64(start.timeIntervalSince1970)
        case .week:
            return Int64(cal.date(byAdding: .day, value: -6, to: start)!.timeIntervalSince1970)
        case .all:
            return 0
        }
    }

    @MainActor
    func reload() async {
        callPage = 1; smsPage = 1
        state = .loading
        do {
            if tab == .calls {
                let r = try await store.api.calls(page: 1, from: rangeFrom())
                calls = r.calls; callTotal = r.total
            } else {
                let r = try await store.api.sms(page: 1, from: rangeFrom())
                sms = r.sms; smsTotal = r.total
            }
            // 同步最近记录到桌面小组件
            if tab == .calls {
                store.saveCallsForWidget(calls.prefix(8).map {
                    SharedWidgetData.CallItem(number: $0.number, direction: $0.direction,
                                              time: $0.startedAt, spam: $0.spam > 0)
                })
            } else {
                store.saveSmsForWidget(sms.prefix(8).map {
                    SharedWidgetData.SmsItem(number: $0.number, content: $0.content,
                                             time: $0.createdAt, spam: $0.spam > 0)
                })
            }
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? error.localizedDescription)
        }
    }

    @MainActor
    func loadMore() async {
        let next = tab == .calls ? callPage + 1 : smsPage + 1
        do {
            if tab == .calls {
                let r = try await store.api.calls(page: next, from: rangeFrom())
                calls.append(contentsOf: r.calls); callPage = next
            } else {
                let r = try await store.api.sms(page: next, from: rangeFrom())
                sms.append(contentsOf: r.sms); smsPage = next
            }
        } catch {
            state = .failed((error as? APIError)?.message ?? error.localizedDescription)
        }
    }

    @MainActor
    func deleteCall(_ id: Int64) async {
        do {
            try await store.api.deleteCall(id: id)
            calls.removeAll { $0.id == id }
        } catch { state = .failed((error as? APIError)?.message ?? error.localizedDescription) }
    }

    @MainActor
    func deleteSms(_ id: Int64) async {
        do {
            try await store.api.deleteSms(id: id)
            sms.removeAll { $0.id == id }
        } catch { state = .failed((error as? APIError)?.message ?? error.localizedDescription) }
    }

    @MainActor
    func clearAll() async {
        do {
            if tab == .calls { try await store.api.clearCalls(days: 0); calls = [] }
            else { try await store.api.clearSms(days: 0); sms = [] }
        } catch { state = .failed((error as? APIError)?.message ?? error.localizedDescription) }
    }
}

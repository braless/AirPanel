import SwiftUI

// MARK: - 通信
//
// 三类记录共用一个页面：通话 / 短信 / 录音。
// 切换用玻璃分段控件，列表按天分组——同一天的东西放在一起，
// 时间才读得出来是「今天中午」还是「前天晚上」。

struct CommsView: View {
    @Environment(PanelStore.self) private var store

    enum Tab: Hashable { case calls, sms, recordings }

    @State private var tab: Tab = CommsView.initialTab
    @State private var hideSpam = false
    @State private var callDetail: CallRecord?
    @State private var smsDetail: SmsRecord?

    private static var initialTab: Tab {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-comms"), i + 1 < args.count {
            switch args[i + 1] {
            case "sms": return .sms
            case "recordings": return .recordings
            default: return .calls
            }
        }
        return .calls
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    PageHeader("通信", subtitle: subtitle) {
                        Button {
                            withAnimation(Motion.layout) { hideSpam.toggle() }
                        } label: {
                            Image(systemName: hideSpam ? "shield.lefthalf.filled" : "shield")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(hideSpam ? Theme.danger : Theme.ink2)
                                .frame(width: 40, height: 40)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.pressable)
                    }

                    GlassSegmented(
                        items: [(Tab.calls, "通话"), (Tab.sms, "短信"), (Tab.recordings, "录音")],
                        selection: $tab
                    )

                    switch tab {
                    case .calls: callsList
                    case .sms: smsList
                    case .recordings: recordingsList
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
            .refreshable { await store.refreshAll() }
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments

                // 联调用：`-loadmore` 自动翻一页，验证分页追加与去重。
                // 跟着当前分段走——短信页也能用同一条参数验分页。
                if args.contains("-loadmore") {
                    let isSms = tab == .sms
                    for _ in 0..<40 where isSms ? store.sms.isEmpty : store.calls.isEmpty {
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                    if isSms {
                        print("[page] sms before count=\(store.sms.count) total=\(store.smsTotal)")
                        await store.loadMoreSms()
                        print("[page] sms after  count=\(store.sms.count) total=\(store.smsTotal) canMore=\(store.canLoadMoreSms)")
                    } else {
                        await store.loadMoreCalls()
                    }
                }

                // 联调用：`-deletetop` 删掉第一条通话。
                // 只靠截图看不出删除有没有真落到后端，所以打完前后两份计数，
                // 再拿服务端 /api/calls 的 total 对一遍。
                if args.contains("-deletetop") {
                    for _ in 0..<40 where store.calls.isEmpty {
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                    if let first = store.calls.first {
                        print("[del] before total=\(store.callsTotal) count=\(store.calls.count) rawID=\(first.rawID)")
                        await store.deleteCall(first.id)
                        let still = store.calls.contains { $0.id == first.id }
                        print("[del] after  total=\(store.callsTotal) count=\(store.calls.count) stillHas=\(still)")
                    }
                }
                #endif
            }
            .onChange(of: tab) { _, newTab in
                // 切分段就抓一次这一段的最新数据：
                // 用户切过来是想看「现在的」，不是几分钟前的缓存
                Task {
                    switch newTab {
                    case .calls: await store.refreshCalls()
                    case .sms: await store.refreshSms()
                    case .recordings: await store.refreshRecordings()
                    }
                }
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $callDetail) { call in
                CallDetailSheet(call: call)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
            }
            .sheet(item: $smsDetail) { sms in
                SmsDetailSheet(sms: sms)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case .calls: return "今日 \(store.todayCallCount) 通 · 共 \(store.callsTotal) 条记录"
        case .sms: return "今日 \(store.todaySmsCount) 条 · 共 \(store.smsTotal) 条记录"
        case .recordings: return "\(store.recordings.count) 个文件 · 存于 WebDAV"
        }
    }

    // MARK: 通话

    private var filteredCalls: [CallRecord] {
        let list = hideSpam ? store.calls.filter { $0.spamRule == nil } : store.calls
        return list.sorted { $0.startedAt > $1.startedAt }
    }

    private var callsList: some View {
        VStack(spacing: Theme.Space.m) {
            if filteredCalls.isEmpty {
                GlassCard {
                    EmptyOrLoading(symbol: "phone",
                               title: hideSpam ? "没有非垃圾通话" : "还没有通话记录",
                               message: hideSpam ? "关闭右上角的屏蔽过滤可以看到全部记录。" : "设备接到来电或拨出电话后，记录会出现在这里。",
                               isLoading: store.isLoading(.calls) && !hideSpam)
                }
            } else {
                ForEach(dayGroups(filteredCalls, date: \.startedAt), id: \.key) { group in
                    GlassCard(padding: Theme.Space.m) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(group.key)
                                    .font(Theme.caption)
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.ink3)
                                Spacer()
                                Text("\(group.items.count) 通")
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.ink3)
                            }
                            .padding(.bottom, 6)

                            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, call in
                                // 不用 Button 包行：Button 的点击会在拖拽抬手时触发，
                                // 左滑和滚动都会误开详情。点击交给 SwipeToDelete 自己判。
                                SwipeToDelete(onTap: { callDetail = call },
                                              onDelete: { Task { await store.deleteCall(call.id) } }) {
                                    CallRow(call: call)
                                }
                                .transition(.asymmetric(insertion: .identity,
                                                        removal: .move(edge: .trailing).combined(with: .opacity)))
                                if idx < group.items.count - 1 {
                                    RowDivider(inset: 44)
                                }
                            }
                        }
                    }
                }

                if !hideSpam, store.canLoadMoreCalls {
                    loadMore(remaining: store.callsTotal - store.calls.count,
                             loading: store.isLoadingMoreCalls) {
                        Task { await store.loadMoreCalls() }
                    }
                }
            }
        }
    }

    // MARK: 短信

    private var filteredSms: [SmsRecord] {
        let list = hideSpam ? store.sms.filter { $0.spamRule == nil } : store.sms
        return list.sorted { $0.time > $1.time }
    }

    private var smsList: some View {
        VStack(spacing: Theme.Space.m) {
            if filteredSms.isEmpty {
                GlassCard {
                    EmptyOrLoading(symbol: "message",
                               title: "还没有短信",
                               message: "收到的验证码、通知短信都会同步到这里，垃圾短信会带标记。",
                               isLoading: store.isLoading(.sms))
                }
            } else {
                ForEach(dayGroups(filteredSms, date: \.time), id: \.key) { group in
                    GlassCard(padding: Theme.Space.m) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(group.key)
                                    .font(Theme.caption)
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.ink3)
                                Spacer()
                                Text("\(group.items.count) 条")
                                    .font(Theme.micro)
                                    .foregroundStyle(Theme.ink3)
                            }
                            .padding(.bottom, 6)

                            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, sms in
                                SwipeToDelete(onTap: { smsDetail = sms },
                                              onDelete: { Task { await store.deleteSms(sms.id) } }) {
                                    SmsRow(sms: sms)
                                }
                                .transition(.asymmetric(insertion: .identity,
                                                        removal: .move(edge: .trailing).combined(with: .opacity)))
                                if idx < group.items.count - 1 {
                                    RowDivider(inset: 44)
                                }
                            }
                        }
                    }
                }

                if !hideSpam, store.canLoadMoreSms {
                    loadMore(remaining: store.smsTotal - store.sms.count,
                             loading: store.isLoadingMoreSms) {
                        Task { await store.loadMoreSms() }
                    }
                }
            }
        }
    }

    // MARK: 录音

    private var recordingsList: some View {
        VStack(spacing: Theme.Space.m) {
            if store.recordings.isEmpty {
                GlassCard {
                    EmptyOrLoading(symbol: store.recordingsError == nil ? "waveform" : "externaldrive.badge.exclamationmark",
                               title: store.recordingsError == nil ? "还没有录音" : "录音存储不可用",
                               message: store.recordingsError
                                   ?? "开启「通话录音」后，接通即录音并自动上传到 WebDAV。",
                               isLoading: store.isLoading(.recordings),
                               action: nil)
                }
            } else {
                RecordingPlayerCard(recordings: store.recordings.sorted { $0.date > $1.date })
            }
        }
    }

    // MARK: 加载更多

    /// 一次只拉 20 条，剩下的交给这个按钮。
    /// 不做无限滚动：滚动到底自动请求，用户永远不知道自己在「加载什么」。
    private func loadMore(remaining: Int, loading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if loading {
                    ProgressView().controlSize(.mini).tint(Theme.ink2)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(loading ? "正在加载…" : "加载更多 · 还有 \(remaining) 条")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.99))
        .disabled(loading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.Radius.tile))
    }

    // MARK: 分组

    private struct DayGroup<Item> {
        let key: String
        let items: [Item]
    }

    private func dayGroups<Item>(_ items: [Item], date: KeyPath<Item, Date>) -> [DayGroup<Item>] {
        var order: [String] = []
        var map: [String: [Item]] = [:]
        for item in items {
            let key = Fmt.dayLabel(item[keyPath: date])
            if map[key] == nil {
                order.append(key)
                map[key] = []
            }
            map[key]?.append(item)
        }
        return order.map { DayGroup(key: $0, items: map[$0] ?? []) }
    }
}

// MARK: - 通话行

struct CallRow: View {
    let call: CallRecord

    private var tint: Color {
        if call.spamRule != nil { return Theme.danger }
        if call.status == .missed || call.status == .rejected { return Theme.warn }
        return call.direction == .incoming ? Theme.online : Theme.accent
    }

    private var title: String {
        call.contactName ?? Fmt.phone(call.number)
    }

    private var subtitle: String {
        if call.status == .connected {
            return "\(call.direction.label) · \(Fmt.duration(call.duration))"
        }
        return "\(call.direction.label) · \(call.status.label)"
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ZStack {
                Circle().fill(tint.opacity(0.13)).frame(width: 34, height: 34)
                Image(systemName: call.direction.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if call.hasRecording {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(call.status == .connected ? Theme.ink2 : tint.opacity(0.9))
                    // 通知状态：这条到底推没推出去。之前完全没渲染，设备端推送失败也看不出来
                    NotifyChip(state: call.notify)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.clock(call.startedAt))
                    .font(Theme.metric(12, .medium))
                    .foregroundStyle(Theme.ink3)
                if call.spamRule != nil {
                    Text("已拦截")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.danger.opacity(0.15)))
                }
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - 短信行

struct SmsRow: View {
    let sms: SmsRecord

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            ZStack {
                Circle()
                    .fill(sms.direction == .inbound ? Theme.cyan.opacity(0.13) : Theme.accent.opacity(0.13))
                    .frame(width: 34, height: 34)
                Image(systemName: sms.direction == .inbound ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(sms.direction == .inbound ? Theme.cyan : Theme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(sms.contactName ?? Fmt.phone(sms.number))
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if sms.spamRule != nil {
                        Text("垃圾")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.danger.opacity(0.15)))
                    }
                    Spacer(minLength: 4)
                    NotifyChip(state: sms.notify)
                    Text(Fmt.clock(sms.time))
                        .font(Theme.metric(11.5, .medium))
                        .foregroundStyle(Theme.ink3)
                }
                Text(sms.content)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - 录音播放卡片
//
// 录音文件带鉴权，只能取回 Data 再本地播，所以进度是真实播放进度。
// 播放中不再给「再点一次停止」的提示——按钮本身就从 play 变成 stop。

struct RecordingPlayerCard: View {
    let recordings: [Recording]

    @Environment(PanelStore.self) private var store
    @State private var player = AudioPlayer()

    var body: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(spacing: 0) {
                HStack {
                    Text("通话录音")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(recordings.count) 个")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.bottom, 8)

                ForEach(Array(recordings.enumerated()), id: \.element.id) { idx, rec in
                    // 录音也支持左滑删除（文件在 WebDAV 上，删了就没了，所以给了红底提示）
                    SwipeToDelete(onDelete: {
                        // 正在放的就是这一条：先把播放器停掉，否则会继续播一个已经不存在的文件
                        if player.isActive(rec.id) { player.stop() }
                        Task { await store.deleteRecording(rec.fileName) }
                    }) {
                        row(rec)
                    }
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
                    if idx < recordings.count - 1 {
                        RowDivider(inset: 46)
                    }
                }

                if let err = player.error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(err)
                            .font(Theme.micro)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 8)
                }
            }
        }
        .onDisappear { player.stop() }
        .onAppear {
            #if DEBUG
            // 截图 / 联调用：-autoplay 直接播第一条，
            // 验证 /api/recordings/play 带 Bearer 取流这条路是通的
            guard ProcessInfo.processInfo.arguments.contains("-autoplay"),
                  !didAutoplay, let first = recordings.first else { return }
            didAutoplay = true
            Task {
                await player.toggle(id: first.id) {
                    try await store.recordingData(file: first.fileName)
                }
            }
            #endif
        }
    }

    @State private var didAutoplay = false

    private func row(_ rec: Recording) -> some View {
        let active = player.isActive(rec.id)
        let playing = active && player.isPlaying
        let loading = active && player.isLoading

        return HStack(spacing: Theme.Space.s) {
            // 播放按钮改成 onTapGesture：外层套了 SwipeToDelete，
            // Button 的点击会在左滑抬手时误触发（通话/短信行踩过这个坑）
            ZStack {
                Circle()
                    .fill((playing ? Theme.danger : Theme.accent).opacity(0.13))
                    .frame(width: 34, height: 34)
                if loading {
                    ProgressView().controlSize(.mini).tint(Theme.accent)
                } else {
                    Image(systemName: playing ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(playing ? Theme.danger : Theme.accent)
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                Task {
                    await player.toggle(id: rec.id) {
                        try await store.recordingData(file: rec.fileName)
                    }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(playing ? "暂停" : "播放")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(Fmt.phone(rec.number))
                        .font(Theme.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(active && player.duration > 0
                         ? "\(Fmt.duration(player.progress * player.duration)) / \(Fmt.duration(player.duration))"
                         : Fmt.bytes(rec.sizeBytes))
                        .font(Theme.metric(11.5, .medium))
                        .foregroundStyle(active ? Theme.accent : Theme.ink3)
                }
                if active {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10))
                            Capsule().fill(Theme.accent)
                                .frame(width: max(2, geo.size.width * player.progress))
                        }
                    }
                    .frame(height: 3)
                } else {
                    HStack(spacing: 6) {
                        Text(Fmt.dayLabel(rec.date) + " " + Fmt.clock(rec.date))
                        Text("·")
                        Text(rec.fileName.hasSuffix(".wav") ? "WAV" : "AMR")
                    }
                    .font(Theme.micro)
                    .foregroundStyle(Theme.ink3)
                }
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - 通话详情

struct CallDetailSheet: View {
    let call: CallRecord
    @Environment(PanelStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                ZStack {
                    Circle().fill((call.direction == .incoming ? Theme.online : Theme.accent).opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: call.direction.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(call.direction == .incoming ? Theme.online : Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(call.contactName ?? Fmt.phone(call.number))
                        .font(Theme.title)
                        .foregroundStyle(Theme.ink)
                    Text("\(call.direction.label) · \(call.status.label)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
            }

            GlassCard(padding: Theme.Space.m) {
                VStack(spacing: 0) {
                    kv("时间", Fmt.dayLabel(call.startedAt) + " " + Fmt.clock(call.startedAt))
                    RowDivider()
                    kv("时长", call.status == .connected ? Fmt.duration(call.duration) : "—")
                    RowDivider()
                    kv("号码", Fmt.phone(call.number))
                    RowDivider()
                    // 通知状态：设备端回执，失败/屏蔽时这一行是最直接的排查入口
                    HStack {
                        Text("通知状态").font(Theme.caption).foregroundStyle(Theme.ink3)
                        Spacer()
                        NotifyChip(state: call.notify)
                    }
                    .padding(.vertical, 9)
                    if let rule = call.spamRule {
                        RowDivider()
                        kv("拦截规则", rule)
                    }
                }
            }

            HStack(spacing: Theme.Space.xs) {
                Button {
                    dismiss()
                } label: {
                    Label("回拨", systemImage: "phone.arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.accent))
                }
                .buttonStyle(.pressable(scale: 0.98))

                if call.hasRecording {
                    Button {} label: {
                        Label("录音", systemImage: "waveform")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 15))
                    }
                    .buttonStyle(.pressable(scale: 0.98))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.page)
        .background(Color.clear)
    }

    private func kv(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(Theme.caption).foregroundStyle(Theme.ink3)
            Spacer()
            Text(value).font(Theme.metric(13, .medium)).foregroundStyle(Theme.ink2)
        }
        .padding(.vertical, 9)
    }
}

// MARK: - 短信详情

struct SmsDetailSheet: View {
    let sms: SmsRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sms.contactName ?? Fmt.phone(sms.number))
                        .font(Theme.title)
                        .foregroundStyle(Theme.ink)
                    Text("\(sms.direction.label) · \(Fmt.dayLabel(sms.time)) \(Fmt.clock(sms.time))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
                NotifyChip(state: sms.notify)
                if sms.spamRule != nil {
                    Text("已拦截")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.danger.opacity(0.15)))
                }
            }

            GlassCard {
                Text(sms.content)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rule = sms.spamRule {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 11, weight: .semibold))
                    Text("命中规则「\(rule)」，通知状态：\(sms.notify.label)")
                        .font(Theme.caption)
                }
                .foregroundStyle(Theme.danger.opacity(0.9))
            }

            Button {
                dismiss()
            } label: {
                Text("用设备回复")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.accent))
            }
            .buttonStyle(.pressable(scale: 0.98))

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.page)
        .background(Color.clear)
    }
}

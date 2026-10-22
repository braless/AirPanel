import SwiftUI

// MARK: - 自动化
//
// 三段：任务（手动下发）/ 定时（周期执行）/ 记录（历史回执）。
// 任务区先给 6 个常用指令的大块入口，再按分组列全部 18 条——
// 常用的不该藏在三级菜单里。

struct AutomationView: View {
    @Environment(PanelStore.self) private var store

    enum Tab: Hashable { case tasks, schedules, log }

    @State private var tab: Tab = AutomationView.initialTab
    @State private var running: Command?

    private static var initialTab: Tab {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-auto"), i + 1 < args.count {
            switch args[i + 1] {
            case "schedules": return .schedules
            case "log": return .log
            default: return .tasks
            }
        }
        return .tasks
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    PageHeader("自动化", subtitle: subtitle) {
                        GlassIconButton(symbol: "terminal") {}
                    }

                    GlassSegmented(
                        items: [(Tab.tasks, "任务"), (Tab.schedules, "定时"), (Tab.log, "记录")],
                        selection: $tab
                    )

                    switch tab {
                    case .tasks: tasksTab
                    case .schedules: schedulesTab
                    case .log: logTab
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refreshAll() }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $running) { cmd in
                CommandRunnerSheet(command: cmd)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-runner") {
                    running = Catalog.command("send_sms")
                }
            }
            .task {
                #if DEBUG
                // 联调用：`-send query_status` 直接下发一条只读指令，
                // 用来验证 executeTask → 设备回执 → 记录刷新整条链路。
                let args = ProcessInfo.processInfo.arguments
                guard let i = args.firstIndex(of: "-send"), i + 1 < args.count,
                      let cmd = Catalog.command(args[i + 1]) else { return }
                for _ in 0..<60 where store.activeDevice == nil {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                store.send(cmd)
                #endif
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case .tasks: return "\(Catalog.all.count) 条远程指令 · 超时 30 秒"
        case .schedules:
            return "\(store.schedules.filter(\.enabled).count) 个已启用 · 共 \(store.schedulesTotal) 个"
        case .log:
            // 总数按服务端说的算：列表只拉最近两页，418 条不能写成 20 条
            return "今日 \(store.todayTaskCount) 次下发 · 共 \(store.tasksTotal) 条"
        }
    }

    // MARK: 任务

    private var tasksTab: some View {
        VStack(spacing: Theme.Space.m) {
            GlassCard(padding: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Text("常用指令")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(store.activeDevice?.displayName ?? "—")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.xs), count: 3),
                        spacing: Theme.Space.xs
                    ) {
                        ForEach(Catalog.primary.compactMap(Catalog.command)) { cmd in
                            CommandTile(command: cmd) { running = cmd }
                        }
                    }
                }
            }

            ForEach(CommandGroup.allCases, id: \.self) { group in
                GlassCard(padding: Theme.Space.m) {
                    VStack(spacing: 0) {
                        HStack {
                            Text(group.rawValue)
                                .font(Theme.caption)
                                .tracking(0.6)
                                .foregroundStyle(Theme.ink3)
                            Spacer()
                            Text("\(Catalog.all.filter { $0.group == group }.count) 条")
                                .font(Theme.micro)
                                .foregroundStyle(Theme.ink3)
                        }
                        .padding(.bottom, 4)

                        let cmds = Catalog.all.filter { $0.group == group }
                        ForEach(Array(cmds.enumerated()), id: \.element.id) { idx, cmd in
                            Button { running = cmd } label: {
                                CommandRow(command: cmd)
                            }
                            .buttonStyle(.pressable(scale: 0.99))
                            if idx < cmds.count - 1 {
                                RowDivider(inset: 44)
                            }
                        }
                    }
                }
            }

            consoleCard
        }
    }

    private var consoleCard: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text("最近下发")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("清空") {
                        withAnimation(Motion.fade) { store.clearConsole() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .buttonStyle(.pressable)
                }
                ConsoleView(lines: store.console, maxHeight: 150)
            }
        }
    }

    // MARK: 定时

    private var schedulesTab: some View {
        VStack(spacing: Theme.Space.m) {
            if store.schedules.isEmpty {
                GlassCard {
                    EmptyOrLoading(symbol: "clock",
                                   title: "还没有定时任务",
                                   message: "定时任务可以按天、按周或按间隔执行指令，例如每天凌晨重启一次。",
                                   isLoading: store.isLoading(.schedules))
                }
            } else {
                ForEach(store.schedules) { schedule in
                    ScheduleCard(schedule: schedule)
                }
            }
        }
    }

    // MARK: 记录

    private var logTab: some View {
        VStack(spacing: Theme.Space.m) {
            if store.taskRecords.isEmpty {
                GlassCard {
                    EmptyOrLoading(symbol: "checklist",
                                   title: "还没有执行记录",
                                   message: "下发任务后，回执与耗时都会记在这里，失败会标红。",
                                   isLoading: store.isLoading(.tasks))
                }
            } else {
                GlassCard(padding: Theme.Space.m) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.taskRecords.enumerated()), id: \.element.id) { idx, record in
                            TaskLogRow(record: record)
                            if idx < store.taskRecords.count - 1 {
                                RowDivider(inset: 18)
                            }
                        }
                    }
                }

                // 手机只拉最近 20 条，说清楚「还有更多」，别让人以为记录被吞了
                if store.tasksTotal > store.taskRecords.count {
                    Text("仅显示最近 \(store.taskRecords.count) 条，更早的记录请到网页端查看")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - 指令方块

struct CommandTile: View {
    let command: Command
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: command.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(command.tint)
                    .frame(height: 20)
                Text(command.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(command.tint.opacity(0.09))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(command.tint.opacity(0.14), lineWidth: 0.75)
            }
        }
        .buttonStyle(.pressable(scale: 0.96))
    }
}

// MARK: - 指令行

struct CommandRow: View {
    let command: Command

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            IconBadge(symbol: command.symbol, tint: command.tint, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.label)
                    .font(Theme.bodyStrong)
                    .foregroundStyle(Theme.ink)
                Text(command.summary)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if command.needsForm {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.ink3.opacity(0.7))
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - 定时任务卡

struct ScheduleCard: View {
    let schedule: Schedule
    @Environment(PanelStore.self) private var store
    @State private var on = false

    var body: some View {
        GlassCard(padding: Theme.Space.m) {
            VStack(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    IconBadge(
                        symbol: schedule.enabled ? "clock.fill" : "clock",
                        tint: schedule.enabled ? Theme.violet : Theme.ink3,
                        size: 34
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(schedule.name)
                            .font(Theme.bodyStrong)
                            .foregroundStyle(schedule.enabled ? Theme.ink : Theme.ink2)
                        Text("\(schedule.taskLabel) · \(schedule.humanSpec)")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer(minLength: 4)
                    Toggle("", isOn: Binding(
                        get: { schedule.enabled },
                        set: { _ in
                            Task { await store.toggleSchedule(schedule.id) }
                        }
                    ))
                    .labelsHidden()
                    .tint(Theme.violet)
                    .scaleEffect(0.85)
                }

                RowDivider()

                HStack(spacing: Theme.Space.m) {
                    HStack(spacing: 4) {
                        Text("上次")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)
                        Text(schedule.lastRun.map { Fmt.ago($0) } ?? "从未")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink2)
                    }
                    HStack(spacing: 4) {
                        Text("下次")
                            .font(Theme.micro)
                            .foregroundStyle(Theme.ink3)
                        Text(schedule.nextRun.map { Fmt.until($0) } ?? "—")
                            .font(Theme.micro)
                            .foregroundStyle(schedule.enabled ? Theme.violet : Theme.ink3)
                    }
                    Spacer()
                    Text(schedule.deviceName)
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
        }
        .opacity(schedule.enabled ? 1 : 0.72)
        .motion(Motion.layout, value: schedule.enabled)
    }
}

// MARK: - 任务记录行

struct TaskLogRow: View {
    let record: TaskRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(record.status.tint)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.label)
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                    Text(record.status.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(record.status.tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(record.status.tint.opacity(0.14)))
                    Spacer(minLength: 0)
                    Text(Fmt.ago(record.createdAt))
                        .font(Theme.micro)
                        .foregroundStyle(Theme.ink3)
                }
                Text(record.result)
                    .font(Theme.mono)
                    .foregroundStyle(record.status == .failed ? Theme.danger.opacity(0.85) : Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(record.deviceName)
                    Text("·")
                    Text(record.durationText)
                }
                .font(Theme.micro)
                .foregroundStyle(Theme.ink3.opacity(0.8))
            }
        }
        .padding(.vertical, 9)
    }
}

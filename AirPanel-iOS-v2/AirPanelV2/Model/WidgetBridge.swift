import Foundation

// MARK: - 给桌面小组件写快照
//
// 小组件不联网，只能读 App 写进 App Group 的那份快照。
// 这里负责把 PanelStore 里的展示模型压成快照需要的形状：
// 只保留要显示的字，号码、时长、状态文案都在 App 侧就格式化好，
// 小组件进程里不再做业务判断。

extension PanelStore {

    /// 刷新结束后调用。中途写会把「一半数据」推上桌面，所以只在收尾处调。
    func publishWidgetSnapshot() {
        guard session != nil, client != nil else {
            // 没登录就把桌面上的旧数据清掉，否则退出登录后小组件还在显示上一台服务器
            WidgetSnapshotStore.clear()
            return
        }

        let ordered = devices.sorted { lhs, rhs in
            if lhs.imei == activeDeviceID { return true }
            if rhs.imei == activeDeviceID { return false }
            return lhs.isOnline && !rhs.isOnline
        }

        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            serverHost: serverHost,
            device: activeDevice.map(widgetDevice),
            devices: ordered.prefix(3).map(widgetDevice),
            calls: calls.prefix(3).map(widgetCall),
            sms: sms.prefix(3).map(widgetSms),
            stats: widgetStats,
            accent: AccentTheme.shared.choice.rawValue
        )
        WidgetSnapshotStore.save(snapshot)
    }

    // MARK: 映射

    private func widgetDevice(_ device: Device) -> WidgetDevice {
        let t = device.telemetry
        return WidgetDevice(
            id: device.imei,
            name: device.displayName,
            online: device.isOnline,
            battery: t.batteryPercent,
            charging: t.isCharging,
            voltage: Double(t.voltageMV) / 1000,
            temperature: t.temperature,
            csq: t.csq,
            estHours: t.estHours
        )
    }

    private func widgetCall(_ call: CallRecord) -> WidgetEvent {
        let connected = call.status == .connected
        let tone: WidgetEvent.Tone
        if connected {
            tone = call.direction == .incoming ? .incoming : .outgoing
        } else {
            // 未接、拒接、无应答、已取消，在桌面上都该是「没接通」这一种视觉
            tone = .missed
        }
        return WidgetEvent(
            id: call.id,
            title: call.contactName ?? Fmt.phone(call.number),
            detail: connected ? "通话 \(Fmt.duration(call.duration))" : call.status.label,
            date: call.startedAt,
            tone: tone,
            flagged: call.spamRule != nil
        )
    }

    private func widgetSms(_ record: SmsRecord) -> WidgetEvent {
        WidgetEvent(
            id: record.id,
            title: record.contactName ?? Fmt.phone(record.number),
            detail: record.content.replacingOccurrences(of: "\n", with: " "),
            date: record.time,
            tone: .plain,
            flagged: record.spamRule != nil
        )
    }

    /// 优先用服务端 `/api/stats/summary` 的口径；没拿到时退回本地计数，
    /// 免得小组件在首屏没加载完时显示一排 0。
    private var widgetStats: WidgetStats {
        let s = stats
        return WidgetStats(
            devices: s?.devices ?? devices.count,
            online: onlineCount,
            callsToday: s?.callsToday ?? todayCallCount,
            callIn: s?.callIn ?? calls.filter { $0.direction == .incoming }.count,
            callOut: s?.callOut ?? calls.filter { $0.direction == .outgoing }.count,
            callMissed: s?.callMissed ?? calls.filter { $0.status != .connected }.count,
            smsToday: s?.smsToday ?? todaySmsCount,
            smsIn: s?.smsIn ?? sms.filter { $0.direction == .inbound }.count,
            smsOut: s?.smsOut ?? sms.filter { $0.direction == .outbound }.count,
            tasksToday: s?.tasksToday ?? todayTaskCount,
            tasksOK: s?.tasksOK ?? taskRecords.filter { $0.status == .success }.count,
            tasksFailed: s?.tasksFailed ?? taskRecords.filter { $0.status == .failed }.count,
            blockedToday: spamCount
        )
    }
}

import Foundation

// MARK: - 展示层格式化
//
// 规则：所有时间/时长/容量只在视图层格式化一次，模型里存原始值。
// 相对时间用于「最近」，超过 24 小时一律给绝对时间——避免出现「3 天前」这种没信息量的说法。

enum Fmt {

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.unitsStyle = .short
        return f
    }()

    /// 紧凑相对时间：刚刚 / 12 分钟前 / 3 小时前
    static func ago(_ date: Date, now: Date = .now) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 45 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
        if delta < 86_400 { return "\(Int(delta / 3600)) 小时前" }
        return dayLabel(date, now: now) + " " + clock(date)
    }

    /// 时钟：14:32
    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// 距现在还有多久：36 分钟后 / 17 小时后 / 明天 04:00
    static func until(_ date: Date, now: Date = .now) -> String {
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "即将执行" }
        if delta < 3600 { return "\(max(1, Int(delta / 60))) 分钟后" }
        if delta < 86_400 { return "\(Int(delta / 3600)) 小时后" }
        return dayLabel(date, now: now) + " " + clock(date)
    }

    /// 日期标签：今天 / 昨天 / 10月19日
    static func dayLabel(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
            .replacingOccurrences(of: "/", with: "月") + "日"
    }

    /// 时长：3:24 / 1:02:15
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// 在线时长：2 小时 14 分
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let d = total / 86_400
        let h = (total % 86_400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return "\(d) 天 \(h) 小时" }
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分"
    }

    static func bytes(_ count: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(count))
    }

    /// 号码分组：138 0013 8000
    static func phone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 11 else { return raw }
        let a = digits.prefix(3)
        let b = digits.dropFirst(3).prefix(4)
        let c = digits.suffix(4)
        return "\(a) \(b) \(c)"
    }

    /// 号码尾号，用于列表里快速辨认
    static func tail(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 4 else { return raw }
        return String(digits.suffix(4))
    }

    static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))"
    }
}

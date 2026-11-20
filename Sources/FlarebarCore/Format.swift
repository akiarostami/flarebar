import Foundation

public enum Format {
    /// 8110 -> "8.11K", 959 -> "959", 10_000_000 -> "10M", 25e9 -> "25B". Three significant digits.
    public static func compact(_ value: Double) -> String {
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (size, suffix) in units where abs(value) >= size {
            return trimmed(value / size) + suffix
        }
        return trimmed(value)
    }

    static func trimmed(_ value: Double) -> String {
        let magnitude = abs(value)
        let digits = magnitude < 10 ? 2 : (magnitude < 100 ? 1 : 0)
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// A bar's value in its own unit.
    public static func value(_ bar: Bar) -> String {
        bar.key == "r2_gb" ? trimmed(bar.value) + " GB" : compact(bar.value)
    }

    /// 0.184 -> "18%".
    public static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    public static func money(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }

    /// "3 min", "5 hr", "22 days, 15 hr", "5 mths, 6 days" (30-day months).
    public static func ago(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if hours < 1 { return "\(minutes) min" }
        if days < 1 { return "\(hours) hr" }
        if days < 30 { return "\(plural(days, "day")), \(hours % 24) hr" }
        return "\(plural(days / 30, "mth")), \(plural(days % 30, "day"))"
    }

    static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}

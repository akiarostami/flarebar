import Foundation

public struct LimitRow: Sendable {
    public var key: String
    public var label: String
    public var shortLabel: String
    public var limit: Double
    public var limitText: String
    public var window: Window
}

/// Account allowances by Workers plan.
/// Workers Paid: included per billing period. Workers Free: daily limits (UTC day);
/// R2's free tier is monthly on both.
/// Sources: https://developers.cloudflare.com/workers/platform/pricing/ and the product pricing pages.
public enum PlanLimits {
    public static func rows(for plan: Plan) -> [LimitRow] {
        switch plan {
        case .paid:
            return [
                LimitRow(key: "req", label: "Workers requests", shortLabel: "Req", limit: 10_000_000, limitText: "10M", window: .period),
                LimitRow(key: "r2_a", label: "R2 Class A", shortLabel: "R2 A", limit: 1_000_000, limitText: "1M", window: .period),
                LimitRow(key: "r2_b", label: "R2 Class B", shortLabel: "R2 B", limit: 10_000_000, limitText: "10M", window: .period),
                LimitRow(key: "r2_gb", label: "R2 storage", shortLabel: "R2", limit: 10, limitText: "10 GB", window: .now),
                LimitRow(key: "d1_read", label: "D1 rows read", shortLabel: "D1 read", limit: 25_000_000_000, limitText: "25B", window: .period),
                LimitRow(key: "d1_written", label: "D1 rows written", shortLabel: "D1 write", limit: 50_000_000, limitText: "50M", window: .period),
                LimitRow(key: "kv_read", label: "KV reads", shortLabel: "KV", limit: 10_000_000, limitText: "10M", window: .period),
                LimitRow(key: "do_req", label: "DO requests", shortLabel: "DO", limit: 1_000_000, limitText: "1M", window: .period),
            ]
        case .free:
            return [
                LimitRow(key: "req", label: "Workers requests", shortLabel: "Req", limit: 100_000, limitText: "100K", window: .day),
                LimitRow(key: "r2_a", label: "R2 Class A", shortLabel: "R2 A", limit: 1_000_000, limitText: "1M", window: .period),
                LimitRow(key: "r2_b", label: "R2 Class B", shortLabel: "R2 B", limit: 10_000_000, limitText: "10M", window: .period),
                LimitRow(key: "r2_gb", label: "R2 storage", shortLabel: "R2", limit: 10, limitText: "10 GB", window: .now),
                LimitRow(key: "d1_read", label: "D1 rows read", shortLabel: "D1 read", limit: 5_000_000, limitText: "5M", window: .day),
                LimitRow(key: "d1_written", label: "D1 rows written", shortLabel: "D1 write", limit: 100_000, limitText: "100K", window: .day),
                LimitRow(key: "kv_read", label: "KV reads", shortLabel: "KV", limit: 100_000, limitText: "100K", window: .day),
                LimitRow(key: "do_req", label: "DO requests", shortLabel: "DO", limit: 100_000, limitText: "100K", window: .day),
            ]
        }
    }
}

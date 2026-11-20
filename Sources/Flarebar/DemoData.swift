import FlarebarCore
import Foundation

/// Invented accounts and figures, shown when the app is launched with FLAREBAR_DEMO set.
/// Demo mode reads no tokens, makes no network calls and saves nothing; it exists so the
/// interface can be shown, and its pictures taken, without anyone's real data.
enum DemoData {
    static let isOn = ProcessInfo.processInfo.environment["FLAREBAR_DEMO"] != nil

    static let acme = "demo0000000000000000000000000001"
    static let side = "demo0000000000000000000000000002"
    static let sandbox = "demo0000000000000000000000000003"

    static let config = Config(accounts: [
        Account(id: acme, name: "Acme Studio", projects: [
            Project(name: "Storefront", prefixes: ["storefront-"]),
            Project(name: "Blog", prefixes: ["blog-", "www-"]),
            Project(name: "Internal Tools", prefixes: ["tools-"]),
        ]),
        Account(id: side, name: "Side Projects", projects: [
            Project(name: "Recipes", prefixes: ["recipes-"]),
            Project(name: "Weather", prefixes: ["weather-"]),
        ]),
    ])

    /// The accounts each demo token can see: one token covers two accounts, one of them not in the menu.
    static let tokenAccounts: [[VisibleAccount]] = [
        [VisibleAccount(id: acme, name: "Acme Studio"), VisibleAccount(id: sandbox, name: "Acme Sandbox")],
        [VisibleAccount(id: side, name: "Side Projects")],
    ]

    static func snapshots(now: Date = Date()) -> [AccountSnapshot] {
        func bars(_ plan: Plan, _ values: [String: Double]) -> [Bar] {
            PlanLimits.rows(for: plan).map { row in
                Bar(key: row.key, label: row.label, shortLabel: row.shortLabel, value: values[row.key] ?? 0,
                    limit: row.limit, limitText: row.limitText, window: row.window)
            }
        }
        func worker(_ name: String, hoursAgo: Double, from client: String = "wrangler") -> WorkerInfo {
            WorkerInfo(name: name, modifiedOn: now.addingTimeInterval(-hoursAgo * 3600), deployedFrom: client)
        }

        let acmeSnapshot = AccountSnapshot(
            accountID: acme, name: "Acme Studio", plan: .paid,
            bill: Bill(usageUSD: 5.05, subsUSD: 5, totalUSD: 10.05, periodStart: "2026-11-05",
                       subscriptions: [MoneyItem(name: "Workers Paid", usd: 5)],
                       lineItems: [MoneyItem(name: "Durable Objects Requests", usd: 3.42),
                                   MoneyItem(name: "R2 Storage", usd: 1.11),
                                   MoneyItem(name: "Workers KV Reads", usd: 0.52)]),
            monthStart: "2026-11-05",
            projects: [
                ProjectSnapshot(
                    name: "Storefront",
                    bars: bars(.paid, ["req": 6_240_000, "r2_a": 312_000, "r2_b": 2_150_000, "r2_gb": 7.4,
                                       "d1_read": 3_100_000_000, "d1_written": 12_400_000,
                                       "kv_read": 4_420_000, "do_req": 182_000]),
                    workers: [worker("storefront-web", hoursAgo: 2), worker("storefront-api", hoursAgo: 71),
                              worker("storefront-checkout", hoursAgo: 75), worker("storefront-jobs", hoursAgo: 290),
                              worker("storefront-web-staging", hoursAgo: 310)]),
                ProjectSnapshot(
                    name: "Blog",
                    bars: bars(.paid, ["req": 820_000, "r2_a": 4_100, "r2_b": 96_000, "r2_gb": 1.2,
                                       "d1_read": 41_000_000, "d1_written": 18_000, "kv_read": 230_000]),
                    workers: [worker("blog-site", hoursAgo: 630, from: "dash"), worker("www-redirects", hoursAgo: 2900)]),
                ProjectSnapshot(
                    name: "Internal Tools",
                    bars: bars(.paid, ["req": 1_310_000, "r2_gb": 0.3, "d1_read": 880_000_000,
                                       "d1_written": 2_900_000, "kv_read": 61_000, "do_req": 931_000]),
                    workers: [worker("tools-admin", hoursAgo: 26), worker("tools-reports", hoursAgo: 3700)]),
            ],
            otherWorkers: [worker("scratchpad", hoursAgo: 4100, from: "quick_editor")],
            otherBars: bars(.paid, ["req": 12_300, "kv_read": 900]),
            fetchedAt: now)

        let sideSnapshot = AccountSnapshot(
            accountID: side, name: "Side Projects", plan: .free,
            bill: Bill(usageUSD: 0, subsUSD: 0, totalUSD: 0, periodStart: "2026-11-11"),
            monthStart: "2026-11-11",
            projects: [
                ProjectSnapshot(
                    name: "Recipes",
                    bars: bars(.free, ["req": 41_200, "r2_a": 1_900, "r2_b": 22_000, "r2_gb": 0.8,
                                       "d1_read": 1_240_000, "d1_written": 9_300]),
                    workers: [worker("recipes-app", hoursAgo: 19), worker("recipes-images", hoursAgo: 480)]),
                ProjectSnapshot(
                    name: "Weather",
                    bars: bars(.free, ["req": 9_100, "kv_read": 22_400, "do_req": 3_100]),
                    workers: [worker("weather-worker", hoursAgo: 215)]),
            ],
            otherWorkers: [],
            otherBars: bars(.free, [:]),
            fetchedAt: now)

        return [acmeSnapshot, sideSnapshot]
    }
}

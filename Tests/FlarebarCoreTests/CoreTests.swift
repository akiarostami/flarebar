import Foundation
import Testing
@testable import FlarebarCore

@Suite struct ConfigTests {
    @Test func prefixMatching() {
        let project = Project(name: "Blog", prefixes: ["blog-", "www-"])
        #expect(project.matches("blog-site"))
        #expect(project.matches("www-landing"))
        #expect(!project.matches("shop-www"))
        #expect(!Project(name: "Empty", prefixes: []).matches("anything"))
        #expect(!Project(name: "Blank", prefixes: [""]).matches("anything"))
    }

    @Test func barFractionAndSeverity() {
        func bar(_ value: Double, _ limit: Double) -> Bar {
            Bar(key: "req", label: "", shortLabel: "", value: value, limit: limit, limitText: "", window: .day)
        }
        #expect(bar(150, 100).fraction == 1)
        #expect(bar(150, 100).ratio == 1.5)
        #expect(bar(5, 0).fraction == 0)
        #expect(bar(70, 100).severity == .normal)
        #expect(bar(71, 100).severity == .warning)
        #expect(bar(90, 100).severity == .warning)
        #expect(bar(91, 100).severity == .critical)
        let custom = Thresholds(warning: 0.3, critical: 0.5)
        #expect(bar(30, 100).severity(custom) == .normal)
        #expect(bar(31, 100).severity(custom) == .warning)
        #expect(bar(51, 100).severity(custom) == .critical)
    }

    @Test func planLimits() {
        let paid = PlanLimits.rows(for: .paid)
        let free = PlanLimits.rows(for: .free)
        #expect(paid.map(\.key) == ["req", "r2_a", "r2_b", "r2_gb", "d1_read", "d1_written", "kv_read", "do_req"])
        #expect(free.map(\.key) == paid.map(\.key))
        #expect(paid[0].limit == 10_000_000 && paid[0].window == .period)
        #expect(free[0].limit == 100_000 && free[0].window == .day)
        #expect(free.first { $0.key == "d1_read" }?.limit == 5_000_000)
        #expect(free.first { $0.key == "r2_a" }?.window == .period)
    }
}

@Suite struct UsageBuilderTests {
    let expected = Fixtures.json("expected.json")

    func check(_ snapshot: AccountSnapshot, against key: String) {
        let table = expected[key] as! [String: [String: Double]]
        #expect(snapshot.projects.map(\.name) == ["Shop", "Blog", "Shop API"])
        for project in snapshot.projects {
            for bar in project.bars {
                #expect(bar.value == table[project.name]![bar.key]!, "\(key) \(project.name) \(bar.key)")
            }
        }
        // Other: the ungrouped Worker, and the D1 database whose name is unknown.
        let other = expected["other_\(key)"] as! [String: Double]
        #expect(snapshot.other?.name == "Other")
        for bar in snapshot.otherBars {
            #expect(bar.value == other[bar.key]!, "\(key) Other \(bar.key)")
        }
    }

    @Test func paidBarsUseThePeriod() {
        let snapshot = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(), lastKnownPlan: nil, now: Fixtures.now)
        #expect(snapshot.plan == .paid)
        #expect(snapshot.monthStart == expected["month_start"] as! String)
        check(snapshot, against: "paid")
    }

    @Test func freeBarsUseToday() {
        let raw = Fixtures.raw(billing: Fixtures.billing(subscriptions: "subscriptions_free.json"))
        let snapshot = UsageBuilder.build(account: Fixtures.account, raw: raw, lastKnownPlan: .paid, now: Fixtures.now)
        #expect(snapshot.plan == .free)
        check(snapshot, against: "free")
    }

    @Test func bill() {
        let snapshot = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(), lastKnownPlan: nil, now: Fixtures.now)
        let bill = expected["bill_paid"] as! [String: Any]
        #expect(snapshot.bill.usageUSD == bill["usage_usd"] as? Double)
        #expect(snapshot.bill.subsUSD == bill["subs_usd"] as? Double)
        #expect(snapshot.bill.totalUSD == bill["total_usd"] as? Double)
        #expect(snapshot.bill.periodStart == bill["period_start"] as? String)
        #expect(snapshot.bill.creditUSD == nil)
        // Only the latest billing period's lines, shortened, largest first; free plans left out.
        #expect(snapshot.bill.lineItems == [
            MoneyItem(name: "Container Memory", usd: 10.25),
            MoneyItem(name: "Container Disk", usd: 2.0),
            MoneyItem(name: "R2 Storage", usd: 0.15),
        ])
        #expect(snapshot.bill.subscriptions == [MoneyItem(name: "Workers Paid", usd: 5.0)])
    }

    @Test func workersAreGroupedAndNewestFirst() {
        let snapshot = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(), lastKnownPlan: nil, now: Fixtures.now)
        #expect(snapshot.projects[0].workers.map(\.name) == expected["shop_workers_newest_first"] as! [String])
        #expect(snapshot.projects[1].workers.map(\.name) == ["blog-site", "www-landing"])
        #expect(snapshot.projects[2].workers.map(\.name) == ["shop-api"])
        #expect(snapshot.otherWorkers.map(\.name) == expected["other_workers"] as! [String])
        #expect(snapshot.projects[0].workers[0].deployedFrom == "wrangler")
        #expect(snapshot.projects[0].workers[0].modifiedOn != nil)
    }

    @Test func missingBillingFallsBack() {
        let raw = Fixtures.raw(billing: RawBilling())
        let unknown = UsageBuilder.build(account: Fixtures.account, raw: raw, lastKnownPlan: nil, now: Fixtures.now)
        #expect(unknown.plan == .paid)
        #expect(unknown.bill == Bill())
        #expect(unknown.monthStart == "2026-11-01")
        let remembered = UsageBuilder.build(account: Fixtures.account, raw: raw, lastKnownPlan: .free, now: Fixtures.now)
        #expect(remembered.plan == .free)
    }

    @Test func monthStartRules() {
        let now = Fixtures.now
        let day = UsageBuilder.dayFormatter()
        #expect(day.string(from: UsageBuilder.monthStart(now: now, periodStart: "2026-11-05")) == "2026-11-05")
        // More than 31 days back, in the future, or unparsable: the calendar month.
        #expect(day.string(from: UsageBuilder.monthStart(now: now, periodStart: "2026-10-05")) == "2026-11-01")
        #expect(day.string(from: UsageBuilder.monthStart(now: now, periodStart: "2026-12-05")) == "2026-11-01")
        #expect(day.string(from: UsageBuilder.monthStart(now: now, periodStart: "nonsense")) == "2026-11-01")
        #expect(day.string(from: UsageBuilder.monthStart(now: now, periodStart: nil)) == "2026-11-01")
    }

    @Test func parsesCloudflareDates() {
        #expect(UsageBuilder.parseDate("2026-11-18T10:00:00.123456Z") != nil)
        #expect(UsageBuilder.parseDate("2026-11-18T10:00:00Z") != nil)
        #expect(UsageBuilder.parseDate("yesterday") == nil)
    }
}

@Suite struct HeadlineTests {
    let expected = Fixtures.json("expected.json")

    @Test func worstBarAndBill() {
        let paid = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(), lastKnownPlan: nil, now: Fixtures.now)
        #expect(Headline.make([paid])?.text == expected["headline_paid"] as? String)
        #expect(Headline.make([paid])?.severity == .normal)
        // Shop's R2 storage is at 20%.
        #expect(Headline.make([paid], thresholds: Thresholds(warning: 0.1, critical: 0.5))?.severity == .warning)
        #expect(Headline.make([paid], thresholds: Thresholds(warning: 0.1, critical: 0.15))?.severity == .critical)
        let free = UsageBuilder.build(account: Fixtures.account,
                                      raw: Fixtures.raw(billing: Fixtures.billing(subscriptions: "subscriptions_free.json")),
                                      lastKnownPlan: nil, now: Fixtures.now)
        #expect(Headline.make([free])?.text == expected["headline_free"] as? String)
    }

    @Test func acrossAccounts() {
        let one = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(), lastKnownPlan: nil, now: Fixtures.now)
        var two = one
        two.name = "Second"
        two.projects = [ProjectSnapshot(name: "Hot", bars: [
            Bar(key: "kv_read", label: "KV reads", shortLabel: "KV", value: 95, limit: 100, limitText: "100", window: .day)
        ], workers: [])]
        two.bill = Bill(totalUSD: 1.1)
        let headline = Headline.make([one, two])
        #expect(headline?.text == "Hot KV 95% · $18.50")
        #expect(headline?.severity == .critical)
    }

    @Test func billOmittedWhenUnknownAndNilWithoutProjects() {
        var snapshot = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(billing: RawBilling()),
                                          lastKnownPlan: nil, now: Fixtures.now)
        #expect(Headline.make([snapshot])?.text == "Shop R2 20%")
        snapshot.projects = []
        #expect(Headline.make([snapshot])?.text == "Other Req 0%")
        snapshot.otherBars = []
        snapshot.otherWorkers = []
        #expect(snapshot.other == nil)
        #expect(Headline.make([snapshot]) == nil)
        #expect(Headline.make([]) == nil)
    }
}

@Suite struct FormatTests {
    @Test func compact() {
        #expect(Format.compact(8110) == "8.11K")
        #expect(Format.compact(959) == "959")
        #expect(Format.compact(7950) == "7.95K")
        #expect(Format.compact(21300) == "21.3K")
        #expect(Format.compact(240000) == "240K")
        #expect(Format.compact(10_000_000) == "10M")
        #expect(Format.compact(25_000_000_000) == "25B")
        #expect(Format.compact(0) == "0")
    }

    @Test func valueAndPercentAndMoney() {
        let storage = Bar(key: "r2_gb", label: "", shortLabel: "", value: 1.85, limit: 10, limitText: "10 GB", window: .now)
        #expect(Format.value(storage) == "1.85 GB")
        #expect(Format.percent(0.184) == "18%")
        #expect(Format.percent(1.5) == "150%")
        #expect(Format.money(17.4) == "$17.40")
    }

    @Test func ago() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func back(days: Int = 0, hours: Int = 0, minutes: Int = 0) -> Date {
            now.addingTimeInterval(-Double(days * 86400 + hours * 3600 + minutes * 60))
        }
        #expect(Format.ago(from: back(minutes: 3), to: now) == "3 min")
        #expect(Format.ago(from: back(hours: 5, minutes: 20), to: now) == "5 hr")
        #expect(Format.ago(from: back(days: 22, hours: 15), to: now) == "22 days, 15 hr")
        #expect(Format.ago(from: back(days: 1, hours: 2), to: now) == "1 day, 2 hr")
        #expect(Format.ago(from: back(days: 156), to: now) == "5 mths, 6 days")
    }
}

@Suite struct StoreTests {
    func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("flarebar-tests-\(UUID().uuidString)")
    }

    @Test func configRoundTrip() throws {
        let store = ConfigStore(directory: tempDirectory())
        #expect(try store.load() == Config())
        try store.save(Fixtures.config)
        #expect(try store.load() == Fixtures.config)
    }

    @Test func snapshotCacheRoundTripAndCorruptFile() throws {
        let directory = tempDirectory()
        let cache = SnapshotCache(directory: directory)
        #expect(cache.load().isEmpty)
        let snapshot = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(), lastKnownPlan: nil, now: Fixtures.now)
        try cache.save([snapshot])
        #expect(cache.load() == [snapshot])
        try Data("not json".utf8).write(to: cache.fileURL)
        #expect(cache.load().isEmpty)
    }
}

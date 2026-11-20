import Foundation

/// Turns one account's raw Cloudflare responses into a snapshot grouped by project.
public enum UsageBuilder {
    // From https://developers.cloudflare.com/r2/pricing/ (checked 2026-11-14).
    static let r2ClassA: Set<String> = [
        "ListBuckets", "PutBucket", "ListObjects", "PutObject", "CopyObject",
        "CompleteMultipartUpload", "CreateMultipartUpload", "LifecycleStorageTierTransition",
        "ListMultipartUploads", "UploadPart", "UploadPartCopy", "ListParts",
        "PutBucketEncryption", "PutBucketCors", "PutBucketLifecycleConfiguration",
    ]
    static let r2ClassB: Set<String> = [
        "HeadBucket", "HeadObject", "GetObject", "UsageSummary", "GetBucketEncryption",
        "GetBucketLocation", "GetBucketCors", "GetBucketLifecycleConfiguration",
    ]

    static let bytesPerGB = 1_000_000_000.0

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Start of the monthly window: the billing period if known and within the last 31 days
    /// (analytics allow no more), else the first of the calendar month. UTC.
    public static func monthStart(now: Date, periodStart: String?) -> Date {
        let month = utc.date(from: utc.dateComponents([.year, .month], from: now)) ?? now
        guard let periodStart, let start = dayFormatter().date(from: periodStart) else { return month }
        if start <= now, start > now.addingTimeInterval(-31 * 86400) {
            return start
        }
        return month
    }

    /// The billing figures and, when subscriptions are readable, the Workers plan.
    public static func bill(_ raw: RawBilling) -> (bill: Bill, plan: Plan?) {
        var bill = Bill()
        var plan: Plan?
        if let records = raw.billable {
            // The endpoint can return the tail of the previous period too; keep the latest one.
            let period = records.map { $0.BillingPeriodStart ?? "" }.max() ?? ""
            let current = records.filter { ($0.BillingPeriodStart ?? "") == period }
            bill.usageUSD = round2(current.reduce(0) { $0 + ($1.ContractedCost ?? 0) })
            var lines: [String: Double] = [:]
            for record in current {
                let name = shortService(record.ServiceName ?? record.ServiceFamilyName ?? "Other")
                lines[name, default: 0] += record.ContractedCost ?? 0
            }
            bill.lineItems = moneyItems(lines)
            bill.periodStart = period.isEmpty ? nil : String(period.prefix(10))
        }
        if let credits = raw.credits, credits.has_record == true {
            bill.creditUSD = round2((credits.confirmed_balance_cents ?? 0) / 100)
        }
        if let subs = raw.subscriptions {
            bill.subsUSD = round2(subs.reduce(0) { $0 + max($1.price ?? 0, 0) })
            var plans: [String: Double] = [:]
            for sub in subs where (sub.price ?? 0) > 0 {
                var name = sub.rate_plan?.public_name ?? "Subscription"
                if let frequency = sub.frequency, !["monthly", "not-applicable"].contains(frequency) {
                    name += " (\(frequency))"
                }
                plans[name, default: 0] += sub.price ?? 0
            }
            bill.subscriptions = moneyItems(plans)
            let isPaid = subs.contains {
                ($0.rate_plan?.public_name ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "workers paid"
            }
            plan = isPaid ? .paid : .free
        }
        if let usage = bill.usageUSD {
            bill.totalUSD = round2(usage + (bill.subsUSD ?? 0))
        }
        return (bill, plan)
    }

    public static func build(account: Account, raw: RawAccountData, lastKnownPlan: Plan?, now: Date) -> AccountSnapshot {
        let (bill, knownPlan) = bill(raw.billing)
        let plan = knownPlan ?? lastKnownPlan ?? .paid
        let start = monthStart(now: now, periodStart: bill.periodStart)

        // counters[project index][field]; "day:" and "period:" prefixes keep the two windows apart.
        // The last entry is "Other": whatever matches no project, or has no known name.
        let otherIndex = account.projects.count
        var counters = Array(repeating: [String: Double](), count: account.projects.count + 1)

        func add(_ field: String, _ amount: Double, _ resource: String?) {
            var matched = false
            if let resource {
                for (index, project) in account.projects.enumerated() where project.matches(resource) {
                    counters[index][field, default: 0] += amount
                    matched = true
                }
            }
            if !matched {
                counters[otherIndex][field, default: 0] += amount
            }
        }

        let usage = raw.usage
        for row in usage.workers ?? [] {
            add("day:req", row.sum?.requests ?? 0, row.dimensions?.scriptName)
        }
        for row in usage.workersMonth ?? [] {
            add("period:req", row.sum?.requests ?? 0, row.dimensions?.scriptName)
        }
        for (rows, window) in [(usage.d1, "day"), (usage.d1Month, "period")] {
            for row in rows ?? [] {
                let name = row.dimensions?.databaseId.flatMap { raw.names.d1[$0] }
                add("\(window):d1_read", row.sum?.rowsRead ?? 0, name)
                add("\(window):d1_written", row.sum?.rowsWritten ?? 0, name)
            }
        }
        for (rows, window) in [(usage.kv, "day"), (usage.kvMonth, "period")] {
            for row in rows ?? [] {
                add("\(window):kv_read", row.sum?.requests ?? 0, row.dimensions?.namespaceId.flatMap { raw.names.kv[$0] })
            }
        }
        for (rows, window) in [(usage.durableObjects, "day"), (usage.durableObjectsMonth, "period")] {
            for row in rows ?? [] {
                add("\(window):do_req", row.sum?.requests ?? 0,
                    row.dimensions?.namespaceId.flatMap { raw.names.durableObjects[$0] })
            }
        }
        for row in usage.r2Ops ?? [] {
            let action = row.dimensions?.actionType ?? ""
            let count = row.sum?.requests ?? 0
            if r2ClassA.contains(action) {
                add("period:r2_a", count, row.dimensions?.bucketName)
            } else if r2ClassB.contains(action) {
                add("period:r2_b", count, row.dimensions?.bucketName)
            }
            // Deletes are free; action types not on the pricing page are not counted.
        }
        // Keep the newest storage sample per bucket.
        var newest: [String: (datetime: String, bytes: Double)] = [:]
        for row in usage.r2Storage ?? [] {
            guard let bucket = row.dimensions?.bucketName else { continue }
            let datetime = row.dimensions?.datetime ?? ""
            if let seen = newest[bucket], seen.datetime >= datetime { continue }
            newest[bucket] = (datetime, row.max?.payloadSize ?? 0)
        }
        for (bucket, sample) in newest {
            add("now:r2_bytes", sample.bytes, bucket)
        }

        let workers = raw.scripts.compactMap { script -> WorkerInfo? in
            guard let name = script.id else { return nil }
            return WorkerInfo(name: name, modifiedOn: script.modified_on.flatMap(parseDate),
                              deployedFrom: script.last_deployed_from)
        }.sorted(by: newestFirst)

        let rows = PlanLimits.rows(for: plan)
        func bars(_ index: Int) -> [Bar] {
            rows.map { row -> Bar in
                let value: Double
                switch row.window {
                case .now: value = round2((counters[index]["now:r2_bytes"] ?? 0) / bytesPerGB)
                case .day: value = counters[index]["day:\(row.key)"] ?? 0
                case .period: value = counters[index]["period:\(row.key)"] ?? 0
                }
                return Bar(key: row.key, label: row.label, shortLabel: row.shortLabel, value: value,
                           limit: row.limit, limitText: row.limitText, window: row.window)
            }
        }
        let projects = account.projects.enumerated().map { index, project in
            ProjectSnapshot(name: project.name, bars: bars(index), workers: workers.filter { project.matches($0.name) })
        }
        let other = workers.filter { worker in !account.projects.contains { $0.matches(worker.name) } }

        return AccountSnapshot(accountID: account.id, name: account.name, plan: plan, bill: bill,
                               monthStart: dayFormatter().string(from: start), projects: projects,
                               otherWorkers: other, otherBars: bars(otherIndex), fetchedAt: now)
    }

    static func newestFirst(_ a: WorkerInfo, _ b: WorkerInfo) -> Bool {
        switch (a.modifiedOn, b.modifiedOn) {
        case let (x?, y?): return x != y ? x > y : a.name < b.name
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.name < b.name
        }
    }

    /// Cloudflare timestamps come with or without fractional seconds.
    public static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// Largest first; amounts that round to zero are dropped.
    static func moneyItems(_ amounts: [String: Double]) -> [MoneyItem] {
        amounts.map { MoneyItem(name: $0.key, usd: round2($0.value)) }
            .filter { $0.usd > 0 }
            .sorted { $0.usd != $1.usd ? $0.usd > $1.usd : $0.name < $1.name }
    }

    /// "Container Memory, per GiB-Second (First 25 GiB-hours included)" -> "Container Memory".
    static func shortService(_ name: String) -> String {
        let cuts = [" (", ", per "].compactMap { name.range(of: $0)?.lowerBound }
        let short = cuts.min().map { String(name[..<$0]) } ?? name
        let trimmed = short.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

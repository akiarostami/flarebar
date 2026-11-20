import Foundation

public enum Plan: String, Codable, Sendable {
    case paid, free
}

/// The period a figure covers.
public enum Window: String, Codable, Sendable {
    case day     // the current UTC day
    case period  // the billing period (or the calendar month when billing is unreadable)
    case now     // the latest sample
}

/// The shares of an allowance above which a figure turns amber, then red.
public struct Thresholds: Equatable, Sendable {
    public var warning: Double
    public var critical: Double

    public init(warning: Double, critical: Double) {
        self.warning = warning
        self.critical = critical
    }

    /// Amber above 70%, red above 90%.
    public static let standard = Thresholds(warning: 0.7, critical: 0.9)
}

public enum Severity: Int, Codable, Comparable, Sendable {
    case normal, warning, critical

    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    public init(fraction: Double, thresholds: Thresholds = .standard) {
        if fraction > thresholds.critical {
            self = .critical
        } else if fraction > thresholds.warning {
            self = .warning
        } else {
            self = .normal
        }
    }
}

/// One usage figure against its allowance.
public struct Bar: Codable, Hashable, Sendable {
    public var key: String
    public var label: String
    public var shortLabel: String
    public var value: Double
    public var limit: Double
    public var limitText: String
    public var window: Window

    public init(key: String, label: String, shortLabel: String, value: Double, limit: Double,
                limitText: String, window: Window) {
        self.key = key
        self.label = label
        self.shortLabel = shortLabel
        self.value = value
        self.limit = limit
        self.limitText = limitText
        self.window = window
    }

    /// The raw share of the allowance; can exceed 1 when over the limit.
    public var ratio: Double { limit > 0 ? value / limit : 0 }
    /// The share clamped to 0...1, for drawing.
    public var fraction: Double { min(max(ratio, 0), 1) }
    public var severity: Severity { severity(.standard) }

    public func severity(_ thresholds: Thresholds) -> Severity {
        Severity(fraction: ratio, thresholds: thresholds)
    }
}

public struct WorkerInfo: Codable, Hashable, Sendable {
    public var name: String
    public var modifiedOn: Date?
    public var deployedFrom: String?

    public init(name: String, modifiedOn: Date?, deployedFrom: String?) {
        self.name = name
        self.modifiedOn = modifiedOn
        self.deployedFrom = deployedFrom
    }
}

/// A named amount on the bill: a paid plan or a billed usage line.
public struct MoneyItem: Codable, Hashable, Sendable {
    public var name: String
    public var usd: Double

    public init(name: String, usd: Double) {
        self.name = name
        self.usd = usd
    }
}

public struct Bill: Codable, Hashable, Sendable {
    /// Metered usage so far in the billing period.
    public var usageUSD: Double?
    /// Sum of paid subscriptions.
    public var subsUSD: Double?
    public var totalUSD: Double?
    public var creditUSD: Double?
    /// First day of the billing period, YYYY-MM-DD.
    public var periodStart: String?
    /// Paid plans such as Workers Paid, largest first.
    public var subscriptions: [MoneyItem] = []
    /// Metered usage per billed line ("Container Memory", "R2 Storage"), largest first.
    public var lineItems: [MoneyItem] = []

    public init(usageUSD: Double? = nil, subsUSD: Double? = nil, totalUSD: Double? = nil,
                creditUSD: Double? = nil, periodStart: String? = nil,
                subscriptions: [MoneyItem] = [], lineItems: [MoneyItem] = []) {
        self.usageUSD = usageUSD
        self.subsUSD = subsUSD
        self.totalUSD = totalUSD
        self.creditUSD = creditUSD
        self.periodStart = periodStart
        self.subscriptions = subscriptions
        self.lineItems = lineItems
    }
}

public struct ProjectSnapshot: Codable, Hashable, Sendable {
    public var name: String
    public var bars: [Bar]
    public var workers: [WorkerInfo]

    public init(name: String, bars: [Bar], workers: [WorkerInfo]) {
        self.name = name
        self.bars = bars
        self.workers = workers
    }

    /// The bar with the highest share of its allowance; the first one wins a tie.
    public var worstBar: Bar? {
        var worst: Bar?
        for bar in bars where worst == nil || bar.ratio > worst!.ratio {
            worst = bar
        }
        return worst
    }
}

public struct AccountSnapshot: Codable, Hashable, Sendable {
    public var accountID: String
    public var name: String
    public var plan: Plan
    public var bill: Bill
    /// Start of the monthly window, YYYY-MM-DD.
    public var monthStart: String
    public var projects: [ProjectSnapshot]
    /// Workers that match no project.
    public var otherWorkers: [WorkerInfo]
    /// Usage of everything that matches no project, including resources whose name is unknown.
    public var otherBars: [Bar]
    public var fetchedAt: Date

    /// The ungrouped remainder as a project named "Other"; nil when there is nothing in it.
    public var other: ProjectSnapshot? {
        guard !otherWorkers.isEmpty || otherBars.contains(where: { $0.value > 0 }) else { return nil }
        return ProjectSnapshot(name: "Other", bars: otherBars, workers: otherWorkers)
    }

    /// The projects followed by Other, when it exists.
    public var projectsAndOther: [ProjectSnapshot] {
        projects + (other.map { [$0] } ?? [])
    }

    public init(accountID: String, name: String, plan: Plan, bill: Bill, monthStart: String,
                projects: [ProjectSnapshot], otherWorkers: [WorkerInfo], otherBars: [Bar] = [], fetchedAt: Date) {
        self.accountID = accountID
        self.name = name
        self.plan = plan
        self.bill = bill
        self.monthStart = monthStart
        self.projects = projects
        self.otherWorkers = otherWorkers
        self.otherBars = otherBars
        self.fetchedAt = fetchedAt
    }
}

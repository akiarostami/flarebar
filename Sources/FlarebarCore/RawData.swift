import Foundation

/// One account's entry in the GraphQL usage response.
public struct UsageAccount: Codable, Sendable {
    public struct Row: Codable, Sendable {
        public struct Sum: Codable, Sendable {
            public var requests: Double?
            public var rowsRead: Double?
            public var rowsWritten: Double?
        }
        public struct Max: Codable, Sendable {
            public var payloadSize: Double?
        }
        public struct Dimensions: Codable, Sendable {
            public var scriptName: String?
            public var databaseId: String?
            public var namespaceId: String?
            public var actionType: String?
            public var bucketName: String?
            public var datetime: String?
        }
        public var sum: Sum?
        public var max: Max?
        public var dimensions: Dimensions?
    }

    public var workers: [Row]?
    public var workersMonth: [Row]?
    public var d1: [Row]?
    public var d1Month: [Row]?
    public var kv: [Row]?
    public var kvMonth: [Row]?
    public var durableObjects: [Row]?
    public var durableObjectsMonth: [Row]?
    public var r2Ops: [Row]?
    public var r2Storage: [Row]?
}

/// Resource ID to name. For Durable Objects: namespace ID to the Worker script that defines it.
public struct ResourceNames: Codable, Sendable, Equatable {
    public var d1: [String: String]
    public var kv: [String: String]
    public var durableObjects: [String: String]

    public init(d1: [String: String] = [:], kv: [String: String] = [:], durableObjects: [String: String] = [:]) {
        self.d1 = d1
        self.kv = kv
        self.durableObjects = durableObjects
    }
}

public struct BillableRecord: Codable, Sendable {
    public var BillingPeriodStart: String?
    public var ContractedCost: Double?
    public var ServiceFamilyName: String?
    public var ServiceName: String?
}

public struct Credits: Codable, Sendable {
    public var has_record: Bool?
    public var confirmed_balance_cents: Double?
}

public struct Subscription: Codable, Sendable {
    public struct RatePlan: Codable, Sendable {
        public var public_name: String?
    }
    public var price: Double?
    public var frequency: String?
    public var rate_plan: RatePlan?
}

/// Each part is nil when its call failed; billing is optional.
public struct RawBilling: Sendable {
    public var billable: [BillableRecord]?
    public var credits: Credits?
    public var subscriptions: [Subscription]?

    public init(billable: [BillableRecord]? = nil, credits: Credits? = nil, subscriptions: [Subscription]? = nil) {
        self.billable = billable
        self.credits = credits
        self.subscriptions = subscriptions
    }
}

public struct RawScript: Codable, Sendable {
    /// The Worker's name.
    public var id: String?
    public var modified_on: String?
    public var last_deployed_from: String?
}

public struct RawAccountData: Sendable {
    public var usage: UsageAccount
    public var names: ResourceNames
    public var billing: RawBilling
    public var scripts: [RawScript]

    public init(usage: UsageAccount, names: ResourceNames, billing: RawBilling, scripts: [RawScript]) {
        self.usage = usage
        self.names = names
        self.billing = billing
        self.scripts = scripts
    }
}

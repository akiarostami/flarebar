import Foundation
@testable import FlarebarCore

/// Sample Cloudflare responses with invented data: Tests/Fixtures.
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // FlarebarCoreTests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("Fixtures")

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func data(_ name: String) -> Data { try! Data(contentsOf: url(name)) }

    static func json(_ name: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data(name)) as! [String: Any]
    }

    struct Result<T: Decodable>: Decodable { var result: T }

    static func result<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T {
        try! JSONDecoder().decode(Result<T>.self, from: data(name)).result
    }

    static var config: Config { try! JSONDecoder().decode(Config.self, from: data("config.json")) }
    static var account: Account { config.accounts[0] }

    static var usage: UsageAccount {
        struct Response: Decodable {
            struct DataPart: Decodable {
                struct Viewer: Decodable { var accounts: [UsageAccount] }
                var viewer: Viewer
            }
            var data: DataPart
        }
        return try! JSONDecoder().decode(Response.self, from: data("graphql_account.json")).data.viewer.accounts[0]
    }

    static var names: ResourceNames { try! JSONDecoder().decode(ResourceNames.self, from: data("names.json")) }

    static func billing(subscriptions: String? = "subscriptions_paid.json") -> RawBilling {
        RawBilling(billable: result("billable_usage.json"), credits: result("credits.json"),
                   subscriptions: subscriptions.map { result($0) })
    }

    static func raw(billing: RawBilling = billing()) -> RawAccountData {
        RawAccountData(usage: usage, names: names, billing: billing, scripts: result("scripts.json"))
    }

    static var now: Date { UsageBuilder.parseDate(json("expected.json")["now"] as! String)! }
}

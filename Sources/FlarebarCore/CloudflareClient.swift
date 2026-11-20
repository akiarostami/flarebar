import Foundation

public struct CloudflareError: LocalizedError, Equatable {
    public var message: String
    public var errorDescription: String? { message }
}

public struct VisibleAccount: Codable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Read-only calls to the Cloudflare API with one token.
public struct CloudflareClient: Sendable {
    let token: String
    let session: URLSession
    static let base = "https://api.cloudflare.com/client/v4"

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: Requests

    struct Envelope<T: Decodable>: Decodable {
        struct Info: Decodable { var total_pages: Int? }
        var result: T?
        var result_info: Info?
    }

    struct ErrorBody: Decodable {
        struct Item: Decodable {
            var message: String?
            var error_chain: [Item]?
        }
        var errors: [Item]?
    }

    func data(_ path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: Self.base + path) else {
            throw CloudflareError(message: "bad path \(path)")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("flarebar", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var messages: [String] = []
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                for item in body.errors ?? [] {
                    messages.append(item.message ?? "")
                    messages.append(contentsOf: (item.error_chain ?? []).map { $0.message ?? "" })
                }
            }
            let detail = messages.filter { !$0.isEmpty }.joined(separator: "; ")
            let shortPath = path.split(separator: "?").first.map(String.init) ?? path
            throw CloudflareError(message: "HTTP \(status) from Cloudflare \(shortPath): \(detail.isEmpty ? "no detail" : detail)")
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T? {
        try JSONDecoder().decode(Envelope<T>.self, from: await data(path)).result
    }

    /// Every item of a paginated REST list.
    func list<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> [T] {
        var items: [T] = []
        var page = 1
        while true {
            let separator = path.contains("?") ? "&" : "?"
            let envelope = try JSONDecoder().decode(
                Envelope<[T]>.self, from: await data("\(path)\(separator)page=\(page)&per_page=100"))
            items.append(contentsOf: envelope.result ?? [])
            if page >= (envelope.result_info?.total_pages ?? 1) { return items }
            page += 1
        }
    }

    // MARK: Token

    public func verifyToken() async throws {
        struct Verify: Decodable { var status: String? }
        let verify: Verify? = try await get("/user/tokens/verify")
        guard verify?.status == "active" else {
            throw CloudflareError(message: "Cloudflare says this token is not active")
        }
    }

    public func accounts() async throws -> [VisibleAccount] {
        try await list("/accounts")
    }

    // MARK: One account

    public func billing(accountID: String) async -> RawBilling {
        let base = "/accounts/\(accountID)"
        async let billable: [BillableRecord]? = try? get(base + "/billable-usage")
        async let credits: Credits? = try? get(base + "/billing/credits")
        async let subscriptions: [Subscription]? = try? get(base + "/subscriptions")
        return await RawBilling(billable: billable, credits: credits, subscriptions: subscriptions)
    }

    public func usage(accountID: String, now: Date, monthStart: Date) async throws -> UsageAccount {
        struct Response: Decodable {
            struct DataPart: Decodable {
                struct Viewer: Decodable { var accounts: [UsageAccount] }
                var viewer: Viewer
            }
            struct GraphQLError: Decodable { var message: String? }
            var data: DataPart?
            var errors: [GraphQLError]?
        }
        struct Body: Encodable {
            var query: String
            var variables: [String: String]
        }
        let body = Body(query: UsageQuery.text,
                        variables: UsageQuery.variables(accountID: accountID, now: now, monthStart: monthStart))
        let response = try JSONDecoder().decode(
            Response.self, from: await data("/graphql", body: JSONEncoder().encode(body)))
        if let errors = response.errors, !errors.isEmpty {
            throw CloudflareError(message: "GraphQL error: " + errors.map { $0.message ?? "unknown error" }.joined(separator: "; "))
        }
        guard let account = response.data?.viewer.accounts.first else {
            throw CloudflareError(message: "account not found or token has no access to it")
        }
        return account
    }

    public func scripts(accountID: String) async throws -> [RawScript] {
        try await list("/accounts/\(accountID)/workers/scripts")
    }

    public func resourceNames(accountID: String) async throws -> ResourceNames {
        struct D1: Decodable { var uuid: String; var name: String }
        struct KV: Decodable { var id: String; var title: String }
        struct DO: Decodable { var id: String; var script: String?; var name: String? }
        let base = "/accounts/\(accountID)"
        async let d1: [D1] = list(base + "/d1/database")
        async let kv: [KV] = list(base + "/storage/kv/namespaces")
        async let durable: [DO] = list(base + "/workers/durable_objects/namespaces")
        return try await ResourceNames(
            d1: Dictionary(d1.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a }),
            kv: Dictionary(kv.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a }),
            durableObjects: Dictionary(durable.map { ($0.id, $0.script ?? $0.name ?? "") }, uniquingKeysWith: { a, _ in a }))
    }

    /// Everything UsageBuilder needs for one account. Pass `cachedNames` to skip the name lookups.
    public func fetch(account: Account, cachedNames: ResourceNames?, now: Date) async throws -> RawAccountData {
        let billing = await billing(accountID: account.id)
        let periodStart = UsageBuilder.bill(billing).bill.periodStart
        let monthStart = UsageBuilder.monthStart(now: now, periodStart: periodStart)
        async let usage = usage(accountID: account.id, now: now, monthStart: monthStart)
        async let scripts = scripts(accountID: account.id)
        let names: ResourceNames
        if let cachedNames {
            names = cachedNames
        } else {
            names = try await resourceNames(accountID: account.id)
        }
        return try await RawAccountData(usage: usage, names: names, billing: billing, scripts: scripts)
    }
}

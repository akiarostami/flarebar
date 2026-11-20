import Foundation
import Testing
@testable import FlarebarCore

/// Answers requests from a table instead of the network.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let (status, data) = handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct CloudflareClientTests {
    func client(_ handler: @escaping (URLRequest) -> (Int, Data)) -> CloudflareClient {
        StubProtocol.lock.lock()
        StubProtocol.handler = handler
        StubProtocol.requests = []
        StubProtocol.lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return CloudflareClient(token: "secret-token", session: URLSession(configuration: configuration))
    }

    /// Serves the fixtures the way Cloudflare would.
    func fixtureHandler(failBilling: Bool = false) -> (URLRequest) -> (Int, Data) {
        { request in
            let path = request.url!.path
            if path.hasSuffix("/graphql") { return (200, Fixtures.data("graphql_account.json")) }
            if path.hasSuffix("/billable-usage") {
                return failBilling ? (403, Data(#"{"errors":[{"message":"no billing"}]}"#.utf8)) : (200, Fixtures.data("billable_usage.json"))
            }
            if path.hasSuffix("/billing/credits") { return failBilling ? (403, Data()) : (200, Fixtures.data("credits.json")) }
            if path.hasSuffix("/subscriptions") { return failBilling ? (403, Data()) : (200, Fixtures.data("subscriptions_paid.json")) }
            if path.hasSuffix("/workers/scripts") { return (200, Fixtures.data("scripts.json")) }
            if path.hasSuffix("/d1/database") {
                return (200, Data(#"{"result":[{"uuid":"db-shop","name":"shop-db"},{"uuid":"db-blog","name":"blog-db"}]}"#.utf8))
            }
            if path.hasSuffix("/storage/kv/namespaces") {
                return (200, Data(#"{"result":[{"id":"kv-shop","title":"shop-cache"},{"id":"kv-blog","title":"www-cache"}]}"#.utf8))
            }
            if path.hasSuffix("/durable_objects/namespaces") {
                return (200, Data(#"{"result":[{"id":"do-1","script":"shop-api","name":"Counter"}]}"#.utf8))
            }
            return (404, Data(#"{"errors":[{"message":"not found"}]}"#.utf8))
        }
    }

    @Test func fetchDecodesEverythingAndMatchesTheBuilderFixtures() async throws {
        let raw = try await client(fixtureHandler()).fetch(account: Fixtures.account, cachedNames: nil, now: Fixtures.now)
        #expect(raw.names == Fixtures.names)
        let snapshot = UsageBuilder.build(account: Fixtures.account, raw: raw, lastKnownPlan: nil, now: Fixtures.now)
        let direct = UsageBuilder.build(account: Fixtures.account, raw: Fixtures.raw(), lastKnownPlan: nil, now: Fixtures.now)
        #expect(snapshot == direct)
        let sent = StubProtocol.requests
        #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token" })
        #expect(sent.contains { $0.url!.path.hasSuffix("/graphql") && $0.httpMethod == "POST" })
    }

    @Test func cachedNamesSkipTheLookups() async throws {
        _ = try await client(fixtureHandler()).fetch(account: Fixtures.account, cachedNames: Fixtures.names, now: Fixtures.now)
        #expect(!StubProtocol.requests.contains { $0.url!.path.contains("/d1/") || $0.url!.path.contains("/kv/") })
    }

    @Test func billingFailureStillReturnsUsage() async throws {
        let raw = try await client(fixtureHandler(failBilling: true)).fetch(account: Fixtures.account, cachedNames: nil, now: Fixtures.now)
        #expect(raw.billing.billable == nil && raw.billing.credits == nil && raw.billing.subscriptions == nil)
        #expect(raw.usage.workers?.count == 5)
    }

    @Test func listFollowsPages() async throws {
        let client = client { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "page" }!.value!
            let body = #"{"result":[{"id":"acct\#(page)","name":"Account \#(page)"}],"result_info":{"total_pages":3}}"#
            return (200, Data(body.utf8))
        }
        let accounts = try await client.accounts()
        #expect(accounts.map(\.id) == ["acct1", "acct2", "acct3"])
    }

    @Test func httpErrorCarriesCloudflareMessages() async {
        let client = client { _ in
            (403, Data(#"{"errors":[{"message":"Authentication error","error_chain":[{"message":"missing permission"}]}]}"#.utf8))
        }
        await #expect(throws: CloudflareError(message: "HTTP 403 from Cloudflare /accounts: Authentication error; missing permission")) {
            _ = try await client.accounts()
        }
    }

    @Test func graphQLErrorsThrow() async {
        let client = client { _ in (200, Data(#"{"data":null,"errors":[{"message":"quota exceeded"}]}"#.utf8)) }
        await #expect(throws: CloudflareError(message: "GraphQL error: quota exceeded")) {
            _ = try await client.usage(accountID: "x", now: Fixtures.now, monthStart: Fixtures.now)
        }
    }

    @Test func inactiveTokenIsRejected() async {
        let client = client { _ in (200, Data(#"{"result":{"status":"disabled"}}"#.utf8)) }
        await #expect(throws: CloudflareError.self) { try await client.verifyToken() }
    }
}

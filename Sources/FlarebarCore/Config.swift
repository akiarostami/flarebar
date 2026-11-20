import Foundation

/// A named set of name prefixes inside one Cloudflare account.
public struct Project: Codable, Hashable, Sendable {
    public var name: String
    public var prefixes: [String]

    public init(name: String, prefixes: [String]) {
        self.name = name
        self.prefixes = prefixes
    }

    /// True when the resource name starts with one of the prefixes. Empty prefixes never match.
    public func matches(_ resource: String) -> Bool {
        prefixes.contains { !$0.isEmpty && resource.hasPrefix($0) }
    }
}

public struct Account: Codable, Hashable, Sendable {
    /// The 32-character Cloudflare account ID.
    public var id: String
    public var name: String
    public var projects: [Project]

    public init(id: String, name: String, projects: [Project] = []) {
        self.id = id
        self.name = name
        self.projects = projects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var accounts: [Account]

    public init(accounts: [Account] = []) {
        self.accounts = accounts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
    }
}

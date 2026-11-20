import Foundation
import Security

/// The Cloudflare API token, as a generic password in the login Keychain.
public struct TokenStore: Sendable {
    public let service: String
    let account = "token"

    public init(service: String = "flarebar") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        let data = Data(token.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw NSError(domain: "TokenStore", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not save the token to the Keychain: \(message)"])
        }
    }

    /// Several tokens are kept in the one item, comma-separated (a comma cannot occur in a token).
    public func readAll() -> [String] {
        (read() ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func saveAll(_ tokens: [String]) throws {
        if tokens.isEmpty {
            delete()
        } else {
            try save(tokens.joined(separator: ","))
        }
    }

    /// Deletes the item and adds it again from this app, which makes this app its owner.
    /// An item created by another program (such as the `security` tool) asks for the login
    /// password whenever this app reads it; one this app created does not.
    /// Returns false when the item could not be read, in which case nothing is changed.
    @discardableResult
    public func takeOwnership() -> Bool {
        guard let value = read() else { return false }
        delete()
        do {
            try save(value)
            return true
        } catch {
            return false
        }
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

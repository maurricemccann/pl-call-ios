import Foundation
import Security

/// One generic-password item per account. Every call blocks, so callers stay off the main thread (ConfigStore is an actor).
enum Keychain {
    struct Failure: Error, Sendable { let status: OSStatus }

    private static let service = Bundle.main.bundleIdentifier ?? "call"

    private static func item(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ data: Data, account: String) throws {
        _ = SecItemDelete(item(account) as CFDictionary)
        var add = item(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly   // read while locked, mid-call
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func load(account: String) -> Data? {
        var find = item(account)
        find[kSecReturnData as String] = true
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(find as CFDictionary, &found) == errSecSuccess else { return nil }
        return found as? Data
    }

    static func delete(account: String) {
        _ = SecItemDelete(item(account) as CFDictionary)
    }
}

import Foundation
import Security

/// Private to this app, device-only, available when unlocked. No App Group or
/// synchronizable Keychain attribute is used. Removing it does not revoke an API key.
enum EstimatorKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "Recomp") + ".estimator",
         kSecAttrAccount as String: "configuration"]
    }
    static func load() throws -> EstimatorConfiguration {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return EstimatorConfiguration() }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(EstimatorConfiguration.self, from: data)
    }
    static func save(_ config: EstimatorConfiguration) throws {
        let config = try config.normalizedForSaving()
        let attrs: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(config),
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attrs) { _, new in new }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Cannot access secure estimator settings (\(status)). Unlock your phone and try again." }
    }
}


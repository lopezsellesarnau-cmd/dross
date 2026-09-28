import Foundation
import Security

/// The user's LLM provider API keys, in the macOS Keychain — encrypted at
/// rest and scoped to this app, one item per provider. The Anthropic key
/// used to live in UserDefaults, i.e. plain text in
/// ~/Library/Preferences/<bundle>.plist, readable by any process running as
/// the user and swept into every backup.
enum KeychainStore {
    private static let service = "com.arnolop.dross"

    private static func account(_ provider: LLMProvider) -> String {
        "\(provider.rawValue)-api-key"
    }

    private static func baseQuery(_ provider: LLMProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(provider),
        ]
    }

    static func apiKey(for provider: LLMProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Store (or, with an empty/whitespace key, delete) a provider's key.
    @discardableResult
    static func setAPIKey(_ key: String, for provider: LLMProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = baseQuery(provider)
        guard !trimmed.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(trimmed.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
        // Only readable while the Mac is unlocked, never synced off this device.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// One-time move of an Anthropic key saved by older builds out of
    /// UserDefaults. The plain-text copy is deleted only once the Keychain
    /// write succeeded.
    static func migrateFromUserDefaults(key defaultsKey: String) {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: defaultsKey) else { return }
        if legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || setAPIKey(legacy, for: .anthropic) {
            defaults.removeObject(forKey: defaultsKey)
        }
    }
}

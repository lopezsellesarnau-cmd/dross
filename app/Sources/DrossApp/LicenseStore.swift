import Foundation
import Combine

/// Owns license + BYO LLM provider/key state for the UI. The source of truth is
/// the engine (`~/.dross/license`, verified by signature); this store just
/// mirrors it and drives the paywall UI. Activation/deactivation shell out to
/// the engine so the CLI and app share one license file.
@MainActor
final class LicenseStore: ObservableObject {
    @Published private(set) var status: Engine.LicenseStatus = .none
    /// Which provider the LLM pass uses. Not a secret — UserDefaults is fine.
    @Published var provider: LLMProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Engine.llmProviderDefaultsKey)
            apiKey = KeychainStore.apiKey(for: provider) ?? ""
        }
    }
    /// The selected provider's key, as stored in the Keychain. Read-only
    /// here: switching provider reloads it, and edits go through
    /// `userEditedKey` — auto-detection must react to what the user typed,
    /// never to the app reloading a key (that bounced the picker back).
    @Published private(set) var apiKey: String

    /// The user typed or pasted `key`. A key whose format names another
    /// provider (an `sk-proj-…` key while Anthropic is selected) is filed
    /// under that provider and the picker follows — a key in the wrong
    /// slot is sent to the wrong API.
    func userEditedKey(_ key: String) {
        if let detected = LLMProvider.detect(fromKey: key), detected != provider {
            // Exactly the key already filed under that provider: an echo of
            // the previous selection (e.g. the field re-sending its text right
            // after a provider switch), not a new paste — ignore it.
            if KeychainStore.apiKey(for: detected) == key.trimmingCharacters(in: .whitespacesAndNewlines) { return }
            KeychainStore.setAPIKey(key, for: detected)
            provider = detected // didSet reloads apiKey from that slot: the key just stored
            return
        }
        KeychainStore.setAPIKey(key, for: provider)
        apiKey = key
    }

    var isPro: Bool { status.valid }
    /// LLM pass can actually run only with BOTH a license and a key.
    var llmReady: Bool { isPro && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        KeychainStore.migrateFromUserDefaults(key: Engine.anthropicKeyDefaultsKey)
        Self.refileMisplacedKeys()
        let chosen = Engine.selectedProvider
        provider = chosen
        apiKey = KeychainStore.apiKey(for: chosen) ?? ""
        refresh()
    }

    /// Keys saved in the wrong provider's slot by earlier builds (the picker
    /// defaulted to Anthropic) move to the slot their format names — only
    /// when that slot is empty, so a real key is never overwritten. If the
    /// selected provider was left with nothing, follow the key.
    private static func refileMisplacedKeys() {
        for slot in LLMProvider.allCases {
            guard let key = KeychainStore.apiKey(for: slot),
                  let owner = LLMProvider.detect(fromKey: key), owner != slot,
                  KeychainStore.apiKey(for: owner) == nil,
                  KeychainStore.setAPIKey(key, for: owner)
            else { continue }
            KeychainStore.setAPIKey("", for: slot)
            if Engine.selectedProvider == slot {
                UserDefaults.standard.set(owner.rawValue, forKey: Engine.llmProviderDefaultsKey)
            }
        }
    }

    func refresh() {
        status = Engine.licenseStatus()
    }

    /// Verify + persist a key. Returns the resulting status (invalid keys are
    /// rejected by the engine and nothing is stored).
    @discardableResult
    func activate(_ key: String) -> Engine.LicenseStatus {
        let result = Engine.activateLicense(key)
        status = result
        return result
    }

    func deactivate() {
        Engine.deactivateLicense()
        refresh()
    }
}

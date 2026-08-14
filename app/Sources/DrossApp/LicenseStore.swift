import Foundation
import Combine

/// Owns license + BYO Anthropic key state for the UI. The source of truth is
/// the engine (`~/.dross/license`, verified by signature); this store just
/// mirrors it and drives the paywall UI. Activation/deactivation shell out to
/// the engine so the CLI and app share one license file.
@MainActor
final class LicenseStore: ObservableObject {
    @Published private(set) var status: Engine.LicenseStatus = .none
    @Published var anthropicKey: String {
        didSet {
            UserDefaults.standard.set(anthropicKey, forKey: Engine.anthropicKeyDefaultsKey)
        }
    }

    var isPro: Bool { status.valid }
    /// LLM pass can actually run only with BOTH a license and a key.
    var llmReady: Bool { isPro && !anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        anthropicKey = UserDefaults.standard.string(forKey: Engine.anthropicKeyDefaultsKey) ?? ""
        refresh()
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

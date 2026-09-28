import SwiftUI

/// License / Pro settings sheet. Datasheet chrome to match the rest of the app.
/// Enter a license key to unlock the LLM semantic-drift pass, plus your own
/// API key for the provider you choose (bring-your-own-key — nothing is
/// resold or proxied). Keys live in the Keychain, one per provider.
struct LicenseView: View {
    @ObservedObject var license: LicenseStore
    var onClose: () -> Void

    @State private var keyField = ""
    /// Local copy of the provider key field; pushed to the store only on user edits.
    @State private var apiKeyDraft = ""
    @FocusState private var apiKeyFocused: Bool
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            statusRow

            Divider().overlay(Theme.ink)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("LICENSE KEY")
                HStack(spacing: 8) {
                    TextField("dross-v1.…", text: $keyField)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(8)
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
                    Button("ACTIVATE") { activate() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.bone)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Theme.ink)
                }
                if license.isPro {
                    Button("Deactivate license") { license.deactivate(); message = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.rust)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("LLM PROVIDER  (BRING-YOUR-OWN KEY)")
                providerPicker
                SecureField(license.provider.keyPlaceholder, text: $apiKeyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .focused($apiKeyFocused)
                    .onAppear { apiKeyDraft = license.apiKey }
                    // User edit → store (may switch provider). Store reload
                    // (provider switch) → field. Equal values stop the loop.
                    .onChange(of: apiKeyDraft) { _, new in
                        guard new != license.apiKey else { return }
                        license.userEditedKey(new)
                        // Ignored echo → show what's actually stored again.
                        if license.apiKey != new { apiKeyDraft = license.apiKey }
                    }
                    .onChange(of: license.apiKey) { _, new in
                        if apiKeyDraft != new { apiKeyDraft = new }
                    }
                    .padding(8)
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
                Text("Required for the semantic-drift pass. Stored in your Keychain; sent only to \(license.provider.label) during a scan.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(messageIsError ? Theme.rust : Theme.ok)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("DONE") { onClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(24)
        .frame(width: 480, height: 480)
        .background(Theme.bone)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DROSS · PRO")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Theme.inkAlpha(0.55))
            Text("Unlock semantic drift")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Deterministic checks are always free. Pro adds the LLM-powered contract-drift pass.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.55))
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(license.llmReady ? Theme.ok : (license.isPro ? Theme.rust : Theme.inkAlpha(0.3)))
                .frame(width: 8, height: 8)
            if license.isPro {
                Text(license.llmReady
                     ? "PRO ACTIVE — \(license.status.email ?? "licensed")"
                     : "PRO ACTIVE — add your \(license.provider.label) key to run the LLM pass")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            } else {
                Text("FREE TIER — deterministic checks only")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    /// Datasheet-style provider buttons. Not a system segmented Picker: that
    /// follows the macOS appearance and drew white labels on this light
    /// sheet in dark mode.
    private var providerPicker: some View {
        HStack(spacing: 0) {
            ForEach(LLMProvider.allCases) { p in
                let selected = license.provider == p
                Button {
                    // Leave the key field first so it can't write its old
                    // text back into the newly selected provider.
                    apiKeyFocused = false
                    license.provider = p
                } label: {
                    Text(p.label.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(selected ? Theme.bone : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if p != LLMProvider.allCases.last {
                    Rectangle().fill(Theme.ink).frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Theme.inkAlpha(0.55))
    }

    private func activate() {
        let result = license.activate(keyField)
        if result.valid {
            message = "Activated — \(result.plan ?? "pro") for \(result.email ?? "you")."
            messageIsError = false
            keyField = ""
        } else {
            message = result.reason ?? "Invalid license key."
            messageIsError = true
        }
    }
}

import SwiftUI

/// License / Pro settings sheet. Datasheet chrome to match the rest of the app.
/// Enter a license key to unlock the LLM semantic-drift pass, plus your own
/// Anthropic API key (bring-your-own-key — nothing is resold or proxied).
struct LicenseView: View {
    @ObservedObject var license: LicenseStore
    var onClose: () -> Void

    @State private var keyField = ""
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
                fieldLabel("ANTHROPIC API KEY  (BRING-YOUR-OWN)")
                SecureField("sk-ant-…", text: $license.anthropicKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
                Text("Required for the semantic-drift pass. Stored locally; sent only to Anthropic during a scan.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.55))
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
        .frame(width: 460, height: 440)
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
                     : "PRO ACTIVE — add your Anthropic key to run the LLM pass")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            } else {
                Text("FREE TIER — deterministic checks only")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
        }
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

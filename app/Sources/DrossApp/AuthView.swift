import SwiftUI

/// Squared auth panel — same chrome language as `CodeFixPopup`.
/// Shown over Welcome; not a separate page.
struct AuthPopup: View {
    enum Mode { case signIn, createAccount }

    let mode: Mode
    var onClose: () -> Void
    var onSuccess: (String) -> Void
    var onSwitchMode: (Mode) -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?

    private let pageBackground = Theme.bone

    private var title: String {
        mode == .signIn ? "Sign in" : "Create account"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.ink).frame(height: 1)
            form
            Rectangle().fill(Theme.ink).frame(height: 1)
            footer
        }
        .background(pageBackground)
        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
        .onExitCommand(perform: onClose)
        .onChange(of: mode) { _, _ in
            error = nil
            password = ""
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Theme.bone)
            Spacer(minLength: 8)
            Text(mode == .signIn ? "LOCAL" : "NEW")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.bone.opacity(0.7))
            Button(action: onClose) {
                Text("×")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.bone)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.ink)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mode == .signIn
                 ? "Welcome back. Scans stay on this Mac."
                 : "One account. Local scans first.")
                .font(.system(size: 12, design: .default))
                .foregroundStyle(Theme.inkAlpha(0.5))
                .padding(.bottom, 8)

            Text("v1 · local stub — nothing leaves this Mac. Cloud auth later.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.35))
                .padding(.bottom, 16)

            if mode == .createAccount {
                field("NAME", text: $name, secret: false)
                    .padding(.bottom, 12)
            }
            field("EMAIL", text: $email, secret: false)
                .padding(.bottom, 12)
            field("PASSWORD", text: $password, secret: true)

            if let error {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.rust)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: {
                onSwitchMode(mode == .signIn ? .createAccount : .signIn)
            }) {
                Text(mode == .signIn ? "Create account" : "Sign in instead")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .underline(color: Theme.inkAlpha(0.22))
            }
            .buttonStyle(.plain)

            Button(action: continueLocal) {
                Text("Continue locally")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .underline(color: Theme.inkAlpha(0.22))
            }
            .buttonStyle(.plain)
            .help("Skip password — use a local profile on this Mac")

            Spacer(minLength: 4)

            Button(action: submit) {
                Text(mode == .signIn ? "Sign in" : "Create account")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(pageBackground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func continueLocal() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .createAccount, !n.isEmpty {
            onSuccess(n)
        } else if let local = email.split(separator: "@").first.map(String.init), !local.isEmpty {
            onSuccess(local)
        } else {
            onSuccess("local")
        }
    }

    private func field(_ label: String, text: Binding<String>, secret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.4))
                .tracking(0.6)
            Group {
                if secret {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
        }
    }

    private func submit() {
        error = nil
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.contains("@"), password.count >= 6 else {
            error = "Valid email + password (≥ 6)."
            return
        }
        if mode == .createAccount {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else {
                error = "Add a name."
                return
            }
            onSuccess(n)
        } else {
            onSuccess(e.split(separator: "@").first.map(String.init) ?? "there")
        }
    }
}

import SwiftUI

/// Home right rail — orient a solo builder without cluttering the folder stack.
struct HomeAssistRail: View {
    var scale: CGFloat = 1
    var onAddRepo: () -> Void

    private func f(_ base: CGFloat) -> CGFloat { base * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpecEyebrow(title: "Ship check", extra: "local", scale: scale)
            Text("Scan before you deploy")
                .font(.system(size: f(22), weight: .bold, design: .default))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .padding(.top, f(8))
            Text("Dross runs locally on the repo you pick — no PR required. Built for shipping straight to main.")
                .font(.system(size: f(11), design: .monospaced))
                .foregroundStyle(Theme.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, f(8))

            Rectangle().fill(Theme.ink).frame(height: 1)
                .padding(.vertical, f(18))

            SpecEyebrow(title: "What it catches", extra: "4", scale: scale)
            VStack(alignment: .leading, spacing: f(10)) {
                DottedRow(label: "Contract", value: "routes / auth", scale: scale)
                DottedRow(label: "Env", value: ".env.example", scale: scale)
                DottedRow(label: "Dead exports", value: "strip / delete", scale: scale)
                DottedRow(label: "Demo data", value: "placeholders", scale: scale)
            }
            .padding(.top, f(10))

            Rectangle().fill(Theme.ink).frame(height: 1)
                .padding(.vertical, f(18))

            SpecEyebrow(title: "Shortcuts", extra: nil, scale: scale)
            VStack(alignment: .leading, spacing: f(8)) {
                shortcut("Click folder", "Open last scan")
                shortcut("⌘R", "Re-scan in detail")
                shortcut("⌘↩", "Fix now")
            }
            .padding(.top, f(10))

            Spacer(minLength: f(20))

            SpecButton(title: "Add repo", kind: .solid, scale: scale, action: onAddRepo)
                .padding(.bottom, f(28))
        }
        .padding(.leading, f(16))
        .padding(.trailing, f(8))
        .padding(.top, f(4))
        .padding(.bottom, f(12))
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func shortcut(_ key: String, _ label: String) -> some View {
        HStack(spacing: f(10)) {
            Text(key)
                .font(.system(size: f(11), weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: f(72), alignment: .leading)
            Text(label)
                .font(.system(size: f(12), design: .default))
                .foregroundStyle(Theme.inkAlpha(0.5))
        }
    }
}

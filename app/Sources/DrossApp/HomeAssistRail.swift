import SwiftUI

/// Home right rail — orient a solo builder without cluttering the folder stack.
struct HomeAssistRail: View {
    var scale: CGFloat = 1
    var onAddRepo: () -> Void

    private func f(_ base: CGFloat) -> CGFloat { base * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpecEyebrow(title: "Shortcuts", extra: nil, scale: scale)
            VStack(alignment: .leading, spacing: f(12)) {
                shortcut("Click folder", "Open last scan")
                shortcut("⌘R", "Re-scan in detail")
                shortcut("⌘↩", "Fix now")
            }
            .padding(.top, f(14))

            Spacer(minLength: f(24))

            SpecButton(title: "Add repo", kind: .solid, scale: scale, action: onAddRepo)
                .padding(.bottom, f(28))
        }
        .padding(.leading, f(20))
        .padding(.trailing, f(16))
        .padding(.top, f(24))
        .padding(.bottom, f(16))
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

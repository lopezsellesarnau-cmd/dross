import SwiftUI
import AppKit

/// Final gate before home — datasheet page with one folder to open.
struct FirstRepoView: View {
    var onOpen: (String) -> Void

    private let pageBackground = Theme.bone

    var body: some View {
        VStack(spacing: 0) {
            CheckerStrip(cell: 7)
            HStack(spacing: 16) {
                Text("TYPE: SETUP / FIRST REPO")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink)
                Spacer()
                InkBadge(text: "Open")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(Theme.ink).frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                SpineLabel(text: "Choose a folder")
                    .frame(width: 36)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.ink).frame(width: 1) }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Open a repo to scan.")
                        .font(.system(size: 36, weight: .bold, design: .default))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                    Text("SCAN / FIX / VERIFY / COMMIT")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(Theme.inkAlpha(0.55))
                    Text(">>>>>>>>>>>>>>>>")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text("Tap the folder. Dross stays on this Mac — nothing leaves the machine.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    HStack {
                        Spacer(minLength: 0)
                        Button(action: { RepoPicker.present(onPicked: onOpen) }) {
                            FolderStack(
                                label: "open repo",
                                depth: 4,
                                isAdd: false,
                                scale: 1.05,
                                backgroundColor: pageBackground
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Choose a folder to scan")
                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 12)

                    HStack {
                        Text("STATUS: WAITING")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("SERIAL: FIRST-PASS")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Theme.ink)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                SpineLabel(text: "Nothing leaves this Mac")
                    .frame(width: 28)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.ink).frame(width: 1) }
            }
        }
        .background(PageGrain())
        .frame(minWidth: 720, minHeight: 560)
    }
}

#Preview {
    FirstRepoView(onOpen: { _ in })
        .frame(width: 900, height: 600)
}

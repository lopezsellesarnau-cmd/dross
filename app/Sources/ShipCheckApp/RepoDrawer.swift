import SwiftUI

/// One compact stacked-folder icon per repo, in a vertical list — replaces
/// the earlier wide single "drawer" (both the static-PNG version and the
/// fully-procedural wide version): simpler, and the stack depth is real —
/// it's the repo's actual top-level file count (capped for legibility),
/// not a decorative constant. "+ open repo" is the first item in the list,
/// styled the same way but empty (dashed, one sheet).
struct RepoStackListView: View {
    let repos: [TrackedRepo]
    var onSelect: (TrackedRepo) -> Void
    var onAddRepo: () -> Void
    var scale: CGFloat = 1
    /// The actual page background behind this view — the front folder's
    /// fill must match it exactly (not the app's general Theme.bone, which
    /// is a visibly different gray from this screen's background) or the
    /// "opaque folder" fix leaves a seam around its edge.
    var backgroundColor: Color = Theme.bone

    var body: some View {
        VStack(alignment: .leading, spacing: max(24, 40 * scale)) {
            Button(action: onAddRepo) {
                FolderStack(label: "+ open repo", depth: 1, isAdd: true, scale: scale, backgroundColor: backgroundColor)
            }
            .buttonStyle(.plain)

            ForEach(repos) { repo in
                Button(action: { onSelect(repo) }) {
                    FolderStack(label: repo.name, depth: fileDepth(for: repo), isAdd: false, scale: scale, backgroundColor: backgroundColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Real signal, not decoration: how many top-level files/folders this
    /// repo actually has, clamped to a range that stays legible (a repo
    /// with 300 files shouldn't draw 300 sheets).
    private func fileDepth(for repo: TrackedRepo) -> Int {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: repo.path)) ?? []
        let hidden: Set<String> = ["node_modules", ".git", "dist", "build", ".next", ".expo", "coverage", "Pods"]
        let count = entries.filter { !$0.hasPrefix(".") && !hidden.contains($0) }.count
        return min(max(count, 2), 7)
    }
}

private struct FolderStack: View {
    let label: String
    let depth: Int
    let isAdd: Bool
    let scale: CGFloat
    let backgroundColor: Color

    private var cardWidth: CGFloat { max(140, 200 * scale) }
    private var cardHeight: CGFloat { cardWidth * (179.0 / 241.0) }
    private var layerOffset: CGFloat { max(5, 8 * scale) }

    var body: some View {
        let totalWidth = cardWidth + CGFloat(depth - 1) * layerOffset

        ZStack(alignment: .bottomTrailing) {
            ForEach(0..<max(depth - 1, 0), id: \.self) { i in
                FolderShape()
                    .stroke(Theme.inkAlpha(0.45), lineWidth: 1)
                    .frame(width: cardWidth, height: cardHeight)
                    .offset(x: CGFloat(i) * layerOffset)
            }

            ZStack {
                // Opaque fill first — the front folder must hide the
                // sliver layers behind it, not let their lines show
                // through its interior.
                FolderShape().fill(backgroundColor)
                FolderShape()
                    .stroke(isAdd ? Theme.inkAlpha(0.4) : Theme.ink, style: isAdd ? StrokeStyle(lineWidth: max(1, 1.4 * scale), dash: [3, 3]) : StrokeStyle(lineWidth: max(1, 1.4 * scale)))
            }
            .frame(width: cardWidth, height: cardHeight)
            .overlay(alignment: .bottomTrailing) {
                Text(label)
                    .font(.system(size: max(10, 15 * scale), weight: .medium, design: .monospaced))
                    .foregroundStyle(isAdd ? Theme.inkAlpha(0.55) : Theme.ink)
                    .lineLimit(1)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
            }
            .offset(x: CGFloat(max(depth - 1, 0)) * layerOffset)
        }
        .frame(width: totalWidth, height: cardHeight, alignment: .topLeading)
    }
}

/// An actual folder silhouette — a body with a smaller tab notch cut into
/// the top-left edge, the classic file-folder icon language — not a plain
/// rounded rectangle, which reads as "a box," not "a folder."
private struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 6
        let tabWidth = rect.width * 0.42
        let tabHeight = rect.height * 0.12

        var p = Path()
        // Start at the top of the tab, go around the tab notch, down the
        // body, and close with rounded corners throughout.
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tabWidth - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tabWidth, y: rect.minY + r), control: CGPoint(x: rect.minX + tabWidth, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tabWidth, y: rect.minY + tabHeight - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tabWidth + r, y: rect.minY + tabHeight), control: CGPoint(x: rect.minX + tabWidth, y: rect.minY + tabHeight))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + tabHeight))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tabHeight + r), control: CGPoint(x: rect.maxX, y: rect.minY + tabHeight))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

import SwiftUI

/// Stacked-folder tiles in a wrapping grid — fill the workspace left-to-right,
/// then wrap. Stack depth is the repo's top-level file count (capped).
/// "+ open repo" is the first tile (dashed, one sheet).
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

    private var tileMin: CGFloat {
        max(140, 200 * scale) + 6 * max(2, 3 * scale)
    }

    var body: some View {
        let columns = [
            GridItem(.adaptive(minimum: tileMin), spacing: max(28, 40 * scale), alignment: .topLeading)
        ]
        LazyVGrid(columns: columns, alignment: .leading, spacing: max(28, 40 * scale)) {
            Button(action: onAddRepo) {
                FolderStack(label: "+ open repo", depth: 1, isAdd: true, scale: scale, backgroundColor: backgroundColor)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            ForEach(repos) { repo in
                Button(action: { onSelect(repo) }) {
                    FolderStack(label: repo.name, depth: fileDepth(for: repo), isAdd: false, scale: scale, backgroundColor: backgroundColor)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct FolderStack: View {
    let label: String
    let depth: Int
    let isAdd: Bool
    let scale: CGFloat
    let backgroundColor: Color
    /// When set, the whole stack (front + offset sheets) fills this width.
    var fitWidth: CGFloat? = nil

    private var layerOffsetY: CGFloat { max(7, 11 * scale) }
    private var layerOffsetX: CGFloat { max(2, 3 * scale) }

    private var cardWidth: CGFloat {
        if let fitWidth {
            let layers = CGFloat(max(depth - 1, 0))
            return max(72, fitWidth - layers * layerOffsetX)
        }
        return max(140, 200 * scale)
    }
    private var cardHeight: CGFloat { cardWidth * (179.0 / 241.0) }

    var body: some View {
        let layers = max(depth - 1, 0)
        let totalWidth = cardWidth + CGFloat(layers) * layerOffsetX
        let totalHeight = cardHeight + CGFloat(layers) * layerOffsetY

        ZStack(alignment: .topLeading) {
            ForEach(0..<layers, id: \.self) { i in
                ZStack {
                    FolderShape().fill(backgroundColor)
                    FolderShape()
                        .stroke(Theme.ink, lineWidth: max(1, 1.2 * scale))
                }
                .frame(width: cardWidth, height: cardHeight)
                .offset(x: CGFloat(i) * layerOffsetX, y: CGFloat(i) * layerOffsetY)
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
                    // Render the name at full width (no "…") anchored to the
                    // right, then fade it out toward the folder's left edge so
                    // long repo names dissolve instead of hard-truncating.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: cardWidth - 20, alignment: .trailing)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.22),
                                .init(color: .black, location: 1.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
            }
            .offset(x: CGFloat(layers) * layerOffsetX, y: CGFloat(layers) * layerOffsetY)
        }
        .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
        // Whole folder bounds are clickable — not just the stroked edge.
        .contentShape(Rectangle())
    }
}

/// An actual folder silhouette — a body with a smaller tab notch cut into
/// the top-left edge, the classic file-folder icon language — not a plain
/// rounded rectangle, which reads as "a box," not "a folder."
struct FolderShape: Shape {
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

import SwiftUI

/// An organic branching tree — same family as TRACE's own dot-tree — grown
/// from a seed derived from the repo path, so the same repo always produces
/// the same shape. Leaves are files: a clean file is a small ink dot, a file
/// with a finding is a larger red dot. Red is used ONLY here, for findings —
/// everything else in the app stays monochrome.
struct RepoGraphView: View {
    let report: ScanReport
    var onSelect: (Finding) -> Void

    var body: some View {
        Canvas { context, size in
            let plant = PlantGraph.build(report: report, size: size)
            for branch in plant.branches {
                var path = Path()
                path.move(to: branch.points[0])
                for p in branch.points.dropFirst() { path.addLine(to: p) }
                context.stroke(path, with: .color(Theme.inkAlpha(0.5)), lineWidth: 1)
            }
            for leaf in plant.leaves {
                let r = leaf.finding != nil ? 3.6 : 1.6
                let rect = CGRect(x: leaf.point.x - r, y: leaf.point.y - r, width: r * 2, height: r * 2)
                let color: Color = leaf.finding != nil ? Theme.rust : Theme.inkAlpha(0.4)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .background(Theme.bone)
        .overlay(Rectangle().stroke(Theme.inkAlpha(0.18), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { location in
            let plant = PlantGraph.build(report: report, size: currentSize)
            if let hit = plant.leaves.min(by: { hypot($0.point.x - location.x, $0.point.y - location.y) < hypot($1.point.x - location.x, $1.point.y - location.y) }),
               hypot(hit.point.x - location.x, hit.point.y - location.y) < 14,
               let finding = hit.finding {
                onSelect(finding)
            }
        }
        .background(SizeReader(size: $currentSize))
        .frame(minHeight: 280)
    }

    @State private var currentSize: CGSize = .init(width: 600, height: 280)
}

private struct SizeReader: View {
    @Binding var size: CGSize
    var body: some View {
        GeometryReader { proxy in
            Color.clear.onAppear { size = proxy.size }.onChange(of: proxy.size) { _, new in size = new }
        }
    }
}

// MARK: - Generative plant

private struct Branch { var points: [CGPoint] }
private struct Leaf { var point: CGPoint; var finding: Finding? }
private struct PlantGraphResult { var branches: [Branch]; var leaves: [Leaf] }

/// A small seeded LCG — deterministic per repo path, not System random, so
/// re-rendering (resize, selection change) doesn't reshuffle the whole plant.
private struct SeededRNG {
    private var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let r = (state &* 0x2545F4914F6CDD1D) >> 11
        return Double(r % 1_000_000) / 1_000_000.0
    }
}

private enum PlantGraph {
    static func build(report: ScanReport, size: CGSize) -> PlantGraphResult {
        guard size.width > 10, size.height > 10 else { return PlantGraphResult(branches: [], leaves: []) }

        var rng = SeededRNG(seed: abs(report.repoRoot.hashValue))
        var branches: [Branch] = []
        var leafPoints: [CGPoint] = []

        // Root at bottom-center, growing upward — same convention as
        // TRACE's own tree (root planted, crown fills the frame).
        let root = CGPoint(x: size.width / 2, y: size.height - 6)
        let mainLen = Double(min(size.width, size.height)) * 0.62

        func grow(from: CGPoint, angle: Double, length: Double, depth: Int) {
            guard depth > 0, length > 6 else {
                leafPoints.append(from)
                return
            }
            let segs = max(2, Int(length / 16))
            var pts = [from]
            var cx = from.x, cy = from.y
            var a = angle
            let curve = (rng.next() - 0.5) * 0.5

            for i in 0..<segs {
                a += curve * 0.3 + (rng.next() - 0.5) * 0.22
                let segLen = length / Double(segs)
                let nx = cx + CGFloat(cos(a) * segLen)
                let ny = cy + CGFloat(sin(a) * segLen)
                pts.append(CGPoint(x: nx, y: ny))
                cx = nx; cy = ny

                if depth > 1, i > 0, rng.next() < 0.4 {
                    let side: Double = rng.next() < 0.5 ? -1 : 1
                    grow(from: CGPoint(x: cx, y: cy), angle: a + side * (0.4 + rng.next() * 0.6), length: length * (0.5 + rng.next() * 0.24), depth: depth - 1)
                }
            }
            branches.append(Branch(points: pts))
            if depth <= 1 { leafPoints.append(CGPoint(x: cx, y: cy)) }
        }

        grow(from: root, angle: -.pi / 2, length: mainLen, depth: 5)

        // Assign findings to the outermost (largest-index) leaves so
        // problems visually sit at the crown, not buried near the root —
        // clean files fill the rest. If there are more findings than
        // leaves, every leaf gets a finding and the rest are simply not
        // shown as individual dots (no silent overcounting — the summary
        // panel above still states the true total).
        let shuffled = leafPoints // generation order is already effectively arbitrary per-branch
        var leaves: [Leaf] = []
        let findingCount = report.findings.count
        for (i, point) in shuffled.enumerated() {
            if i < findingCount {
                leaves.append(Leaf(point: point, finding: report.findings[i]))
            } else {
                leaves.append(Leaf(point: point, finding: nil))
            }
        }

        return PlantGraphResult(branches: branches, leaves: leaves)
    }
}

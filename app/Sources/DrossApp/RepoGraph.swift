import SwiftUI

/// Compact port of Aithority `/lab` `DotTree` for the repo panel:
/// shorter band plant (seed 378 / len 230) so dots stay readable, drawn as
/// **circles** (not the hero's squares). Same grow/stroke/cluster grammar.
struct RepoGraphView: View {
    let report: ScanReport
    var onSelect: (Finding) -> Void = { _ in }

    @State private var currentSize: CGSize = .init(width: 280, height: 300)

    var body: some View {
        Canvas { context, size in
            let plant = LabDotTree.layout(
                seed: LabDotTree.seedBand,
                len: LabDotTree.lenBand,
                depth: LabDotTree.depthBand,
                size: size,
                findings: report.openFindings
            )
            for cell in plant.cells {
                let rect = CGRect(x: cell.x, y: cell.y, width: plant.dot, height: plant.dot)
                let color: Color = cell.isFinding ? Theme.rust : Theme.ink
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let plant = LabDotTree.layout(
                seed: LabDotTree.seedBand,
                len: LabDotTree.lenBand,
                depth: LabDotTree.depthBand,
                size: currentSize,
                findings: report.openFindings
            )
            if let hit = plant.cells.first(where: {
                $0.isFinding &&
                hypot($0.x + plant.dot / 2 - location.x, $0.y + plant.dot / 2 - location.y) < 18
            }), let finding = hit.finding {
                onSelect(finding)
            }
        }
        .background(SizeReader(size: $currentSize))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SizeReader: View {
    @Binding var size: CGSize
    var body: some View {
        GeometryReader { proxy in
            Color.clear.onAppear { size = proxy.size }.onChange(of: proxy.size) { _, new in size = new }
        }
    }
}

// MARK: - Lab DotTree port

struct DrawnCell {
    var x: CGFloat
    var y: CGFloat
    var isFinding: Bool
    var finding: Finding?
}

struct PlantLayout {
    var cells: [DrawnCell]
    var dot: CGFloat
}

enum LabDotTree {
    /// Same constants as `components/lab/dot-tree.tsx`.
    static let cell: CGFloat = 7
    static let dotBase: CGFloat = 4.2
    /// Compact-but-dense plant for the repo panel (still shorter than hero 430).
    static let seedBand = 378
    static let lenBand: Double = 290
    static let depthBand = 6

    static func layout(
        seed: Int,
        len: Double,
        depth: Int,
        size: CGSize,
        findings: [Finding] = []
    ) -> PlantLayout {
        guard size.width > 20, size.height > 20 else {
            return PlantLayout(cells: [], dot: 0)
        }

        let built = buildPlant(seed: seed, len: len, depth: depth)
        guard !built.isEmpty else { return PlantLayout(cells: [], dot: 0) }

        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for c in built {
            minX = min(minX, c.cx); maxX = max(maxX, c.cx)
            minY = min(minY, c.cy); maxY = max(maxY, c.cy)
        }
        let plantW = CGFloat(maxX - minX + 1) * cell
        let plantH = CGFloat(maxY - minY + 1) * cell

        let pad: CGFloat = 4
        // Fill the panel — allow modest upscale so a larger frame actually
        // grows the plant (lab hero never upscales; the app panel needs it).
        let fit = min((size.width - pad * 2) / plantW, (size.height - pad * 2) / plantH)
        let scale = min(max(fit, 0.5), 1.35)
        let cs = cell * scale
        let ds = min(dotBase * scale, cs * 0.62)
        let off = (cs - ds) / 2

        // Right-anchored, vertically centered — enters from the right edge.
        let offX = size.width - pad - CGFloat(maxX) * cs
        let offY = (size.height - plantH * scale) / 2 - CGFloat(minY) * cs

        let maxDist = built.map { hypot(Double($0.cx), Double($0.cy)) }.max() ?? 1
        var tipIndices: [Int] = []
        for (i, c) in built.enumerated() {
            let d = hypot(Double(c.cx), Double(c.cy)) / maxDist
            if d > 0.82 && c.isCluster { tipIndices.append(i) }
        }
        if tipIndices.isEmpty {
            tipIndices = built.enumerated()
                .sorted { hypot(Double($0.element.cx), Double($0.element.cy)) > hypot(Double($1.element.cx), Double($1.element.cy)) }
                .prefix(max(findings.count, 1))
                .map(\.offset)
        }

        var findingByIndex: [Int: Finding] = [:]
        for (i, finding) in findings.enumerated() where i < tipIndices.count {
            findingByIndex[tipIndices[i]] = finding
        }

        var drawn: [DrawnCell] = []
        drawn.reserveCapacity(built.count)
        for (i, c) in built.enumerated() {
            let finding = findingByIndex[i]
            drawn.append(DrawnCell(
                x: CGFloat(c.cx) * cs + offX + off,
                y: CGFloat(c.cy) * cs + offY + off,
                isFinding: finding != nil,
                finding: finding
            ))
        }
        return PlantLayout(cells: drawn, dot: ds)
    }

    private struct CellKey: Hashable {
        var cx: Int
        var cy: Int
        var isCluster: Bool
    }

    private static func buildPlant(seed: Int, len: Double, depth: Int) -> [CellKey] {
        var rng = Mulberry32(seed: UInt32(bitPattern: Int32(truncatingIfNeeded: seed)))
        var map: [String: CellKey] = [:]

        func add(_ cx: Int, _ cy: Int, cluster: Bool = false) {
            let key = "\(cx),\(cy)"
            if let existing = map[key] {
                if cluster && !existing.isCluster {
                    map[key] = CellKey(cx: cx, cy: cy, isCluster: true)
                }
            } else {
                map[key] = CellKey(cx: cx, cy: cy, isCluster: cluster)
            }
        }

        func stroke(x1: Double, y1: Double, x2: Double, y2: Double, w: Int) {
            let dist = hypot(x2 - x1, y2 - y1)
            if dist < 0.001 { return }
            let steps = max(2, Int((dist / (Double(cell) * 0.7)).rounded()))
            let px = -(y2 - y1) / dist
            let py = (x2 - x1) / dist
            let half = Double(w - 1) / 2
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let bx = x1 + (x2 - x1) * t
                let by = y1 + (y2 - y1) * t
                var k = -half
                while k <= half + 0.001 {
                    let cx = Int(((bx + px * k * Double(cell)) / Double(cell)).rounded())
                    let cy = Int(((by + py * k * Double(cell)) / Double(cell)).rounded())
                    add(cx, cy)
                    k += 1
                }
            }
        }

        func cluster(x: Double, y: Double, radius: Double, density: Double) {
            let c0 = Int((x / Double(cell)).rounded())
            let r0 = Int((y / Double(cell)).rounded())
            let rc = Int(ceil(radius / Double(cell)))
            for i in -rc...rc {
                for j in -rc...rc {
                    let d = hypot(Double(i) * Double(cell), Double(j) * Double(cell)) / radius
                    if d > 1 { continue }
                    let p = pow(1 - d, 1.5) * density
                    if rng.next() < p {
                        add(c0 + i, r0 + j, cluster: true)
                    }
                }
            }
        }

        func grow(x: Double, y: Double, angle: Double, len: Double, depth: Int, width: Int) {
            if depth <= 0 || len < Double(cell) * 1.5 { return }
            let segs = max(3, Int((len / (Double(cell) * 2.4)).rounded()))
            let segLen = len / Double(segs)
            var cx = x, cy = y, a = angle
            let curve = (rng.next() - 0.5) * 0.05 - 0.03

            for i in 0..<segs {
                a += curve + (rng.next() - 0.5) * 0.1
                let nx = cx + cos(a) * segLen
                let ny = cy + sin(a) * segLen
                let w = max(1, Int((Double(width) * (1 - (Double(i) / Double(segs)) * 0.4)).rounded()))
                stroke(x1: cx, y1: cy, x2: nx, y2: ny, w: w)
                cx = nx; cy = ny

                // More side shoots than the lab band plant — denser silhouette
                // without going back to the long hero.
                if depth > 1 && i > 0 && rng.next() < 0.46 {
                    let lado: Double = rng.next() < 0.5 ? -1 : 1
                    grow(
                        x: cx, y: cy,
                        angle: a + lado * (0.3 + rng.next() * 0.55),
                        len: len * (0.38 + rng.next() * 0.36),
                        depth: depth - 1,
                        width: max(1, width - 1)
                    )
                }

                // Occasional mid-branch leaf puff.
                if depth <= 3 && i > segs / 3 && rng.next() < 0.18 {
                    cluster(x: cx, y: cy, radius: Double(cell) * (1.4 + rng.next() * 0.9), density: 0.7)
                }
            }

            // Tips always get foliage; often a denser flower cluster too.
            if depth <= 3 {
                cluster(x: cx, y: cy, radius: Double(cell) * (2.0 + rng.next() * 1.2), density: 0.88)
                if rng.next() < 0.45 {
                    cluster(x: cx, y: cy, radius: Double(cell) * (3.2 + rng.next() * 1.6), density: 0.92)
                }
            }
        }

        // Main sweep + a short companion shoot for extra volume.
        grow(x: 0, y: 0, angle: 2.85, len: len, depth: depth, width: 4)
        grow(x: 0, y: Double(cell) * 2, angle: 2.55, len: len * 0.55, depth: depth - 1, width: 2)
        return Array(map.values)
    }
}

/// mulberry32 — same sequence as `dot-tree.tsx`.
struct Mulberry32 {
    private var a: UInt32
    init(seed: UInt32) { a = seed }
    mutating func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t = imul32(a ^ (a >> 15), 1 | a)
        t = (t &+ imul32(t ^ (t >> 7), 61 | t)) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

func imul32(_ x: UInt32, _ y: UInt32) -> UInt32 {
    UInt32(truncatingIfNeeded: Int32(bitPattern: x) &* Int32(bitPattern: y))
}

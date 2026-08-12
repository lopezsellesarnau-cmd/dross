import SwiftUI

/// The multi-repo home screen from the Figma mock (DrossApp1).
///
/// Figma's frame is 1728pt wide; this window defaults to ~980pt. Using the
/// mock's raw point values verbatim (an earlier pass) rendered everything
/// oversized, because the SAME point size reads much bigger in a canvas
/// that's little more than half as wide. `scale` corrects for that — it's
/// the actual ratio between this window's width and the Figma frame's,
/// applied to every font size, padding, and the drawer illustration, so
/// proportions match instead of just raw numbers matching.
struct HomeView: View {
    @ObservedObject var store: RepoStore
    var onOpenRepo: (String) -> Void

    @State private var query = ""

    private let homeBackground = Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255)
    private let chartOrange = Color(red: 1, green: 0.67, blue: 0)
    private let figmaDesignWidth: CGFloat = 1728

    private var filteredRepos: [TrackedRepo] {
        guard !query.isEmpty else { return store.repos }
        return store.repos.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, max(0.45, geo.size.width / figmaDesignWidth))
            content(scale: scale)
        }
        .background(homeBackground)
        .frame(minWidth: 980, minHeight: 700)
    }

    private func content(scale: CGFloat) -> some View {
        func f(_ base: CGFloat) -> CGFloat { base * scale }

        return VStack(alignment: .leading, spacing: 0) {
            topBar(f: f)
            Text("Welcome back, Arnau.")
                .font(.system(size: f(24), weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, f(39))
                .padding(.top, f(34))
                .padding(.bottom, f(20))

            HStack(alignment: .top, spacing: f(31)) {
                sidebar(f: f)
                    .frame(width: f(300))

                VStack(alignment: .leading, spacing: f(24)) {
                    searchField(f: f)
                    ScrollView {
                        RepoStackListView(repos: filteredRepos, onSelect: { onOpenRepo($0.path) }, onAddRepo: pickFolder, scale: scale, backgroundColor: homeBackground)
                            .padding(.top, f(10))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, f(39))
            .padding(.bottom, f(28))
        }
    }

    // MARK: Top bar

    private func topBar(f: (CGFloat) -> CGFloat) -> some View {
        HStack(spacing: f(14)) {
            HalftoneMark()
                .frame(width: f(36), height: f(41))
            Text("Dross")
                .font(.system(size: f(24), weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.leading, f(8))
            Spacer()
            HStack(spacing: f(8)) {
                Text("Activity").font(.system(size: f(16), weight: .medium, design: .monospaced)).foregroundStyle(Theme.ink)
                Circle().fill(Theme.rust).frame(width: f(9), height: f(9))
            }
            .padding(.trailing, f(90))
            Text("Profile").font(.system(size: f(16), weight: .medium, design: .monospaced)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, f(39))
        .padding(.top, f(24))
    }

    // MARK: Sidebar

    private func sidebar(f: @escaping (CGFloat) -> CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Previews files")
                .font(.system(size: f(20), weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, f(20))

            Divider().overlay(Theme.inkAlpha(0.3))
                .padding(.bottom, f(18))

            if store.repos.isEmpty {
                Text("No repos yet — open one from the drawer to get started.")
                    .font(.system(size: max(10, f(11.5))))
                    .foregroundStyle(Theme.inkAlpha(0.5))
            } else {
                ForEach(Array(filteredRepos.enumerated()), id: \.element.id) { index, repo in
                    if index > 0 {
                        Divider().overlay(Theme.inkAlpha(0.3))
                            .padding(.vertical, f(18))
                    }
                    RepoFilePreview(repo: repo, f: f)
                }
            }

            Divider().overlay(Theme.inkAlpha(0.3))
                .padding(.vertical, f(18))

            codeStatusSection(f: f)
            Spacer(minLength: 0)
        }
        .padding(f(23))
        .frame(maxWidth: .infinity, minHeight: f(420), alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.ink, lineWidth: max(1, f(2))))
    }

    /// A real trend, not a per-file snapshot: every scan across every
    /// tracked repo, oldest to newest, left to right — whether the codebase
    /// is getting more dangerous (bars rising) or less (bars falling) over
    /// time. Bars stay left-aligned regardless of count, never centered.
    /// Lives inside the same panel as "Previews files," not a second box.
    private func codeStatusSection(f: @escaping (CGFloat) -> CGFloat) -> some View {
        let history = store.combinedHistory

        return VStack(alignment: .leading, spacing: f(10)) {
            Text(history.isEmpty ? "Code status: no data yet" : "Code status: \(trendLabel(history))")
                .font(.system(size: f(16), weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)

            if history.isEmpty {
                Text("Run a scan to start tracking risk over time.")
                    .font(.system(size: max(10, f(11))))
                    .foregroundStyle(Theme.inkAlpha(0.45))
            } else {
                let maxCount = CGFloat(max(1, history.map(\.findingsCount).max() ?? 1))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: f(2)) {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, snapshot in
                            let heightFraction = CGFloat(snapshot.findingsCount) / maxCount
                            Rectangle()
                                .fill(snapshot.findingsCount == 0 ? Theme.inkAlpha(0.25) : Theme.rust)
                                .frame(width: max(2, f(5)), height: max(2, heightFraction * f(80)))
                        }
                        Spacer(minLength: 0)
                    }
                    Rectangle().fill(Theme.ink).frame(height: max(1, f(1.4)))
                }
            }
        }
    }

    private func trendLabel(_ history: [ScanSnapshot]) -> String {
        guard history.count > 1 else { return "\(history.last?.findingsCount ?? 0) findings" }
        let recent = history.suffix(3).map(\.findingsCount)
        let earlier = history.dropLast(3).suffix(3).map(\.findingsCount)
        guard !earlier.isEmpty else { return "\(history.last?.findingsCount ?? 0) findings" }
        let recentAvg = Double(recent.reduce(0, +)) / Double(recent.count)
        let earlierAvg = Double(earlier.reduce(0, +)) / Double(earlier.count)
        if recentAvg > earlierAvg + 0.5 { return "rising — more findings recently" }
        if recentAvg < earlierAvg - 0.5 { return "falling — cleaner recently" }
        return "steady"
    }

    // MARK: Search

    private func searchField(f: @escaping (CGFloat) -> CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if query.isEmpty {
                Text("type")
                    .font(.system(size: f(15), weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 182 / 255, green: 182 / 255, blue: 182 / 255))
                    .padding(.horizontal, f(16))
            }
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: f(15), weight: .medium, design: .monospaced))
                .padding(.horizontal, f(16))
        }
        .frame(height: f(40))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.ink, lineWidth: max(1, f(2))))
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onOpenRepo(url.path)
        }
    }
}

// MARK: - Per-repo file preview (tree with connector lines)

private struct TreeRow {
    let depth: Int
    let text: String
    let color: Color
}

private struct RepoFilePreview: View {
    let repo: TrackedRepo
    let f: (CGFloat) -> CGFloat

    private var topLevelEntries: [String] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: repo.path)) ?? []
        let hidden: Set<String> = ["node_modules", ".git", "dist", "build", ".next", ".expo", "coverage", "Pods"]
        return Array(entries.filter { !$0.hasPrefix(".") && !hidden.contains($0) }.sorted().prefix(5))
    }

    private func finding(for entry: String) -> Finding? {
        repo.lastReport?.findings.first { $0.file == entry || $0.file.hasPrefix("\(entry)/") }
    }

    private var rows: [TreeRow] {
        var result: [TreeRow] = []
        for entry in topLevelEntries {
            result.append(TreeRow(depth: 0, text: entry, color: Theme.inkAlpha(0.8)))
            if let found = finding(for: entry) {
                result.append(TreeRow(depth: 1, text: "File error", color: Theme.rust))
                if let line = found.line {
                    result.append(TreeRow(depth: 1, text: "Line \(line) error", color: Theme.inkAlpha(0.7)))
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: f(8)) {
            Text(repo.name)
                .font(.system(size: f(15), weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            FileTreeCanvas(rows: rows, f: f)
        }
    }
}

/// Draws the tree exactly like a source-control file tree: a trunk line
/// through the top-level entries, elbow ticks out to each label, and a
/// secondary trunk+ticks for any nested "File error"/"Line N" rows.
private struct FileTreeCanvas: View {
    let rows: [TreeRow]
    let f: (CGFloat) -> CGFloat

    private var rowHeight: CGFloat { max(14, f(22)) }

    var body: some View {
        Canvas { context, _ in
            let depth0Indices = rows.indices.filter { rows[$0].depth == 0 }
            let lineColor = Theme.inkAlpha(0.35)
            let x0: CGFloat = f(8), x0Tick: CGFloat = f(22), x1: CGFloat = f(26), x1Tick: CGFloat = f(40)
            let fontSize = max(9, f(12))

            if let first = depth0Indices.first, let last = depth0Indices.last, first != last {
                var trunk = Path()
                trunk.move(to: CGPoint(x: x0, y: rowMidY(first)))
                trunk.addLine(to: CGPoint(x: x0, y: rowMidY(last)))
                context.stroke(trunk, with: .color(lineColor), lineWidth: 1)
            }
            for i in depth0Indices {
                var tick = Path()
                tick.move(to: CGPoint(x: x0, y: rowMidY(i)))
                tick.addLine(to: CGPoint(x: x0Tick, y: rowMidY(i)))
                context.stroke(tick, with: .color(lineColor), lineWidth: 1)
            }

            var i = 0
            while i < rows.count {
                if rows[i].depth == 0 {
                    var j = i + 1
                    var children: [Int] = []
                    while j < rows.count, rows[j].depth == 1 { children.append(j); j += 1 }
                    if let lastChild = children.last {
                        var childTrunk = Path()
                        childTrunk.move(to: CGPoint(x: x1, y: rowMidY(i)))
                        childTrunk.addLine(to: CGPoint(x: x1, y: rowMidY(lastChild)))
                        context.stroke(childTrunk, with: .color(lineColor), lineWidth: 1)
                        for c in children {
                            var tick = Path()
                            tick.move(to: CGPoint(x: x1, y: rowMidY(c)))
                            tick.addLine(to: CGPoint(x: x1Tick, y: rowMidY(c)))
                            context.stroke(tick, with: .color(lineColor), lineWidth: 1)
                        }
                    }
                    i = j
                } else {
                    i += 1
                }
            }

            for (idx, row) in rows.enumerated() {
                let x: CGFloat = row.depth == 0 ? x0Tick + 4 : x1Tick + 4
                let text = Text(row.text).font(.system(size: fontSize, design: .monospaced)).foregroundColor(row.color)
                context.draw(text, at: CGPoint(x: x, y: rowMidY(idx)), anchor: .leading)
            }
        }
        .frame(height: CGFloat(max(rows.count, 1)) * rowHeight)
    }

    private func rowMidY(_ index: Int) -> CGFloat {
        CGFloat(index) * rowHeight + rowHeight / 2
    }
}

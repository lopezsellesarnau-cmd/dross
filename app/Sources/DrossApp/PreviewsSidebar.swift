import SwiftUI
import AppKit

/// Full-height left rail — contemporary tech finish with present-but-quiet dots.
struct PreviewsSidebar: View {
    @ObservedObject var store: RepoStore
    var repos: [TrackedRepo]
    var scale: CGFloat
    /// Path of the repo currently open in detail — drives the folder mark
    /// in the empty band above Code status.
    var selectedPath: String? = nil
    var pageBackground: Color = Theme.bone
    var onSelectRepo: ((TrackedRepo) -> Void)? = nil

    private func f(_ base: CGFloat) -> CGFloat { base * scale }

    private var selectedRepo: TrackedRepo? {
        guard let selectedPath else { return nil }
        return repos.first { $0.path == selectedPath }
    }

    var body: some View {
        GeometryReader { geo in
            let inset = f(12)
            let innerW = max(0, geo.size.width - inset * 2)
            VStack(alignment: .leading, spacing: 0) {
                Text("Preview")
                    .font(Theme.sectionLabel(f(9.5)))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkAlpha(0.5))
                    .padding(.bottom, f(14))

                Rectangle().fill(Theme.hair).frame(height: 1)

                if repos.isEmpty {
                    Text("No repos yet.\nOpen one from the drawer.")
                        .font(.system(size: max(10, f(11)), design: .default))
                        .foregroundStyle(Theme.inkAlpha(0.45))
                        .padding(.top, f(16))
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(repos.enumerated()), id: \.element.id) { index, repo in
                                if index > 0 {
                                    Rectangle().fill(Theme.hair).frame(height: 1)
                                }
                                repoCell(repo)
                            }
                        }
                    }
                    .hideScrollChrome()
                }

                // Selected repo folder — fills the empty band above Code status.
                if let selectedRepo {
                    Spacer(minLength: f(12))
                    selectedFolder(selectedRepo, width: innerW)
                    Spacer(minLength: f(8))
                } else {
                    Spacer(minLength: 0)
                }

                Rectangle().fill(Theme.hair).frame(height: 1)
                    .padding(.top, f(8))

                codeStatusSection
                    .padding(.top, f(14))
            }
            .padding(.horizontal, inset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func selectedFolder(_ repo: TrackedRepo, width: CGFloat) -> some View {
        let depth = folderDepth(for: repo.path)
        return FolderStack(
            label: repo.name,
            depth: depth,
            isAdd: false,
            scale: scale,
            backgroundColor: pageBackground,
            fitWidth: width
        )
        .frame(maxWidth: .infinity)
        .onTapGesture {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path)
        }
        .help("Reveal in Finder")
    }

    private func folderDepth(for path: String) -> Int {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let hidden: Set<String> = ["node_modules", ".git", "dist", "build", ".next", ".expo", "coverage", "Pods"]
        let count = entries.filter { !$0.hasPrefix(".") && !hidden.contains($0) }.count
        return min(max(count, 2), 7)
    }

    private func repoCell(_ repo: TrackedRepo) -> some View {
        let findings = repo.lastReport?.openFindings ?? []
        let files = repo.lastReport?.filesScanned

        return Button {
            onSelectRepo?(repo)
        } label: {
            VStack(alignment: .leading, spacing: f(10)) {
                HStack(alignment: .firstTextBaseline) {
                    Text(repo.name)
                        .font(.system(size: f(13), weight: .semibold, design: .default))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let files {
                        Text("\(files)")
                            .font(.system(size: f(11), design: .monospaced))
                            .foregroundStyle(Theme.inkAlpha(0.35))
                    }
                }

                DotStrip(repo: repo, f: f)

                if findings.isEmpty {
                    Text(repo.lastReport == nil ? "Not scanned" : "Clear")
                        .font(.system(size: f(10), weight: .medium, design: .default))
                        .foregroundStyle(Theme.inkAlpha(0.4))
                } else {
                    Text("\(findings.count) finding\(findings.count == 1 ? "" : "s")")
                        .font(.system(size: f(10), weight: .medium, design: .default))
                        .foregroundStyle(Theme.rust)
                }

                ForEach(Array(findings.prefix(2))) { finding in
                    Text(finding.line.map { "\(finding.file):\($0)" } ?? finding.file)
                        .font(.system(size: f(10), design: .monospaced))
                        .foregroundStyle(Theme.inkAlpha(0.5))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, f(16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelectRepo == nil)
    }

    private var codeStatusSection: some View {
        let history = store.combinedHistory
        return VStack(alignment: .leading, spacing: f(12)) {
            Text(history.isEmpty ? "Code status" : "Code status · \(trendLabel(history))")
                .font(Theme.sectionLabel(f(9.5)))
                .tracking(1.4)
                .foregroundStyle(Theme.inkAlpha(0.5))

            if history.isEmpty {
                Text("No trend yet — first scan seeds the chart.")
                    .font(.system(size: max(10, f(11)), design: .default))
                    .foregroundStyle(Theme.inkAlpha(0.4))
            } else {
                let maxCount = max(1, history.map(\.findingsCount).max() ?? 1)
                HStack(alignment: .center, spacing: f(7)) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, snapshot in
                        let t = CGFloat(snapshot.findingsCount) / CGFloat(maxCount)
                        let size = max(f(7), f(7) + t * f(11))
                        Circle()
                            .fill(snapshot.findingsCount == 0 ? Theme.inkAlpha(0.22) : Theme.rust.opacity(0.45 + Double(t) * 0.5))
                            .frame(width: size, height: size)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: f(24))

                HStack {
                    Text("Older")
                        .font(.system(size: f(9), weight: .medium, design: .default))
                        .foregroundStyle(Theme.inkAlpha(0.35))
                    Spacer()
                    Text("Now")
                        .font(.system(size: f(9), weight: .medium, design: .default))
                        .foregroundStyle(Theme.inkAlpha(0.35))
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
        if recentAvg > earlierAvg + 0.5 { return "rising" }
        if recentAvg < earlierAvg - 0.5 { return "falling" }
        return "steady"
    }
}

/// Top-level file dots — a bit more presence, not decorative noise.
private struct DotStrip: View {
    let repo: TrackedRepo
    let f: (CGFloat) -> CGFloat

    private var entries: [(name: String, flagged: Bool)] {
        let fm = FileManager.default
        let list = (try? fm.contentsOfDirectory(atPath: repo.path)) ?? []
        let hidden: Set<String> = ["node_modules", ".git", "dist", "build", ".next", ".expo", "coverage", "Pods"]
        return list
            .filter { !$0.hasPrefix(".") && !hidden.contains($0) }
            .sorted()
            .prefix(12)
            .map { name in
                let flagged = repo.lastReport?.openFindings.contains { $0.file == name || $0.file.hasPrefix("\(name)/") } == true
                return (name, flagged)
            }
    }

    var body: some View {
        HStack(spacing: f(5)) {
            if entries.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    Circle().stroke(Theme.inkAlpha(0.22), lineWidth: 1)
                        .frame(width: f(7), height: f(7))
                }
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Circle()
                        .fill(entry.flagged ? Theme.rust : Theme.ink.opacity(0.85))
                        .frame(width: entry.flagged ? f(8) : f(6.5), height: entry.flagged ? f(8) : f(6.5))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

import Foundation

/// One scan's outcome at a point in time — the raw material for "is this
/// codebase getting more or less dangerous," not just its latest snapshot.
struct ScanSnapshot: Codable {
    var timestamp: Double
    var findingsCount: Int
}

struct TrackedRepo: Identifiable, Codable {
    var id: String { path }
    var name: String
    var path: String
    var lastReport: ScanReport?
    var history: [ScanSnapshot] = []
}

/// Persists the repos Dross knows about, across launches, in
/// UserDefaults (no server, no account — this is a local tool). Starts
/// empty on first run, deliberately: seeding it with fake pre-scanned repos
/// (the way the Figma mock shows Trace-app/Aithority/etc. already populated)
/// would be exactly the kind of fabricated-looking-real data this app exists
/// to catch elsewhere. A repo appears here only once you've actually opened
/// and scanned it.
final class RepoStore: ObservableObject {
    @Published var repos: [TrackedRepo] = []
    private let defaultsKey = "dross.repos.v1"

    /// Every meaningful scan across every tracked repo, oldest first —
    /// only points where the findings count moved (or the first scan).
    var combinedHistory: [ScanSnapshot] {
        repos.flatMap(\.history).sorted { $0.timestamp < $1.timestamp }
    }

    init() { load() }

    func report(for path: String) -> ScanReport? {
        repos.first(where: { $0.path == path })?.lastReport
    }

    /// Updates the cached report. Appends a history bar only when the
    /// findings count actually changes — reopening / re-scanning the same
    /// state must not invent a new "Code status" sample. When a fix lands
    /// and findings drop, the new lower bar is what charts the improvement.
    func upsert(path: String, report: ScanReport) {
        let name = (path as NSString).lastPathComponent
        let snapshot = ScanSnapshot(timestamp: report.generatedAt, findingsCount: report.openCount)
        if let idx = repos.firstIndex(where: { $0.path == path }) {
            let previousCount = repos[idx].history.last?.findingsCount
            repos[idx].lastReport = report
            if previousCount != snapshot.findingsCount {
                repos[idx].history.append(snapshot)
                if repos[idx].history.count > 30 {
                    repos[idx].history.removeFirst(repos[idx].history.count - 30)
                }
            }
        } else {
            repos.append(TrackedRepo(name: name, path: path, lastReport: report, history: [snapshot]))
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var decoded = try? JSONDecoder().decode([TrackedRepo].self, from: data) else { return }
        // Collapse consecutive duplicate findings counts left by older builds
        // that appended a bar on every open.
        for i in decoded.indices {
            decoded[i].history = Self.collapseHistory(decoded[i].history)
        }
        repos = decoded
    }

    private static func collapseHistory(_ history: [ScanSnapshot]) -> [ScanSnapshot] {
        var out: [ScanSnapshot] = []
        for snap in history {
            if out.last?.findingsCount == snap.findingsCount { continue }
            out.append(snap)
        }
        return out
    }
}

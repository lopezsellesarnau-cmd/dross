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

/// Persists the repos ShipCheck knows about, across launches, in
/// UserDefaults (no server, no account — this is a local tool). Starts
/// empty on first run, deliberately: seeding it with fake pre-scanned repos
/// (the way the Figma mock shows Trace-app/Aithority/etc. already populated)
/// would be exactly the kind of fabricated-looking-real data this app exists
/// to catch elsewhere. A repo appears here only once you've actually opened
/// and scanned it.
final class RepoStore: ObservableObject {
    @Published var repos: [TrackedRepo] = []
    private let defaultsKey = "shipcheck.repos.v1"

    /// Every scan across every tracked repo, oldest first — what "code
    /// status" actually charts now: a real trend over time, not a
    /// per-file snapshot of the last run.
    var combinedHistory: [ScanSnapshot] {
        repos.flatMap(\.history).sorted { $0.timestamp < $1.timestamp }
    }

    init() { load() }

    func upsert(path: String, report: ScanReport) {
        let name = (path as NSString).lastPathComponent
        let snapshot = ScanSnapshot(timestamp: report.generatedAt, findingsCount: report.findings.count)
        if let idx = repos.firstIndex(where: { $0.path == path }) {
            repos[idx].lastReport = report
            repos[idx].history.append(snapshot)
            if repos[idx].history.count > 30 { repos[idx].history.removeFirst(repos[idx].history.count - 30) }
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
              let decoded = try? JSONDecoder().decode([TrackedRepo].self, from: data) else { return }
        repos = decoded
    }
}

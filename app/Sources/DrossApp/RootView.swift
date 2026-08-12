import SwiftUI

/// Routes between the multi-repo home screen and the single-repo scan
/// detail view. Plain state-based routing — no NavigationStack needed for
/// two screens.
struct RootView: View {
    @StateObject private var store = RepoStore()
    @State private var openRepoPath: String?

    var body: some View {
        if let openRepoPath {
            ContentView(
                initialPath: openRepoPath,
                onBack: { self.openRepoPath = nil },
                onScanComplete: { path, report in store.upsert(path: path, report: report) }
            )
        } else {
            HomeView(store: store, onOpenRepo: { path in openRepoPath = path })
        }
    }
}

import SwiftUI

/// Routes welcome → onboarding → home → repo detail.
/// Sign in / Create account stay as popups on Welcome (not separate pages).
struct RootView: View {
    @StateObject private var store = RepoStore()
    @StateObject private var session = SessionStore()
    @State private var openRepoPath: String?

    var body: some View {
        Group {
            switch session.phase {
            case .welcome:
                WelcomeView(onAuthenticated: { session.completeSignIn(name: $0) })
            case .onboarding:
                OnboardingView(
                    name: session.displayName,
                    onFinish: { answers in
                        session.saveOnboarding(answers)
                        session.finishQuestions()
                    }
                )
            case .firstRepo:
                FirstRepoView(onOpen: { path in
                    session.completeOnboarding()
                    openRepoPath = path
                })
            case .home:
                if let openRepoPath {
                    ContentView(
                        store: store,
                        initialPath: openRepoPath,
                        onBack: { self.openRepoPath = nil },
                        onOpenAnother: { path in
                            // Force a fresh detail view even if SwiftUI would reuse the struct.
                            self.openRepoPath = nil
                            DispatchQueue.main.async { self.openRepoPath = path }
                        },
                        onScanComplete: { path, report in store.upsert(path: path, report: report) }
                    )
                    // Identity by path — without this, swapping repos can keep stale @State.
                    .id(openRepoPath)
                } else {
                    HomeView(
                        store: store,
                        displayName: session.displayName,
                        onOpenRepo: { path in openRepoPath = path }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
    }
}

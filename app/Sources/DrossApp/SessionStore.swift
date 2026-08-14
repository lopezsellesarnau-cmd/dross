import Foundation
import Combine

/// Local session gate for welcome → onboarding → home.
/// Auth UI lives as a popup on Welcome; this store only tracks signed-in state.
/// No cloud backend yet — swap later without UI churn.
final class SessionStore: ObservableObject {
    enum Phase: Equatable {
        case welcome
        case onboarding
        case firstRepo
        case home
    }

    @Published var phase: Phase
    @Published var displayName: String

    private let defaults = UserDefaults.standard
    private let signedInKey = "dross.session.signedIn"
    private let onboardedKey = "dross.session.onboarded"
    private let nameKey = "dross.session.displayName"
    private let onboardingKey = "dross.session.onboardingAnswers"

    var isSignedIn: Bool { defaults.bool(forKey: signedInKey) }
    var hasOnboarded: Bool { defaults.bool(forKey: onboardedKey) }

    init() {
        let name = defaults.string(forKey: nameKey) ?? ""
        self.displayName = name
        if defaults.bool(forKey: signedInKey) {
            self.phase = defaults.bool(forKey: onboardedKey) ? .home : .onboarding
        } else {
            self.phase = .welcome
        }
    }

    func completeSignIn(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmed.isEmpty ? "there" : trimmed
        defaults.set(true, forKey: signedInKey)
        defaults.set(displayName, forKey: nameKey)
        phase = hasOnboarded ? .home : .onboarding
    }

    func saveOnboarding(_ answers: OnboardingAnswers) {
        let payload: [String: Any] = [
            "problems": answers.problems,
            "source": answers.source,
            "building": answers.building,
        ]
        defaults.set(payload, forKey: onboardingKey)
    }

    /// After the 3 questions — show the empty folder gate next.
    func finishQuestions() {
        phase = .firstRepo
    }

    /// Empty-folder tap — onboarding fully done, enter home.
    func completeOnboarding() {
        defaults.set(true, forKey: onboardedKey)
        phase = .home
    }

    /// Dev / settings escape — reset to welcome.
    func signOut() {
        defaults.set(false, forKey: signedInKey)
        // Keep onboarded so returning users skip tutorial after re-auth
        phase = .welcome
    }

    /// Full reset including onboarding (useful while building the flow).
    func resetAll() {
        defaults.set(false, forKey: signedInKey)
        defaults.set(false, forKey: onboardedKey)
        defaults.removeObject(forKey: nameKey)
        displayName = ""
        phase = .welcome
    }
}

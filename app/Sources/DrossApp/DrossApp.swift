import SwiftUI
import AppKit

/// Dross's design is a fixed light "datasheet" (ink on bone). Without this,
/// every color macOS picks itself — field placeholders, the text cursor,
/// selection, system controls — follows the system dark mode and turns
/// white on the light panels. Colors Dross sets explicitly are unaffected.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}

@main
struct DrossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 980, height: 700)
    }
}

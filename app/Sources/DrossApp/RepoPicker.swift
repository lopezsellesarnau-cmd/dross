import AppKit

/// Shared folder picker.
///
/// Uses application-modal `runModal` (not a window sheet). Sheets attach to
/// `keyWindow`, which under SwiftUI is often wrong or already busy — that
/// looked like “Open repo does nothing.”
enum RepoPicker {
    static func present(onPicked: @escaping (String) -> Void) {
        // Defer one turn so we never present from inside a SwiftUI update.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.message = "Choose a project folder for Dross to scan"
            panel.prompt = "Open"
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }
            onPicked(url.path)
        }
    }
}

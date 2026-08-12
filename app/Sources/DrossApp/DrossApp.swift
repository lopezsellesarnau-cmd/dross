import SwiftUI

@main
struct DrossApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 980, height: 700)
    }
}

import SwiftUI

@main
struct ShipCheckApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 980, height: 700)
    }
}

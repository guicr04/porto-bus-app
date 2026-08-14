import SwiftUI

@main
struct PortoBusApp: App {
    /// The single source of app-wide services, created once and shared through
    /// the environment. Screens read it to build clients and ViewModels.
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .tint(.accentColor)
        }
    }
}

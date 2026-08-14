import SwiftUI

/// Value-typed routes for app-chrome destinations (as opposed to data-driven
/// pushes like `DeparturesRoute`, which carry their own payload). Kept small on
/// purpose — most navigation is by data value.
enum Route: Hashable {
    case settings

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .settings: SettingsView()
        }
    }
}

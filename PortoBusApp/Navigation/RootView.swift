import SwiftUI

/// Hosts the selected tab's screen with the floating bar overlaid. Each screen
/// runs in its own `NavigationStack`, so detail pushes (a stop, a line's
/// departures) keep the bar visible and never leave the tab.
///
/// v1 builds only the selected tab's content, so switching tabs resets that
/// tab's navigation stack. That's an accepted tradeoff for v1 — preserving a
/// stack per tab means keeping every screen alive (and polling) at once, which
/// this deliberately avoids.
struct RootView: View {
    @State private var selection: AppTab = .board

    var body: some View {
        // The bar floats as an overlay over the content. Each scrollable screen
        // reserves room for it with `.floatingBarInset()` applied directly to its
        // List — an inset applied out here (outside the NavigationStack) doesn't
        // reach the List inside it, so rows would render under the bar.
        content
            .overlay(alignment: .bottom) {
                FloatingTabBar(selection: $selection)
                    .padding(.bottom, 4)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .board:
            NavigationStack { BoardScreen() }
        case .lines:
            NavigationStack { LinesScreen() }
        case .map:
            NavigationStack { ComingSoonView(tab: .map, note: "Live route map with vehicle positions — needs an API endpoint that infers positions from trip_id (DESIGN.md §10.2).") }
        case .favorites:
            NavigationStack { FavoritesScreen() }
        case .info:
            NavigationStack { InfoView() }
        }
    }
}

extension View {
    /// Reserves space at the bottom of a scrollable screen for the floating tab
    /// bar, so its last row rests above the bar rather than under it. Apply to
    /// the List/ScrollView itself (inside the NavigationStack).
    func floatingBarInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 60)
        }
    }
}

/// Placeholder for the tabs that ship after v1. Honest about what's coming
/// rather than an empty screen that reads as broken.
struct ComingSoonView: View {
    let tab: AppTab
    let note: String

    var body: some View {
        ContentUnavailableView {
            Label("\(tab.title) — coming soon", systemImage: tab.systemImage)
        } description: {
            Text(note)
        }
        .navigationTitle(tab.title)
    }
}

#Preview {
    RootView()
        .environment(AppServices.preview())
}

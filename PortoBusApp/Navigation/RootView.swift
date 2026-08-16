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
            NavigationStack { MapScreen() }
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

private struct FloatingBarVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

private struct HostDrawsRouteKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the floating tab bar is overlapping this view's bottom edge.
    ///
    /// True everywhere inside a tab; false inside a sheet, which is drawn over
    /// the bar. A screen reachable from both — the line detail is, via the Map's
    /// stop sheet and via the Lines tab — cannot otherwise know whether to
    /// reserve room, and gets either clipped rows or 60pt of dead space.
    var floatingBarVisible: Bool {
        get { self[FloatingBarVisibleKey.self] }
        set { self[FloatingBarVisibleKey.self] = newValue }
    }

    /// Whether there is already a map behind this view that will draw a
    /// published route (`AppServices.route`).
    ///
    /// True inside the Map tab's stop sheet, false everywhere else. A screen
    /// that shows a route and can be reached from both — the line detail is,
    /// via the Map's sheet and via the Lines tab — would otherwise either stack
    /// a second little map on top of the real one, or show no route at all.
    var hostDrawsRoute: Bool {
        get { self[HostDrawsRouteKey.self] }
        set { self[HostDrawsRouteKey.self] = newValue }
    }
}

extension View {
    /// Reserve room for the floating bar, but only where it actually is.
    @ViewBuilder
    func floatingBarInsetIfVisible(_ visible: Bool) -> some View {
        if visible { floatingBarInset() } else { self }
    }
}

#Preview {
    RootView()
        .environment(AppServices.preview())
}

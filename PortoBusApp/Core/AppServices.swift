import Foundation
import Observation
import PortoBusKit

/// App-wide services, injected once at the root and read from the SwiftUI
/// environment. It is the *only* place that knows how to build a client from
/// settings — screens ask `services.makeClient()` and hand the result to a
/// ViewModel, so no View ever constructs a URL or touches URLSession.
@Observable
@MainActor
final class AppServices {
    let settings: AppSettings
    let location: LocationProvider
    let favorites: FavoritesStore

    /// The route the Map tab should currently be drawing, if any.
    ///
    /// It lives here rather than in `MapScreen` for one reason: the screen that
    /// *publishes* a route is inside a sheet, and a sheet is presented outside
    /// the presenting view's hierarchy — an `.environment(object)` attached
    /// halfway down the Map tab does not reliably reach it. `AppServices` is
    /// injected once at the app root, above every presentation, so it does.
    /// See `RouteOverlay` for what this is for.
    let route = RouteOverlay()

    /// When set, `makeClient()` returns this instead of a live client. Used by
    /// SwiftUI previews and tests to run screens against canned data with no
    /// server. Never set in the production app.
    private let clientOverride: PortoBusClient?

    init(
        settings: AppSettings = AppSettings(),
        location: LocationProvider = LocationProvider(),
        favorites: FavoritesStore = FavoritesStore(),
        clientOverride: PortoBusClient? = nil
    ) {
        self.settings = settings
        self.location = location
        self.favorites = favorites
        self.clientOverride = clientOverride
    }

    /// A client for the current base URL. Rebuilt on demand rather than cached,
    /// so editing the address in Settings takes effect on the next screen load
    /// with no invalidation dance. Nil when the configured URL is malformed.
    func makeClient() -> PortoBusClient? {
        if let clientOverride { return clientOverride }
        guard let url = settings.baseURL else { return nil }
        return LivePortoBusClient(baseURL: url)
    }
}

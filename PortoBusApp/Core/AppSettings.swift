import Foundation
import Observation

/// User-configurable settings, persisted to `UserDefaults`. The base URL is
/// first-class from day one (DESIGN.md §9): today it points at a LAN address,
/// and hosting the API later is a value change here, not a refactor.
@Observable
@MainActor
final class AppSettings {
    /// Where the API lives. Defaults to the iOS simulator's view of the host
    /// Mac (`127.0.0.1` reaches the Mac from the simulator). On a physical
    /// device this must be changed to the Mac's LAN IP, e.g.
    /// `http://192.168.1.20:8000`.
    var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Keys.baseURL) }
    }

    /// Walking-time budget passed to `/board` as `walk_minutes`.
    var walkMinutes: Int {
        didSet { defaults.set(walkMinutes, forKey: Keys.walkMinutes) }
    }

    /// Fallback origin used when location is denied or unavailable. Defaults to
    /// central Porto (Aliados) so the app shows *something* rather than an
    /// error the first time it runs without permission.
    var homeLat: Double {
        didSet { defaults.set(homeLat, forKey: Keys.homeLat) }
    }
    var homeLon: Double {
        didSet { defaults.set(homeLon, forKey: Keys.homeLon) }
    }

    /// Show buses you can't reach on foot (maps to `include_unreachable`).
    var showUnreachable: Bool {
        didSet { defaults.set(showUnreachable, forKey: Keys.showUnreachable) }
    }

    /// Sort the board by soonest ETA instead of by line number.
    var sortByETA: Bool {
        didSet { defaults.set(sortByETA, forKey: Keys.sortByETA) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseURLString = defaults.string(forKey: Keys.baseURL) ?? "http://127.0.0.1:8000"
        self.walkMinutes = defaults.object(forKey: Keys.walkMinutes) as? Int ?? 10
        self.homeLat = defaults.object(forKey: Keys.homeLat) as? Double ?? 41.1496
        self.homeLon = defaults.object(forKey: Keys.homeLon) as? Double ?? -8.6109
        self.showUnreachable = defaults.bool(forKey: Keys.showUnreachable)
        self.sortByETA = defaults.bool(forKey: Keys.sortByETA)
    }

    /// Parsed base URL, or nil when the string is malformed (surfaced as an
    /// `.invalidURL` error at request time so the user is told to fix Settings).
    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespaces))
    }

    private enum Keys {
        static let baseURL = "settings.baseURL"
        static let walkMinutes = "settings.walkMinutes"
        static let homeLat = "settings.homeLat"
        static let homeLon = "settings.homeLon"
        static let showUnreachable = "settings.showUnreachable"
        static let sortByETA = "settings.sortByETA"
    }
}

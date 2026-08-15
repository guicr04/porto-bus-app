import SwiftUI

/// The five destinations of the floating tab bar (DESIGN.md §5). Map is
/// present from day one but lands on a "coming soon" placeholder in v1, so the
/// navigation shell never has to be retrofitted when it ships.
///
/// No dedicated stop-search tab: search-by-name didn't earn its slot once
/// Board covers "near me" and Map (once built) covers "what's around this
/// point" — Favorites covers "the specific stop+line I check often".
enum AppTab: Int, CaseIterable, Identifiable {
    case board
    case lines
    case map
    case favorites
    case info

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .board:     "Board"
        case .lines:     "Lines"
        case .map:       "Map"
        case .favorites: "Favorites"
        case .info:      "Info"
        }
    }

    var systemImage: String {
        switch self {
        case .board:     "location.north.line.fill"
        case .lines:     "bus.fill"
        case .map:       "map.fill"
        case .favorites: "heart.fill"
        case .info:      "info"
        }
    }

    /// The centre item is visually dominant — larger and filled — mirroring the
    /// reference app, where the map is the eventual centrepiece for us too.
    var isEmphasized: Bool { self == .map }
}

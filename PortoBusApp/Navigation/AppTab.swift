import SwiftUI

/// The five destinations of the floating tab bar (DESIGN.md §5). Lines and Map
/// are present from day one but land on a "coming soon" placeholder in v1, so
/// the navigation shell never has to be retrofitted when they ship.
enum AppTab: Int, CaseIterable, Identifiable {
    case board
    case lines
    case map
    case stops
    case info

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .board: "Board"
        case .lines: "Lines"
        case .map:   "Map"
        case .stops: "Stops"
        case .info:  "Info"
        }
    }

    var systemImage: String {
        switch self {
        case .board: "location.north.line.fill"
        case .lines: "bus.fill"
        case .map:   "map.fill"
        case .stops: "mappin.and.ellipse"
        case .info:  "info"
        }
    }

    /// The centre item is visually dominant — larger and filled — mirroring the
    /// reference app, where the map is the eventual centrepiece for us too.
    var isEmphasized: Bool { self == .map }
}

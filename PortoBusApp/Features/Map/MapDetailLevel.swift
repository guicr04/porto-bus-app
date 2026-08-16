import Foundation
import PortoBusKit

/// How much a stop shows at the current zoom.
///
/// Copied from how Apple Maps handles its own transit stops, because the
/// problem is the same: 2,568 stops cannot all say the same amount at every
/// scale. Detail arrives in stages as the camera comes down, so each zoom shows
/// the most it can without becoming a wall of markers (DESIGN.md §11.1).
///
/// The thresholds are latitude span across the viewport, which is a stable
/// proxy for zoom — unlike a zoom "level", it means the same thing on every
/// device size.
enum MapDetailLevel: Int, Comparable {
    /// City-wide and beyond. Pins would be a smear, so there are none.
    case hidden
    /// District. A small coloured dot: "stops exist here", nothing more.
    case dots
    /// Neighbourhood. The mark on a badge — recognisably a bus stop.
    case marks
    /// Street. The mark plus the line numbers that stop there.
    case marksWithLines

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Widest latitude span at which each level still applies.
    static let dotsMaxSpan = 0.075          // ~8 km — the whole city
    static let marksMaxSpan = 0.020         // ~2 km — a neighbourhood
    // ~650 m. Chosen by looking, not by feel: at 0.011 the badges of adjacent
    // stops overlap into an unreadable mass downtown, and at 0.004 they sit
    // clear of each other. Porto's centre is the dense case, so it sets this.
    static let linesMaxSpan = 0.006

    static func forSpan(_ latSpan: Double) -> MapDetailLevel {
        if latSpan <= linesMaxSpan { return .marksWithLines }
        if latSpan <= marksMaxSpan { return .marks }
        if latSpan <= dotsMaxSpan { return .dots }
        return .hidden
    }

    /// Does anything get drawn at all?
    var showsStops: Bool { self > .hidden }

    /// Only the tightest level pays for line numbers — see MapViewModel for why
    /// that request is gated rather than always made.
    var showsLines: Bool { self == .marksWithLines }
}

import Foundation

/// A geographic rectangle, as the API's `?bbox=` parameter understands it.
///
/// Deliberately not `MKMapRect` or `MKCoordinateRegion`: `PortoBusKit` imports
/// no UI frameworks (DESIGN.md §2), and MapKit is a UI framework. The Map screen
/// converts its camera region into one of these at the boundary.
public struct BoundingBox: Sendable, Hashable {
    public let minLat: Double
    public let minLon: Double
    public let maxLat: Double
    public let maxLon: Double

    public init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }

    /// Build from a centre plus spans, the shape MapKit hands you.
    public init(centerLat: Double, centerLon: Double, latDelta: Double, lonDelta: Double) {
        self.init(
            minLat: centerLat - latDelta / 2,
            minLon: centerLon - lonDelta / 2,
            maxLat: centerLat + latDelta / 2,
            maxLon: centerLon + lonDelta / 2
        )
    }

    /// Grow the box by a fraction on each side.
    ///
    /// The map fetches slightly more than is visible so that a small pan reveals
    /// pins that are already loaded, instead of a blank margin that fills in a
    /// beat later.
    public func expanded(by fraction: Double) -> BoundingBox {
        let latPad = (maxLat - minLat) * fraction
        let lonPad = (maxLon - minLon) * fraction
        return BoundingBox(
            minLat: minLat - latPad,
            minLon: minLon - lonPad,
            maxLat: maxLat + latPad,
            maxLon: maxLon + lonPad
        )
    }

    /// Does this box fully contain `other`? Used to skip a refetch when the new
    /// camera region is still inside what was already loaded.
    public func contains(_ other: BoundingBox) -> Bool {
        minLat <= other.minLat && minLon <= other.minLon
            && maxLat >= other.maxLat && maxLon >= other.maxLon
    }

    /// Rough width in degrees of latitude — the map's zoom-threshold test.
    public var latSpan: Double { maxLat - minLat }
}

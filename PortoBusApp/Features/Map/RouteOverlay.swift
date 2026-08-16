import CoreLocation
import MapKit
import Observation
import SwiftUI

/// A route the Map tab should draw, published by whatever screen is currently
/// describing one.
///
/// It exists because the line detail is a *sheet over the map*, and the map it
/// wants to draw on is the one already behind it. Giving that sheet its own
/// small inline map put two maps on screen at once, the useful one hidden
/// behind the useless one. So the sheet publishes here and the Map tab renders
/// it — which is the Apple Maps arrangement, and the reason its transit cards
/// feel like part of the map rather than a page about it.
///
/// Injected only by `MapScreen`. Read it as an optional
/// (`@Environment(RouteOverlay.self) var overlay: RouteOverlay?`): it is absent
/// in the Lines tab, where there is no map behind and the screen draws its own.
@MainActor
@Observable
final class RouteOverlay {
    struct Stop: Identifiable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        /// The rider's stop.
        let isOrigin: Bool
        /// Where the line starts or ends. Filled rather than hollow, the way
        /// Apple Maps marks the ends of a transit route — they are the two
        /// stops that tell you what the line *is*.
        let isTerminus: Bool

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    /// Identifies *which* route is shown. The map re-frames when this changes
    /// and not otherwise — the publisher refreshes every 20 seconds, and a
    /// camera that snapped back on each refresh would be unusable.
    private(set) var key = ""
    private(set) var coordinates: [CLLocationCoordinate2D] = []
    private(set) var stops: [Stop] = []
    private(set) var colorHex: String?

    var isActive: Bool { !coordinates.isEmpty || !stops.isEmpty }

    func show(key: String, coordinates: [CLLocationCoordinate2D], stops: [Stop], colorHex: String?) {
        self.key = key
        self.coordinates = coordinates
        self.stops = stops
        self.colorHex = colorHex
    }

    func clear() {
        key = ""
        coordinates = []
        stops = []
        colorHex = nil
    }
}

extension MKCoordinateRegion {
    /// A region containing every point, with room to breathe.
    ///
    /// `visibleFraction` is the share of the map's height that isn't behind a
    /// sheet. At 0.55 the region is doubled and its centre pushed south, so the
    /// route lands in the strip the rider can actually see instead of being
    /// neatly centred underneath the card covering it.
    static func fitting(_ points: [CLLocationCoordinate2D], visibleFraction: Double = 1) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for p in points.dropFirst() {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }

        // A floor as well as a margin: one stop, or two adjacent ones, would
        // otherwise zoom to a span of nearly zero.
        let routeLat = max(maxLat - minLat, 0.004)
        let routeLon = max(maxLon - minLon, 0.004)
        let fraction = min(max(visibleFraction, 0.2), 1)

        let totalLat = routeLat * 1.1 / fraction
        let totalLon = routeLon * 1.1
        let centreLat = (minLat + maxLat) / 2 - (totalLat - routeLat * 1.1) / 2

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centreLat, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: totalLat, longitudeDelta: totalLon)
        )
    }
}

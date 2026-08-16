import Foundation
import Testing
@testable import PortoBusKit

/// Decoding tests run against recorded/representative JSON fixtures. They pin the
/// contract port in `Models/` to what the API actually sends — snake_case
/// conversion, nullability, the `lng` exception, and the open enums.
struct DecodingTests {

    // Shared decoder configured exactly as the live client configures it.
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "fixture \(name).json not found in test bundle"
        )
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try decoder().decode(T.self, from: fixture(name))
    }

    @Test func decodesLocationBoard() throws {
        let board = try Self.decode(LocationBoard.self, from: "board")

        #expect(board.origin.lat == 41.1496)
        #expect(board.stopsConsidered == 14)
        #expect(board.departures.count == 2)

        // stops_truncated is not in domain.d.ts but present here — captured.
        #expect(board.stopsTruncated == true)

        // A failed poll must surface, not be swallowed.
        #expect(board.hasFailedStops == true)

        let first = board.departures[0]
        #expect(first.line == "305")
        #expect(first.etaMinutes == 6)
        #expect(first.leaveInMinutes == 2)
        #expect(first.catchable == true)
        #expect(first.realtime == true)

        // The unreachable row is present in the payload; filtering is the app's job.
        let second = board.departures[1]
        #expect(second.catchable == false)
        #expect(second.leaveInMinutes == -4)
        #expect(second.delayMinutes == 5)
    }

    @Test func decodesRealtimeWithNullsAndUnknownStatus() throws {
        let stop = try Self.decode(RealtimeStop.self, from: "realtime")

        #expect(stop.stopCode == "CMO")
        #expect(stop.dataSource == "realtime")
        #expect(stop.arrivals.count == 2)

        let known = stop.arrivals[0]
        #expect(known.arrivalMinutes == 6)
        #expect(known.statusValue == .onTime)
        // Regression: delay_minutes is a fractional upstream `number` (0.8), not
        // an Int. Decoding it into Int once broke the whole board decode.
        #expect(known.delayMinutes == 0.8)

        // Every optional actually null in the wild must decode to nil, never a
        // defaulted zero — a fabricated "0 min" would be a lie on the board.
        let sparse = stop.arrivals[1]
        #expect(sparse.arrivalMinutes == nil)
        #expect(sparse.estimatedArrivalTime == nil)
        #expect(sparse.delayMinutes == nil)
        #expect(sparse.color == nil)
        #expect(sparse.tripId == nil)

        // An unrecognised status decodes (as raw) rather than throwing…
        #expect(sparse.status == "SURPRISE_STATUS")
        // …but has no typed value.
        #expect(sparse.statusValue == nil)
    }

    @Test func decodesCombinedDeparturesPreservingSource() throws {
        let payload = try Self.decode(StopLineDepartures.self, from: "departures")

        #expect(payload.serviceId == "DOM|FERIADO:FLUXO 3.1 20260718")
        #expect(payload.departures.count == 3)

        // The source tag drives two distinct UI treatments — it must round-trip.
        #expect(payload.departures[0].source == .realtime)
        #expect(payload.departures[0].source.isRealtime == true)
        #expect(payload.departures[1].source == .scheduled)
        #expect(payload.departures[1].source.isRealtime == false)

        // An unknown source degrades to .unknown rather than failing the list.
        #expect(payload.departures[2].source == .unknown("some_future_source"))
        #expect(payload.departures[2].etaMinutes == nil)
    }

    @Test func decodesShapeWithLngKey() throws {
        // The one field snake_case conversion does not rename. If the explicit
        // CodingKey ever regresses, this throws.
        let shape = try Self.decode(RouteShape.self, from: "shape")
        #expect(shape.coordinates.count == 3)
        #expect(shape.coordinates[0].lng == -8.6109)
        #expect(shape.coordinates[2].sequence == 2)
    }

    // MARK: - /trips/{trip_id}/stops

    @Test func decodesAResolvedTrip() throws {
        let trip = try Self.decode(ResolvedTrip.self, from: "trip-stops")

        // The live id and the store's differ by exactly the feed-version field;
        // both must survive the round trip, because the mismatch is the thing
        // worth being able to see when this screen misbehaves.
        #expect(trip.requestedTripId == "900_0_1|280|D3|T1|N5")
        #expect(trip.tripId == "900_0_1|276|D3|T1|N5")
        #expect(trip.match == .version)
        #expect(trip.line == "900")
        #expect(trip.headsign == "Francelos")
        #expect(trip.directionId == 0)
        #expect(trip.stops.count == 5)

        // The feed this fixture came from was past its validity window. Not an
        // error — but the app must be able to tell.
        #expect(trip.feedExpired == true)

        let carmo = try #require(trip.stops.first { $0.stopCode == "CMO" })
        #expect(carmo.stopSequence == 2)
        #expect(carmo.arrivalSeconds == 32775)
        #expect(carmo.timepoint == false)
        #expect(trip.stops[0].timepoint == true)
    }

    @Test func downstreamProjectsFromTheLiveETAOnly() throws {
        let trip = try Self.decode(ResolvedTrip.self, from: "trip-stops")

        // The bus is 6 minutes from CARMO. Everything after that is the live
        // number plus a timetable gap — 32905 - 32775 = 130s to the next stop.
        let after = trip.downstream(from: "CMO", liveEtaMinutes: 6)
        #expect(after.map(\.stop.stopCode) == ["HSA1", "PAL6", "EQ4"])
        #expect(abs(after[0].etaMinutes - (6 + 130.0 / 60)) < 1e-9)
        #expect(abs(after[2].etaMinutes - (6 + 350.0 / 60)) < 1e-9)

        // Nothing runs before the rider's own stop.
        #expect(!after.contains { $0.stop.stopCode == "CORD5" })
    }

    @Test func downstreamIsEmptyOffTheEndsOfTheTrip() throws {
        let trip = try Self.decode(ResolvedTrip.self, from: "trip-stops")
        // A stop this bus does not call at, and its terminus: both mean "there
        // is nothing after here", and neither may crash or invent a row.
        #expect(trip.downstream(from: "NOPE", liveEtaMinutes: 6).isEmpty)
        #expect(trip.downstream(from: "EQ4", liveEtaMinutes: 6).isEmpty)
    }

    @Test func anUnknownMatchDecodesRatherThanFailing() throws {
        // A rung added server-side must not take the whole screen down.
        let json = Data(#"""
        {"trip_id":"T","requested_trip_id":"T","match":"telepathy","route_id":"R",
         "line":"1","color":null,"text_color":null,"headsign":null,"direction_id":null,
         "service_id":"S","shape_id":null,"feed_expired":false,"stops":[]}
        """#.utf8)
        let trip = try Self.decoder().decode(ResolvedTrip.self, from: json)
        #expect(trip.match == .unknown("telepathy"))
        #expect(trip.match.isCertain == false)
    }

    @Test func matchConfidenceSeparatesIdsFromGuesses() {
        #expect(TripMatch.exact.isCertain)
        #expect(TripMatch.version.isCertain)
        // These two identified the bus by inference, not by its id.
        #expect(!TripMatch.versionLatest.isCertain)
        #expect(!TripMatch.pattern.isCertain)
    }

    @Test func decodesStopsWithNullCoordinates() throws {
        let stops = try Self.decode([Stop].self, from: "stops")
        #expect(stops.count == 2)
        #expect(stops[0].stopCode == "CMO")
        #expect(stops[1].lat == nil)
        #expect(stops[1].lon == nil)
    }
}

// MARK: - Bounding boxes

@Suite struct BoundingBoxTests {
    @Test func expandingGrowsEverySide() {
        let box = BoundingBox(minLat: 0, minLon: 0, maxLat: 10, maxLon: 20)
        let bigger = box.expanded(by: 0.1)
        #expect(bigger.minLat == -1)
        #expect(bigger.maxLat == 11)
        #expect(bigger.minLon == -2)
        #expect(bigger.maxLon == 22)
    }

    @Test func containsIsTrueOnlyWhenFullyEnclosed() {
        let loaded = BoundingBox(minLat: 0, minLon: 0, maxLat: 10, maxLon: 10)
        #expect(loaded.contains(BoundingBox(minLat: 1, minLon: 1, maxLat: 9, maxLon: 9)))
        #expect(loaded.contains(loaded))
        // Panned off the edge: must refetch, not reuse.
        #expect(!loaded.contains(BoundingBox(minLat: 1, minLon: 1, maxLat: 9, maxLon: 11)))
    }

    @Test func centreAndSpanBuildsASymmetricBox() {
        let box = BoundingBox(centerLat: 41.15, centerLon: -8.61, latDelta: 0.02, lonDelta: 0.04)
        #expect(abs(box.minLat - 41.14) < 1e-9)
        #expect(abs(box.maxLat - 41.16) < 1e-9)
        #expect(abs(box.minLon - -8.63) < 1e-9)
        #expect(abs(box.maxLon - -8.59) < 1e-9)
        #expect(abs(box.latSpan - 0.02) < 1e-9)
    }
}

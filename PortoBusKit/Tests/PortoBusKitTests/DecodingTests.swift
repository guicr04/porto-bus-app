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

    @Test func decodesStopsWithNullCoordinates() throws {
        let stops = try Self.decode([Stop].self, from: "stops")
        #expect(stops.count == 2)
        #expect(stops[0].stopCode == "CMO")
        #expect(stops[1].lat == nil)
        #expect(stops[1].lon == nil)
    }
}

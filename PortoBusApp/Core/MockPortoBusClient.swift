#if DEBUG
import Foundation
import PortoBusKit

/// An in-memory client returning canned data, for SwiftUI previews and future
/// ViewModel tests. The design requires the client to be a protocol precisely so
/// screens can run with no server (DESIGN.md §4). Only compiled in DEBUG.
struct MockPortoBusClient: PortoBusClient {
    var boardResult: LocationBoard = .preview
    var stopsResult: [Stop] = Stop.previews
    var realtimeResult: RealtimeStop = .preview
    var departuresResult: StopLineDepartures = .preview
    var linesResult: [Line] = Line.previews
    var lineStopsResult: RouteDirectionStops = .preview
    var lineShapeResult: RouteShape = .preview
    var tripStopsResult: ResolvedTrip = .preview
    /// When set, every call throws this instead of returning — for error-state previews.
    var error: APIError?

    private func result<T>(_ value: T) throws -> T {
        if let error { throw error }
        return value
    }

    func board(lat: Double, lon: Double, walkMinutes: Int?, sort: BoardSort?, includeUnreachable: Bool) async throws -> LocationBoard {
        try result(boardResult)
    }
    func stops(query: String?, limit: Int?) async throws -> [Stop] {
        try result(query.map { q in stopsResult.filter { $0.name.localizedCaseInsensitiveContains(q) } } ?? stopsResult)
    }
    /// Filters the canned stops by the box, so a preview of the Map behaves like
    /// the real thing — pan away from the sample stops and they disappear.
    func stops(bbox: BoundingBox) async throws -> [Stop] {
        try result(stopsResult.filter { stop in
            guard let lat = stop.lat, let lon = stop.lon else { return false }
            return lat >= bbox.minLat && lat <= bbox.maxLat && lon >= bbox.minLon && lon <= bbox.maxLon
        })
    }
    /// Every canned stop gets the same two lines — enough for a preview of the
    /// street-zoom labels without inventing a fake network.
    func stopLines(bbox: BoundingBox) async throws -> [StopLines] {
        try result(stopsResult.map {
            StopLines(stopCode: $0.stopCode, lines: [
                StopLine(line: "500", color: "#187EC2", textColor: "#FFFFFF"),
                StopLine(line: "203", color: "#C2185B", textColor: "#FFFFFF"),
            ])
        })
    }
    func stop(code: String) async throws -> Stop { try result(stopsResult.first { $0.stopCode == code } ?? stopsResult[0]) }
    func realtime(stop code: String) async throws -> RealtimeStop { try result(realtimeResult) }
    func stopRoutes(stop code: String) async throws -> StopRoutes { try result(StopRoutes(routes: [], directions: [])) }
    func stopServices(stop code: String, date: String?) async throws -> StopServices {
        try result(StopServices(services: [], activeServiceId: nil, selectedDate: nil, today: nil))
    }
    func departures(stop code: String, line: String, serviceId: String?, directionId: Int?, windowMinutes: Int?, limit: Int?) async throws -> StopLineDepartures {
        try result(departuresResult)
    }
    func stopSchedule(stop code: String, routeId: String, serviceId: String, directionId: Int) async throws -> StopSchedule {
        try result(StopSchedule(stopCode: code, routeId: routeId, directionId: directionId, serviceId: serviceId, departures: []))
    }
    func lines() async throws -> [Line] { try result(linesResult) }
    func lineStops(line: String, directionId: Int) async throws -> RouteDirectionStops {
        try result(lineStopsResult)
    }
    func lineShape(line: String, directionId: Int) async throws -> RouteShape {
        try result(lineShapeResult)
    }
    func lineServices(line: String, date: String?) async throws -> RouteServices {
        try result(RouteServices(routeId: line, services: [], activeServiceId: nil, selectedDate: nil, today: nil))
    }
    func lineSchedule(line: String, serviceId: String, directionId: Int) async throws -> RouteSchedule {
        try result(RouteSchedule(routeId: line, serviceId: serviceId, directionId: directionId, timepointStops: [], trips: []))
    }
    func tripStops(tripId: String?, line: String?, headsign: String?, stop: String?, etaMinutes: Int?) async throws -> ResolvedTrip {
        try result(tripStopsResult)
    }
}

extension AppServices {
    /// AppServices wired to the mock client, for previews.
    static func preview(client: MockPortoBusClient = MockPortoBusClient()) -> AppServices {
        AppServices(clientOverride: client)
    }
}

// MARK: - Canned data

extension LocationBoard {
    static let preview = LocationBoard(
        origin: .init(lat: 41.1496, lon: -8.6109),
        walkMinutes: 10,
        generatedAt: "2026-08-13T16:14:00+01:00",
        stopsConsidered: 8,
        stopsPolled: [
            PolledStop(stopCode: "CMO", name: "CARMO", distanceMeters: 180, walkMinutes: 4, ok: true),
        ],
        departures: [
            BoardRow(line: "305", destination: "Cordoaria", realtime: true, dataSource: "realtime", stopCode: "CMO", stopName: "CARMO", walkMinutes: 4, distanceMeters: 180, etaMinutes: 6, leaveInMinutes: 2, catchable: true, status: "ON_TIME", delayMinutes: 0, color: "#417DBD", textColor: "#FFFFFF"),
            BoardRow(line: "300", destination: "Aliados - H.S.João", realtime: true, dataSource: "realtime", stopCode: "CMO", stopName: "CARMO", walkMinutes: 4, distanceMeters: 180, etaMinutes: 12, leaveInMinutes: 8, catchable: true, status: "DELAYED", delayMinutes: 5, color: "#417DBD", textColor: "#FFFFFF"),
            BoardRow(line: "701", destination: "Codiceira", realtime: false, dataSource: "scheduled", stopCode: "COR", stopName: "CORDOARIA", walkMinutes: 6, distanceMeters: 420, etaMinutes: 0, leaveInMinutes: -6, catchable: true, status: nil, delayMinutes: nil, color: "#E8A200", textColor: "#000000"),
        ],
        stopsTruncated: false
    )
}

extension Stop {
    static let previews = [
        Stop(stopCode: "CMO", name: "CARMO", lat: 41.1496, lon: -8.6109),
        Stop(stopCode: "BOLH", name: "BOLHÃO", lat: 41.1503, lon: -8.6074),
        Stop(stopCode: "COR", name: "CORDOARIA", lat: 41.1465, lon: -8.6155),
    ]
}

extension RealtimeStop {
    // Several buses per line, and one line with no live tracking at all — the
    // grouped stop sheet (DESIGN.md §11.1) has three distinct cases to render
    // and a flat two-row board would exercise none of them.
    static let preview = RealtimeStop(
        stopCode: "CMO", stopName: "CARMO", arrivals: [
            Arrival(line: "305", destination: "Cordoaria", arrivalMinutes: 6, estimatedArrivalTime: nil, scheduledArrivalTime: nil, status: "ON_TIME", delayMinutes: 0, color: "#417DBD", textColor: "#FFFFFF", tripId: "305_0_1|280|D3|T1|N6"),
            Arrival(line: "300", destination: "Aliados", arrivalMinutes: 12, estimatedArrivalTime: nil, scheduledArrivalTime: nil, status: "DELAYED", delayMinutes: 5, color: "#417DBD", textColor: "#FFFFFF", tripId: "300_0_1|280|D3|T1|N2"),
            Arrival(line: "305", destination: "Cordoaria", arrivalMinutes: 21, estimatedArrivalTime: nil, scheduledArrivalTime: nil, status: "ON_TIME", delayMinutes: 0, color: "#417DBD", textColor: "#FFFFFF", tripId: "305_0_1|280|D3|T1|N8"),
            Arrival(line: "701", destination: "Codiceira", arrivalMinutes: 14, estimatedArrivalTime: nil, scheduledArrivalTime: "16:28", status: nil, delayMinutes: nil, color: "#FF0000", textColor: "#FFFFFF", tripId: nil),
            Arrival(line: "300", destination: "Aliados", arrivalMinutes: 27, estimatedArrivalTime: nil, scheduledArrivalTime: nil, status: "ON_TIME", delayMinutes: 0, color: "#417DBD", textColor: "#FFFFFF", tripId: "300_0_1|280|D3|T1|N4"),
        ], lastUpdated: nil, dataSource: "realtime")
}

extension RouteShape {
    // A few real points along Rua do Carmo / Cordoaria — enough for the line
    // detail's polyline to be visibly a road rather than a straight hop.
    static let preview = RouteShape(
        routeId: "305", directionId: 0,
        coordinates: [
            ShapePoint(lat: 41.1496, lng: -8.6109, sequence: 1),
            ShapePoint(lat: 41.1489, lng: -8.6131, sequence: 2),
            ShapePoint(lat: 41.1471, lng: -8.6148, sequence: 3),
            ShapePoint(lat: 41.1465, lng: -8.6155, sequence: 4),
            ShapePoint(lat: 41.1502, lng: -8.6203, sequence: 5),
        ])
}

extension ResolvedTrip {
    static let preview = ResolvedTrip(
        tripId: "305_0_1|276|D3|T1|N6",
        requestedTripId: "305_0_1|280|D3|T1|N6",
        match: .version,
        routeId: "305",
        line: "305",
        color: "#417DBD",
        textColor: "#FFFFFF",
        headsign: "Cordoaria",
        directionId: 0,
        serviceId: "SABADO:Fluxo 3 20260801",
        shapeId: "SH305",
        feedExpired: false,
        stops: [
            ResolvedTripStop(stopSequence: 1, stopId: "BOLH", stopCode: "BOLH", stopName: "BOLHÃO", stopLat: 41.1503, stopLon: -8.6074, arrivalTime: "16:14:00", departureTime: "16:14:00", arrivalSeconds: 58440, departureSeconds: 58440, timepoint: true),
            ResolvedTripStop(stopSequence: 2, stopId: "CMO", stopCode: "CMO", stopName: "CARMO", stopLat: 41.1496, stopLon: -8.6109, arrivalTime: "16:20:00", departureTime: "16:20:00", arrivalSeconds: 58800, departureSeconds: 58800, timepoint: false),
            ResolvedTripStop(stopSequence: 3, stopId: "HSA5", stopCode: "HSA5", stopName: "HOSP. ST. ANTÓNIO", stopLat: 41.1489, stopLon: -8.6131, arrivalTime: "16:22:00", departureTime: "16:22:00", arrivalSeconds: 58920, departureSeconds: 58920, timepoint: false),
            ResolvedTripStop(stopSequence: 4, stopId: "COR", stopCode: "COR", stopName: "CORDOARIA", stopLat: 41.1465, stopLon: -8.6155, arrivalTime: "16:25:00", departureTime: "16:25:00", arrivalSeconds: 59100, departureSeconds: 59100, timepoint: true),
            ResolvedTripStop(stopSequence: 5, stopId: "PRG1", stopCode: "PRG1", stopName: "PR. DA GALIZA", stopLat: 41.1502, stopLon: -8.6203, arrivalTime: "16:31:00", departureTime: "16:31:00", arrivalSeconds: 59460, departureSeconds: 59460, timepoint: true),
        ])
}

extension StopLineDepartures {
    static let preview = StopLineDepartures(
        stopCode: "CMO", line: "300", directionId: 0, serviceId: "DOM|FERIADO:FLUXO 3.1 20260718",
        generatedAt: "2026-08-13T16:14:00+01:00",
        departures: [
            CombinedDeparture(line: "300", destination: "Aliados", source: .realtime, etaMinutes: 3, time: "16:17", status: "DELAYED", delayMinutes: 5, color: "#417DBD", textColor: "#FFFFFF"),
            CombinedDeparture(line: "300", destination: "Aliados", source: .realtime, etaMinutes: 11, time: "16:25", status: "ON_TIME", delayMinutes: 0, color: "#417DBD", textColor: "#FFFFFF"),
            CombinedDeparture(line: "300", destination: "Aliados", source: .scheduled, etaMinutes: 24, time: "16:38", status: nil, delayMinutes: nil, color: "#417DBD", textColor: "#FFFFFF"),
            CombinedDeparture(line: "300", destination: "Aliados", source: .scheduled, etaMinutes: 44, time: "16:58", status: nil, delayMinutes: nil, color: "#417DBD", textColor: "#FFFFFF"),
        ])
}

extension Line {
    // Real GTFS route colours, confirmed against the live feed: city lines
    // share #187EC2, the M-family is black, 701 is red.
    static let previews = [
        Line(line: "201", description: "Viso - Trindade", routeId: "201_0", color: "#187EC2", textColor: "#FFFFFF"),
        Line(line: "300", description: "Circular Aliados - H.S.João", routeId: "300_0", color: "#187EC2", textColor: "#FFFFFF"),
        Line(line: "305", description: "Cordoaria - Matosinhos", routeId: "305_0", color: "#187EC2", textColor: "#FFFFFF"),
        Line(line: "701", description: "Bolhão - Codiceira", routeId: "701_0", color: "#FF0000", textColor: "#FFFFFF"),
        Line(line: "1M", description: "Circular Foz", routeId: "1M_0", color: "#000000", textColor: "#FFFFFF"),
    ]
}

extension RouteDirectionStops {
    static let preview = RouteDirectionStops(
        routeId: "305", directionId: 0,
        stops: [
            DirectionStop(stopId: "1", stopName: "CORDOARIA", stopCode: "COR", zoneId: nil, lat: nil, lon: nil, sequence: 0, description: nil),
            DirectionStop(stopId: "2", stopName: "CARMO", stopCode: "CMO", zoneId: nil, lat: nil, lon: nil, sequence: 1, description: nil),
            DirectionStop(stopId: "3", stopName: "TRINDADE", stopCode: "TRD6", zoneId: nil, lat: nil, lon: nil, sequence: 2, description: nil),
        ],
        timepointStopIds: ["1", "3"]
    )
}
#endif

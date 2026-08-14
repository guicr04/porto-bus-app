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
    func lines() async throws -> [Line] { try result([]) }
    func lineStops(line: String, directionId: Int) async throws -> RouteDirectionStops {
        try result(RouteDirectionStops(routeId: line, directionId: directionId, stops: [], timepointStopIds: []))
    }
    func lineShape(line: String, directionId: Int) async throws -> RouteShape {
        try result(RouteShape(routeId: line, directionId: directionId, coordinates: []))
    }
    func lineServices(line: String, date: String?) async throws -> RouteServices {
        try result(RouteServices(routeId: line, services: [], activeServiceId: nil, selectedDate: nil, today: nil))
    }
    func lineSchedule(line: String, serviceId: String, directionId: Int) async throws -> RouteSchedule {
        try result(RouteSchedule(routeId: line, serviceId: serviceId, directionId: directionId, timepointStops: [], trips: []))
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
    static let preview = RealtimeStop(
        stopCode: "CMO", stopName: "CARMO", arrivals: [
            Arrival(line: "305", destination: "Cordoaria", arrivalMinutes: 6, estimatedArrivalTime: nil, scheduledArrivalTime: nil, status: "ON_TIME", delayMinutes: 0, color: "#417DBD", textColor: "#FFFFFF", tripId: "T1"),
            Arrival(line: "300", destination: "Aliados", arrivalMinutes: 12, estimatedArrivalTime: nil, scheduledArrivalTime: nil, status: "DELAYED", delayMinutes: 5, color: "#417DBD", textColor: "#FFFFFF", tripId: "T2"),
        ], lastUpdated: nil, dataSource: "realtime")
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
#endif

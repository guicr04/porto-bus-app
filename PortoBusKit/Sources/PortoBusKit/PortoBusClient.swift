import Foundation

/// The app's view of the Porto Bus API. A protocol so the live implementation
/// and an in-memory mock are interchangeable — previews and tests never touch
/// the network. One method per endpoint; ViewModels depend on this, never on
/// URLSession.
public protocol PortoBusClient: Sendable {
    // board
    func board(lat: Double, lon: Double, walkMinutes: Int?, sort: BoardSort?, includeUnreachable: Bool) async throws -> LocationBoard

    // stops
    func stops(query: String?, limit: Int?) async throws -> [Stop]
    func stops(bbox: BoundingBox) async throws -> [Stop]
    func stopLines(bbox: BoundingBox) async throws -> [StopLines]
    func stop(code: String) async throws -> Stop
    func realtime(stop code: String) async throws -> RealtimeStop
    func stopRoutes(stop code: String) async throws -> StopRoutes
    func stopServices(stop code: String, date: String?) async throws -> StopServices
    func departures(stop code: String, line: String, serviceId: String?, directionId: Int?, windowMinutes: Int?, limit: Int?) async throws -> StopLineDepartures
    func stopSchedule(stop code: String, routeId: String, serviceId: String, directionId: Int) async throws -> StopSchedule

    // lines
    func lines() async throws -> [Line]
    func lineStops(line: String, directionId: Int) async throws -> RouteDirectionStops
    func lineShape(line: String, directionId: Int) async throws -> RouteShape
    func lineServices(line: String, date: String?) async throws -> RouteServices
    func lineSchedule(line: String, serviceId: String, directionId: Int) async throws -> RouteSchedule

    // trips
    func tripStops(tripId: String?, line: String?, headsign: String?, stop: String?, etaMinutes: Int?) async throws -> ResolvedTrip
}

// Convenience overloads so callers can omit the optional-heavy tail.
extension PortoBusClient {
    public func board(lat: Double, lon: Double) async throws -> LocationBoard {
        try await board(lat: lat, lon: lon, walkMinutes: nil, sort: nil, includeUnreachable: false)
    }

    public func stops(query: String? = nil) async throws -> [Stop] {
        try await stops(query: query, limit: nil)
    }

    public func departures(stop code: String, line: String) async throws -> StopLineDepartures {
        try await departures(stop: code, line: line, serviceId: nil, directionId: nil, windowMinutes: nil, limit: nil)
    }

    /// Resolve the bus behind one live arrival. Every hint the API's fallback
    /// can use is already on the `Arrival` and the stop it came from, so the
    /// call site never has to assemble them by hand — or forget to.
    public func tripStops(for arrival: Arrival, at stopCode: String) async throws -> ResolvedTrip {
        try await tripStops(
            tripId: arrival.tripId,
            line: arrival.line,
            headsign: arrival.destination,
            stop: stopCode,
            etaMinutes: arrival.arrivalMinutes.map { Int($0.rounded()) }
        )
    }

    /// The same, for a row on the combined departures list. A scheduled row has
    /// no trip id and resolves by pattern instead — which is why this doesn't
    /// refuse the way it used to when the id was missing.
    public func tripStops(for departure: CombinedDeparture, at stopCode: String) async throws -> ResolvedTrip {
        try await tripStops(
            tripId: departure.tripId,
            line: departure.line,
            headsign: departure.destination,
            stop: stopCode,
            etaMinutes: departure.etaMinutes.map { Int($0.rounded()) }
        )
    }
}

/// Live implementation over `URLSession`. Immutable and `Sendable`; the base URL
/// is captured at construction. When the base URL changes in Settings, the app
/// makes a new client rather than mutating this one.
public struct LivePortoBusClient: PortoBusClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: Core request

    private func get<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        guard let url = endpoint.url(relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: Self.previewBody(data))
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// A short slice of a response body, for error diagnostics only.
    private static func previewBody(_ data: Data, limit: Int = 500) -> String? {
        guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return nil }
        return s.count > limit ? String(s.prefix(limit)) + "…" : s
    }

    // MARK: Endpoints

    public func board(lat: Double, lon: Double, walkMinutes: Int?, sort: BoardSort?, includeUnreachable: Bool) async throws -> LocationBoard {
        try await get(API.board(lat: lat, lon: lon, walkMinutes: walkMinutes, sort: sort, includeUnreachable: includeUnreachable))
    }

    public func stops(bbox: BoundingBox) async throws -> [Stop] {
        try await get(API.stops(bbox: bbox))
    }

    public func stopLines(bbox: BoundingBox) async throws -> [StopLines] {
        try await get(API.stopLines(bbox: bbox))
    }

    public func stops(query: String?, limit: Int?) async throws -> [Stop] {
        try await get(API.stops(query: query, limit: limit))
    }

    public func stop(code: String) async throws -> Stop {
        try await get(API.stop(code: code))
    }

    public func realtime(stop code: String) async throws -> RealtimeStop {
        try await get(API.realtime(stop: code))
    }

    public func stopRoutes(stop code: String) async throws -> StopRoutes {
        try await get(API.stopRoutes(stop: code))
    }

    public func stopServices(stop code: String, date: String?) async throws -> StopServices {
        try await get(API.stopServices(stop: code, date: date))
    }

    public func departures(stop code: String, line: String, serviceId: String?, directionId: Int?, windowMinutes: Int?, limit: Int?) async throws -> StopLineDepartures {
        try await get(API.departures(stop: code, line: line, serviceId: serviceId, directionId: directionId, windowMinutes: windowMinutes, limit: limit))
    }

    public func stopSchedule(stop code: String, routeId: String, serviceId: String, directionId: Int) async throws -> StopSchedule {
        try await get(API.stopSchedule(stop: code, routeId: routeId, serviceId: serviceId, directionId: directionId))
    }

    public func lines() async throws -> [Line] {
        try await get(API.lines())
    }

    public func lineStops(line: String, directionId: Int) async throws -> RouteDirectionStops {
        try await get(API.lineStops(line: line, directionId: directionId))
    }

    public func lineShape(line: String, directionId: Int) async throws -> RouteShape {
        try await get(API.lineShape(line: line, directionId: directionId))
    }

    public func lineServices(line: String, date: String?) async throws -> RouteServices {
        try await get(API.lineServices(line: line, date: date))
    }

    public func lineSchedule(line: String, serviceId: String, directionId: Int) async throws -> RouteSchedule {
        try await get(API.lineSchedule(line: line, serviceId: serviceId, directionId: directionId))
    }

    public func tripStops(tripId: String?, line: String?, headsign: String?, stop: String?, etaMinutes: Int?) async throws -> ResolvedTrip {
        try await get(API.tripStops(tripId: tripId, line: line, headsign: headsign, stop: stop, etaMinutes: etaMinutes))
    }
}

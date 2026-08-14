import Foundation

/// A single API call: a path relative to the base URL plus query items.
///
/// Query encoding is deliberately strict. STCP matches `service_id` exactly
/// server-side (`DOM|FERIADO:FLUXO 3.1 20260718`), and the API README warns that
/// a space sent as `+` breaks the lookup. So every value is percent-encoded
/// against a conservative allowed set — alphanumerics only — which turns spaces
/// into `%20`, encodes `|` and `:`, and never emits `+`. `URLComponents` alone
/// leaves some of those characters raw, so we build the query string by hand.
public struct Endpoint: Sendable {
    public let path: String
    public let queryItems: [String: String?]

    public init(path: String, queryItems: [String: String?] = [:]) {
        self.path = path
        self.queryItems = queryItems
    }

    /// Characters left unescaped in query values. Everything else — including
    /// space, `|`, `:`, `+` — is percent-encoded.
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// Resolve against a base URL (e.g. `http://192.168.1.20:8000`).
    public func url(relativeTo base: URL) -> URL? {
        // Combine base + path first, without query, so path segments resolve.
        guard let pathURL = URL(string: path, relativeTo: base) else { return nil }

        let pairs = queryItems
            .compactMap { key, value -> String? in
                guard let value else { return nil }
                let ek = key.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? key
                let ev = value.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? value
                return "\(ek)=\(ev)"
            }
            .sorted() // deterministic ordering — stable cache keys and test assertions

        guard !pairs.isEmpty else { return pathURL.absoluteURL }

        guard var components = URLComponents(url: pathURL.absoluteURL, resolvingAgainstBaseURL: true) else {
            return nil
        }
        components.percentEncodedQuery = pairs.joined(separator: "&")
        return components.url
    }
}

// MARK: - Endpoint catalogue

/// One factory per API route. Centralised so the paths live in exactly one place
/// and the client reads as a list of intents, not string interpolation.
public enum API {
    // --- board ---
    public static func board(
        lat: Double, lon: Double,
        walkMinutes: Int? = nil,
        sort: BoardSort? = nil,
        includeUnreachable: Bool? = nil
    ) -> Endpoint {
        Endpoint(path: "board", queryItems: [
            "lat": String(lat),
            "lon": String(lon),
            "walk_minutes": walkMinutes.map(String.init),
            "sort": sort?.rawValue,
            "include_unreachable": (includeUnreachable == true) ? "1" : nil,
        ])
    }

    // --- stops ---
    public static func stops(query: String? = nil, limit: Int? = nil) -> Endpoint {
        Endpoint(path: "stops", queryItems: [
            "q": query,
            "limit": limit.map(String.init),
        ])
    }

    public static func stop(code: String) -> Endpoint {
        Endpoint(path: "stops/\(pathSafe(code))")
    }

    public static func realtime(stop code: String) -> Endpoint {
        Endpoint(path: "stops/\(pathSafe(code))/realtime")
    }

    public static func stopRoutes(stop code: String) -> Endpoint {
        Endpoint(path: "stops/\(pathSafe(code))/routes")
    }

    public static func stopServices(stop code: String, date: String? = nil) -> Endpoint {
        Endpoint(path: "stops/\(pathSafe(code))/services", queryItems: ["date": date])
    }

    public static func departures(
        stop code: String,
        line: String,
        serviceId: String? = nil,
        directionId: Int? = nil,
        windowMinutes: Int? = nil,
        limit: Int? = nil
    ) -> Endpoint {
        Endpoint(path: "stops/\(pathSafe(code))/departures", queryItems: [
            "line": line,
            "service_id": serviceId,
            "direction_id": directionId.map(String.init),
            "window_minutes": windowMinutes.map(String.init),
            "limit": limit.map(String.init),
        ])
    }

    public static func stopSchedule(
        stop code: String, routeId: String, serviceId: String, directionId: Int = 0
    ) -> Endpoint {
        Endpoint(path: "stops/\(pathSafe(code))/schedule", queryItems: [
            "route_id": routeId,
            "service_id": serviceId,
            "direction_id": String(directionId),
        ])
    }

    // --- lines ---
    public static func lines() -> Endpoint {
        Endpoint(path: "lines")
    }

    public static func lineStops(line: String, directionId: Int = 0) -> Endpoint {
        Endpoint(path: "lines/\(pathSafe(line))/stops", queryItems: ["direction_id": String(directionId)])
    }

    public static func lineShape(line: String, directionId: Int = 0) -> Endpoint {
        Endpoint(path: "lines/\(pathSafe(line))/shape", queryItems: ["direction_id": String(directionId)])
    }

    public static func lineServices(line: String, date: String? = nil) -> Endpoint {
        Endpoint(path: "lines/\(pathSafe(line))/services", queryItems: ["date": date])
    }

    public static func lineSchedule(line: String, serviceId: String, directionId: Int = 0) -> Endpoint {
        Endpoint(path: "lines/\(pathSafe(line))/schedule", queryItems: [
            "service_id": serviceId,
            "direction_id": String(directionId),
        ])
    }

    /// Encode a value destined for a path segment (stop codes are plain, but a
    /// line id could in principle carry a space or slash).
    private static func pathSafe(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}

public enum BoardSort: String, Sendable {
    case line
    case eta
}

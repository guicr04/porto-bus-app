// Port of porto-bus-api/types/domain.d.ts — one live bus's whole journey
// (`/trips/{trip_id}/stops`). Backs the line-detail screen: DESIGN.md §11.1.

import Foundation

/// How the live `trip_id` was matched to a trip in the static feed.
///
/// Descending confidence, and the app is expected to read it rather than treat
/// every resolution as equal — a `pattern` match guessed the bus from its line
/// and headsign, which is a materially weaker claim than an id that resolved.
/// Modelled with an `unknown` case so a new rung added server-side degrades
/// instead of failing the whole decode, same rule as `DepartureSource`.
public enum TripMatch: Sendable, Hashable {
    /// ids were equal: the store's feed version is what STCP is serving
    case exact
    /// equal once the feed-version field was dropped, and unambiguous
    case version
    /// version-stripped match the day's service could not narrow; newest feed version won
    case versionLatest
    /// the id missed entirely; matched on line + headsign + nearest scheduled departure
    case pattern
    case unknown(String)

    /// True for the two rungs that identify the bus by its id rather than by
    /// guessing from what it looks like.
    public var isCertain: Bool { self == .exact || self == .version }
}

extension TripMatch: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "exact": self = .exact
        case "version": self = .version
        case "version_latest": self = .versionLatest
        case "pattern": self = .pattern
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .exact: try container.encode("exact")
        case .version: try container.encode("version")
        case .versionLatest: try container.encode("version_latest")
        case .pattern: try container.encode("pattern")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

/// One stop on a resolved trip.
///
/// Distinct from `TripStop` (the schedule grid's) by the two fields that make
/// this payload useful: the `stopCode` the rest of the app speaks, and seconds
/// since midnight. The seconds matter — the whole point of this response is
/// arithmetic on the gaps, and GTFS legitimately writes "24:35:00", so doing
/// that on clock strings re-invites an after-midnight bug the API already
/// solved once.
public struct ResolvedTripStop: Codable, Sendable, Hashable, Identifiable {
    public let stopSequence: Int
    public let stopId: String
    public let stopCode: String
    public let stopName: String
    public let stopLat: Double?
    public let stopLon: Double?
    /// "HH:MM:SS", may exceed 24h
    public let arrivalTime: String
    public let departureTime: String
    /// may exceed 86400 for the after-midnight tail of a trip
    public let arrivalSeconds: Int
    public let departureSeconds: Int
    public let timepoint: Bool

    /// A stop can legitimately appear twice on one trip (loop services), so the
    /// sequence — not the code — is what identifies a row.
    public var id: Int { stopSequence }

    public init(
        stopSequence: Int,
        stopId: String,
        stopCode: String,
        stopName: String,
        stopLat: Double?,
        stopLon: Double?,
        arrivalTime: String,
        departureTime: String,
        arrivalSeconds: Int,
        departureSeconds: Int,
        timepoint: Bool
    ) {
        self.stopSequence = stopSequence
        self.stopId = stopId
        self.stopCode = stopCode
        self.stopName = stopName
        self.stopLat = stopLat
        self.stopLon = stopLon
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.arrivalSeconds = arrivalSeconds
        self.departureSeconds = departureSeconds
        self.timepoint = timepoint
    }
}

/// A live bus resolved to a trip in the static feed, with its whole ordered
/// journey.
public struct ResolvedTrip: Codable, Sendable, Hashable {
    /// the store's id for this trip
    public let tripId: String
    /// the id as asked for, i.e. the live one; nil when asked for by pattern
    public let requestedTripId: String?
    public let match: TripMatch
    public let routeId: String
    /// route_short_name, e.g. "601"
    public let line: String?
    public let color: String?
    public let textColor: String?
    public let headsign: String?
    public let directionId: Int?
    public let serviceId: String
    public let shapeId: String?
    /// True when the ingested feed is past its validity window. The stop order
    /// is still trustworthy; the minute-gaps between them come from a timetable
    /// STCP has already moved past.
    public let feedExpired: Bool
    public let stops: [ResolvedTripStop]

    public init(
        tripId: String,
        requestedTripId: String?,
        match: TripMatch,
        routeId: String,
        line: String?,
        color: String?,
        textColor: String?,
        headsign: String?,
        directionId: Int?,
        serviceId: String,
        shapeId: String?,
        feedExpired: Bool,
        stops: [ResolvedTripStop]
    ) {
        self.tripId = tripId
        self.requestedTripId = requestedTripId
        self.match = match
        self.routeId = routeId
        self.line = line
        self.color = color
        self.textColor = textColor
        self.headsign = headsign
        self.directionId = directionId
        self.serviceId = serviceId
        self.shapeId = shapeId
        self.feedExpired = feedExpired
        self.stops = stops
    }

    /// Where the rider is standing, as an index into `stops`.
    ///
    /// Searched from the front: a loop service calls at the same stop twice, and
    /// the first call is the one they are waiting for.
    public func index(of stopCode: String) -> Int? {
        stops.firstIndex { $0.stopCode == stopCode }
    }

    /// The stops after the rider's, each with the minutes-from-now it should
    /// reach them.
    ///
    /// `liveEtaMinutes` is the only measured number in the result; every offset
    /// comes from the timetable. That is the honest shape of this feature —
    /// carrying the current delay forward is an assumption, not a measurement,
    /// so the caller must not style these as live (DESIGN.md §11.1).
    ///
    /// - Returns: an empty array when the stop isn't on this trip, or is its
    ///   last stop — both meaning "there is nothing after here to show".
    public func downstream(from stopCode: String, liveEtaMinutes: Double) -> [(stop: ResolvedTripStop, etaMinutes: Double)] {
        guard let start = index(of: stopCode) else { return [] }
        let origin = stops[start].arrivalSeconds
        return stops.dropFirst(start + 1).map { stop in
            (stop, liveEtaMinutes + Double(stop.arrivalSeconds - origin) / 60)
        }
    }
}

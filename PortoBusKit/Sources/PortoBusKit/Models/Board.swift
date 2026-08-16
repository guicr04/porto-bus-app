// Port of porto-bus-api/types/domain.d.ts — combined departures and the
// location board. These back the two most important screens, so their fields
// carry the most behavioural weight (see DESIGN.md §6, §7).

import Foundation

// MARK: - Combined live + scheduled departures: /stops/{code}/departures?line=

/// Which feed a departure came from. Closed set in the contract, but modelled
/// with an `unknown` fallback so an upstream addition degrades instead of
/// failing to decode the whole list. This tag drives the two distinct visual
/// treatments in the Departures screen — it must never be silently lost.
public enum DepartureSource: Sendable, Hashable {
    case realtime
    case scheduled
    case unknown(String)

    public var isRealtime: Bool { self == .realtime }
}

extension DepartureSource: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "realtime": self = .realtime
        case "scheduled": self = .scheduled
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .realtime: try container.encode("realtime")
        case .scheduled: try container.encode("scheduled")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

public struct CombinedDeparture: Codable, Sendable, Hashable {
    public let line: String
    public let destination: String
    /// which feed this came from — style these differently on the frontend
    public let source: DepartureSource
    /// minutes from now (both sources); 0 == arriving. Upstream `number` — may
    /// be fractional; round for display.
    public let etaMinutes: Double?
    /// "HH:MM" clock time (estimated for live, scheduled for static)
    public let time: String
    public let status: String?         // realtime only (ON_TIME / DELAYED)
    public let delayMinutes: Double?   // realtime only; fractional
    public let color: String?
    public let textColor: String?
    /// The trip behind this departure, when it is known. Always set on live
    /// rows; nil on scheduled ones unless they came from the store, because
    /// upstream's timetable is times and headsigns only. A nil here is normal —
    /// the journey for such a departure is asked for by pattern instead.
    public let tripId: String?

    public init(line: String, destination: String, source: DepartureSource, etaMinutes: Double?, time: String, status: String?, delayMinutes: Double?, color: String?, textColor: String?, tripId: String? = nil) {
        self.line = line
        self.destination = destination
        self.source = source
        self.etaMinutes = etaMinutes
        self.time = time
        self.status = status
        self.delayMinutes = delayMinutes
        self.color = color
        self.textColor = textColor
        self.tripId = tripId
    }
}

public struct StopLineDepartures: Codable, Sendable, Hashable {
    public let stopCode: String
    public let line: String
    public let directionId: Int?
    public let serviceId: String?      // service used for the scheduled fallback
    public let generatedAt: String     // ISO timestamp of when this was built
    public let departures: [CombinedDeparture]

    public init(stopCode: String, line: String, directionId: Int?, serviceId: String?, generatedAt: String, departures: [CombinedDeparture]) {
        self.stopCode = stopCode
        self.line = line
        self.directionId = directionId
        self.serviceId = serviceId
        self.generatedAt = generatedAt
        self.departures = departures
    }
}

// MARK: - Departure board for a location: /board and /board.txt

public struct BoardRow: Codable, Sendable, Hashable, Identifiable {
    public let line: String
    public let destination: String
    /// True when STCP is actually tracking the buses at this stop, false when it
    /// has fallen back to projecting from the timetable.
    public let realtime: Bool
    /// the raw upstream label behind `realtime`, e.g. "realtime"
    public let dataSource: String?
    /// which nearby stop this departs from
    public let stopCode: String
    public let stopName: String
    /// minutes to walk from the origin to that stop
    public let walkMinutes: Int
    public let distanceMeters: Int
    /// minutes until the bus reaches the stop. Upstream `number` — may be
    /// fractional; round for display.
    public let etaMinutes: Double
    /// Minutes until you have to leave. eta minus the walk (minus any buffer);
    /// negative means the walk is longer than the wait, so it's unreachable.
    public let leaveInMinutes: Double
    public let catchable: Bool
    public let status: String?
    /// + late, - early. Fractional — a raw upstream `number`.
    public let delayMinutes: Double?
    public let color: String?
    public let textColor: String?

    /// Stable identity for a row: a given line from a given stop is one board
    /// slot. Keeps SwiftUI diffing steady across the 20s refresh.
    public var id: String { "\(stopCode)-\(line)-\(destination)" }

    public init(line: String, destination: String, realtime: Bool, dataSource: String?, stopCode: String, stopName: String, walkMinutes: Int, distanceMeters: Int, etaMinutes: Double, leaveInMinutes: Double, catchable: Bool, status: String?, delayMinutes: Double?, color: String?, textColor: String?) {
        self.line = line
        self.destination = destination
        self.realtime = realtime
        self.dataSource = dataSource
        self.stopCode = stopCode
        self.stopName = stopName
        self.walkMinutes = walkMinutes
        self.distanceMeters = distanceMeters
        self.etaMinutes = etaMinutes
        self.leaveInMinutes = leaveInMinutes
        self.catchable = catchable
        self.status = status
        self.delayMinutes = delayMinutes
        self.color = color
        self.textColor = textColor
    }
}

public struct PolledStop: Codable, Sendable, Hashable, Identifiable {
    public let stopCode: String
    public let name: String
    public let distanceMeters: Int
    public let walkMinutes: Int
    /// false when the live call for this stop failed — an empty board vs a broken one
    public let ok: Bool

    public var id: String { stopCode }

    public init(stopCode: String, name: String, distanceMeters: Int, walkMinutes: Int, ok: Bool) {
        self.stopCode = stopCode
        self.name = name
        self.distanceMeters = distanceMeters
        self.walkMinutes = walkMinutes
        self.ok = ok
    }
}

public struct LocationBoard: Codable, Sendable, Hashable {
    public struct Origin: Codable, Sendable, Hashable {
        public let lat: Double
        public let lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    public let origin: Origin
    public let walkMinutes: Int
    public let generatedAt: String
    /// how many stops were in range
    public let stopsConsidered: Int
    /// the subset actually polled (capped by max_stops)
    public let stopsPolled: [PolledStop]
    public let departures: [BoardRow]
    /// Present when `max_stops` cut the poll short. Not in domain.d.ts but
    /// documented in the API README and relied on by DESIGN.md §7, so captured
    /// as optional — absent decodes to nil rather than failing.
    public let stopsTruncated: Bool?

    public init(origin: Origin, walkMinutes: Int, generatedAt: String, stopsConsidered: Int, stopsPolled: [PolledStop], departures: [BoardRow], stopsTruncated: Bool?) {
        self.origin = origin
        self.walkMinutes = walkMinutes
        self.generatedAt = generatedAt
        self.stopsConsidered = stopsConsidered
        self.stopsPolled = stopsPolled
        self.departures = departures
        self.stopsTruncated = stopsTruncated
    }

    /// True when at least one polled stop failed — the UI should say "some
    /// stops unavailable" rather than implying nothing runs. See DESIGN.md §7.
    public var hasFailedStops: Bool {
        stopsPolled.contains { !$0.ok }
    }
}

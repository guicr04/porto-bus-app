// Port of porto-bus-api/types/domain.d.ts — stops & lines (static, from GTFS)
// and live arrivals. Names and optionality mirror the .d.ts one-to-one so the
// contract diffs the same on both sides.

import Foundation

// MARK: - Stops & lines (static, from GTFS)

public struct Stop: Codable, Sendable, Hashable, Identifiable {
    public let stopCode: String
    public let name: String
    public let lat: Double?
    public let lon: Double?

    public var id: String { stopCode }

    public init(stopCode: String, name: String, lat: Double?, lon: Double?) {
        self.stopCode = stopCode
        self.name = name
        self.lat = lat
        self.lon = lon
    }
}

public struct Line: Codable, Sendable, Hashable, Identifiable {
    /// short name shown to riders, e.g. "500"
    public let line: String
    /// long name, e.g. "Cordoaria - Matosinhos"
    public let description: String
    /// internal GTFS route id
    public let routeId: String
    /// official GTFS route_color, e.g. "#187EC2"; most city lines share one family colour
    public let color: String?
    public let textColor: String?

    public var id: String { line }

    public init(line: String, description: String, routeId: String, color: String?, textColor: String?) {
        self.line = line
        self.description = description
        self.routeId = routeId
        self.color = color
        self.textColor = textColor
    }
}

// MARK: - Live arrivals: /stops/{code}/realtime

/// Open union in the contract ('ON_TIME' | 'DELAYED' | string). Modelled as a
/// raw String so an unrecognised upstream status decodes rather than throwing;
/// callers compare against the known constants.
public enum ArrivalStatus: String, Sendable {
    case onTime = "ON_TIME"
    case delayed = "DELAYED"
}

public struct Arrival: Codable, Sendable, Hashable {
    /// route_short_name, e.g. "305"
    public let line: String
    /// trip_headsign, e.g. "Cordoaria"
    public let destination: String
    /// minutes until arrival; 0 means "Arriving". Passed through from upstream
    /// as a `number`, so it can be fractional — round only for display.
    public let arrivalMinutes: Double?
    /// ISO 8601 timestamp, e.g. "2026-07-19T16:37:10+01:00"
    public let estimatedArrivalTime: String?
    public let scheduledArrivalTime: String?
    /// raw upstream status; see `statusValue` for the typed form
    public let status: String?
    /// + late, - early. Fractional (e.g. 0.8) — a raw upstream `number`.
    public let delayMinutes: Double?
    /// route_color, e.g. "#417DBD"
    public let color: String?
    public let textColor: String?
    public let tripId: String?

    /// Typed view of `status`; nil when upstream sends something unrecognised.
    public var statusValue: ArrivalStatus? {
        status.flatMap(ArrivalStatus.init(rawValue:))
    }

    public init(
        line: String,
        destination: String,
        arrivalMinutes: Double?,
        estimatedArrivalTime: String?,
        scheduledArrivalTime: String?,
        status: String?,
        delayMinutes: Double?,
        color: String?,
        textColor: String?,
        tripId: String?
    ) {
        self.line = line
        self.destination = destination
        self.arrivalMinutes = arrivalMinutes
        self.estimatedArrivalTime = estimatedArrivalTime
        self.scheduledArrivalTime = scheduledArrivalTime
        self.status = status
        self.delayMinutes = delayMinutes
        self.color = color
        self.textColor = textColor
        self.tripId = tripId
    }
}

public struct RealtimeStop: Codable, Sendable, Hashable {
    public let stopCode: String
    public let stopName: String?
    public let arrivals: [Arrival]
    public let lastUpdated: String?
    /// "realtime" when live, otherwise a scheduled fallback
    public let dataSource: String?

    public init(
        stopCode: String,
        stopName: String?,
        arrivals: [Arrival],
        lastUpdated: String?,
        dataSource: String?
    ) {
        self.stopCode = stopCode
        self.stopName = stopName
        self.arrivals = arrivals
        self.lastUpdated = lastUpdated
        self.dataSource = dataSource
    }
}

// MARK: - Routes at a stop: /stops/{code}/routes

public struct StopRoute: Codable, Sendable, Hashable {
    public let routeId: String
    public let shortName: String
    public let longName: String
    public let color: String?
    public let textColor: String?
    public let routeType: Int?
    /// only present on the per-direction ("dropdown") variant
    public let directionId: Int?
    public let directionName: String?
    public let displayName: String?
    public let tripHeadsign: String?
}

public struct StopRoutes: Codable, Sendable, Hashable {
    /// one entry per line (from display_routes)
    public let routes: [StopRoute]
    /// one entry per line+direction (from dropdown_routes)
    public let directions: [StopRoute]

    public init(routes: [StopRoute], directions: [StopRoute]) {
        self.routes = routes
        self.directions = directions
    }
}

// MARK: - Services at a stop: /stops/{code}/services

public struct ServiceDay: Codable, Sendable, Hashable {
    public let serviceId: String
    public let serviceName: String
    public let isActiveToday: Bool
    /// monday..sunday flags as returned upstream (often unreliable — prefer isActiveToday)
    public let days: [String: Int]
}

public struct StopServices: Codable, Sendable, Hashable {
    public let services: [ServiceDay]
    public let activeServiceId: String?
    /// YYYYMMDD as returned upstream
    public let selectedDate: String?
    public let today: String?

    public init(services: [ServiceDay], activeServiceId: String?, selectedDate: String?, today: String?) {
        self.services = services
        self.activeServiceId = activeServiceId
        self.selectedDate = selectedDate
        self.today = today
    }
}

// MARK: - Timetable: /stops/{code}/schedule

public struct Departure: Codable, Sendable, Hashable {
    /// "HH:MM:SS", may exceed 24h (e.g. "24:39:00") for after-midnight trips
    public let departureTime: String
    public let arrivalTime: String
    public let headsign: String
    public let directionId: Int
}

public struct StopSchedule: Codable, Sendable, Hashable {
    public let stopCode: String
    public let routeId: String
    public let directionId: Int
    public let serviceId: String
    /// flattened out of the hour-keyed buckets and sorted by departureTime
    public let departures: [Departure]

    public init(stopCode: String, routeId: String, directionId: Int, serviceId: String, departures: [Departure]) {
        self.stopCode = stopCode
        self.routeId = routeId
        self.directionId = directionId
        self.serviceId = serviceId
        self.departures = departures
    }
}

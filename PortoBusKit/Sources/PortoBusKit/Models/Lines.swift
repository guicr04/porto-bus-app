// Port of porto-bus-api/types/domain.d.ts — line-centric endpoints
// (/api/route/{line}/...).

import Foundation

// MARK: - /route/{line}/shape?direction_id= (map polyline)

public struct ShapePoint: Codable, Sendable, Hashable {
    public let lat: Double
    /// NOTE: the one field snake_case conversion does NOT rename — everything
    /// else in the API says `lon`, but the shape payload sends `lng`. Explicit
    /// key required.
    public let lng: Double
    public let sequence: Int

    enum CodingKeys: String, CodingKey {
        case lat
        case lng
        case sequence
    }
}

public struct RouteShape: Codable, Sendable, Hashable {
    public let routeId: String
    public let directionId: Int
    public let coordinates: [ShapePoint]

    public init(routeId: String, directionId: Int, coordinates: [ShapePoint]) {
        self.routeId = routeId
        self.directionId = directionId
        self.coordinates = coordinates
    }
}

// MARK: - /route/{line}/services?date=
// NOTE: differs from the stop version — `services` is a plain string array.

public struct RouteServices: Codable, Sendable, Hashable {
    public let routeId: String
    public let services: [String]              // service_id strings
    public let activeServiceId: String?
    public let selectedDate: String?           // YYYYMMDD
    public let today: String?

    public init(routeId: String, services: [String], activeServiceId: String?, selectedDate: String?, today: String?) {
        self.routeId = routeId
        self.services = services
        self.activeServiceId = activeServiceId
        self.selectedDate = selectedDate
        self.today = today
    }
}

// MARK: - /route/{line}/stops/direction?direction_id=

public struct DirectionStop: Codable, Sendable, Hashable, Identifiable {
    public let stopId: String
    public let stopName: String
    public let stopCode: String
    public let zoneId: String?
    public let lat: Double?
    public let lon: Double?
    public let sequence: Int
    public let description: String?

    public var id: String { stopId }

    public init(stopId: String, stopName: String, stopCode: String, zoneId: String?, lat: Double?, lon: Double?, sequence: Int, description: String?) {
        self.stopId = stopId
        self.stopName = stopName
        self.stopCode = stopCode
        self.zoneId = zoneId
        self.lat = lat
        self.lon = lon
        self.sequence = sequence
        self.description = description
    }
}

public struct RouteDirectionStops: Codable, Sendable, Hashable {
    public let routeId: String
    public let directionId: Int
    public let stops: [DirectionStop]          // full ordered stop list for the direction
    public let timepointStopIds: [String]      // subset shown as timing columns

    public init(routeId: String, directionId: Int, stops: [DirectionStop], timepointStopIds: [String]) {
        self.routeId = routeId
        self.directionId = directionId
        self.stops = stops
        self.timepointStopIds = timepointStopIds
    }
}

// MARK: - /route/{line}/schedule?service_id=&direction_id=
// The full timetable grid: many trips, each hitting the timepoint stops.

public struct TripStop: Codable, Sendable, Hashable {
    public let stopSequence: Int
    public let stopId: String
    public let stopName: String
    public let stopLat: Double?
    public let stopLon: Double?
    public let arrivalTime: String             // "HH:MM:SS", may exceed 24h
    public let departureTime: String
}

public struct Trip: Codable, Sendable, Hashable, Identifiable {
    public let tripId: String
    public let serviceId: String
    public let tripHeadsign: String
    public let directionId: Int
    public let stops: [TripStop]

    public var id: String { tripId }
}

public struct RouteSchedule: Codable, Sendable, Hashable {
    public let routeId: String
    public let serviceId: String
    public let directionId: Int
    public let timepointStops: [DirectionStop] // the column headers (from selected_stops)
    public let trips: [Trip]                   // sorted by first departure

    public init(routeId: String, serviceId: String, directionId: Int, timepointStops: [DirectionStop], trips: [Trip]) {
        self.routeId = routeId
        self.serviceId = serviceId
        self.directionId = directionId
        self.timepointStops = timepointStops
        self.trips = trips
    }
}

import CoreLocation
import Foundation
import Observation
import PortoBusKit

/// One departure of this line from this stop — a bubble in the row along the
/// top, and the thing the rest of the screen is about once it's selected.
struct DepartureChipDisplay: Identifiable, Hashable {
    /// Stable across refreshes, which is what lets a selection survive them.
    /// The trip id when there is one; otherwise the timetable clock, which for
    /// a scheduled slot doesn't move. A live bus's *estimated* clock does move,
    /// which is exactly why it isn't the key when an id is available.
    let id: String
    let tripId: String?
    let etaMinutes: Double?
    let etaText: String
    /// "HH:MM" — estimated for a tracked bus, timetable for a scheduled one.
    let clockText: String
    let destination: String
    /// Tracked by STCP, as opposed to a timetable entry. Drives the colouring.
    let isLive: Bool
    let tone: ArrivalTone
}

/// A stop as drawn on the map. The *whole* trip, not just the part ahead —
/// a polyline running the length of the line with dots on only the last third
/// reads as a data error.
struct RouteStopDisplay: Identifiable, Hashable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let isOrigin: Bool
    /// First or last stop on the trip.
    let isTerminus: Bool
}

/// One stop on the journey ahead, preformatted.
///
/// `clockText` is nil when the bus could not be resolved to a real trip. That
/// is the honest empty — the stop order is still known, the times are not, and
/// inventing one to fill the column is the exact failure DESIGN.md §11.1 rules
/// out.
struct JourneyStopDisplay: Identifiable, Hashable {
    let id: Int
    let name: String
    let clockText: String?
    /// Where the bus is now, in the rider's own terms — set only on their stop.
    let etaText: String?
    let tone: ArrivalTone
    let isOrigin: Bool
    let isTimepoint: Bool
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Everything the line-detail screen shows about one bus on one line: which
/// departures are coming, where the selected one goes after the rider's stop,
/// when it gets there, and the shape of its route.
///
/// The times downstream are **projected, not measured**:
///
///     ETA(later stop) = the selected departure's ETA + (scheduled(later) − scheduled(here))
///
/// Only the anchor is real, and only when the selected departure is a tracked
/// one. A bus four minutes late may make some of it up, so carrying the delay
/// forward is an assumption — which is why nothing after the rider's own stop
/// is ever styled as live, however confident the number reads (DESIGN.md §11.1).
@MainActor
@Observable
final class LineDetailViewModel {
    private(set) var state: LoadState<Void> = .idle

    /// Every departure of this line from this stop, the followed one included.
    ///
    /// It used to be "the *other* departures", with the followed bus filtered
    /// out — which turned out to be the wrong shape twice over: it hid the bus
    /// you were actually looking at from the row that lists them, and it left
    /// no way to look at a different one.
    private(set) var chips: [DepartureChipDisplay] = []
    private(set) var selectedId: String?

    /// The resolved trip, when the selected departure could be identified.
    private(set) var trip: ResolvedTrip?
    /// The fallback stop list, used when it could not.
    private(set) var untimedStops: [DirectionStop] = []
    private(set) var shape: [CLLocationCoordinate2D] = []
    /// True while a load is in flight. The view uses it to hold an empty space
    /// open rather than filling it with "nothing here" — see `select`.
    private(set) var isResolving = false

    private let client: PortoBusClient
    private let stop: Stop
    /// The board row that opened this screen. Only used to choose the initial
    /// selection; after that the selection is the rider's.
    private let opened: Arrival
    let line: String

    init(client: PortoBusClient, stop: Stop, arrival: Arrival, line: String) {
        self.client = client
        self.stop = stop
        self.opened = arrival
        self.line = line
    }

    // MARK: - What the view reads

    var selected: DepartureChipDisplay? { chips.first { $0.id == selectedId } }
    var destination: String { selected?.destination ?? trip?.headsign ?? opened.destination }
    var colorHex: String? { opened.color ?? trip?.color }
    var textColorHex: String? { opened.textColor ?? trip?.textColor }
    var originName: String { stop.name }
    var etaText: String { selected.map(\.etaText) ?? "Departed" }
    var tone: ArrivalTone { selected?.tone ?? .unknown }

    /// True once the followed bus has dropped off the departures list — it left.
    var departed: Bool { !chips.isEmpty && selected == nil }

    /// A key identifying the currently-drawn route, so the map re-frames when
    /// the rider picks a different departure and not on every refresh.
    var routeKey: String { "\(line)|\(selectedId ?? "")" }

    /// The rider's stop, then everything after it.
    ///
    /// The origin row is included deliberately. It is the one measured number on
    /// the screen — when there is one at all — and showing it at the head of the
    /// sequence is what makes the rest legible as offsets from it rather than as
    /// independent predictions.
    var journey: [JourneyStopDisplay] {
        if let trip { return timedJourney(trip) }
        return untimedJourney()
    }

    /// Every stop on the trip, for the map.
    ///
    /// Deliberately not `journey`, which starts at the rider's stop: the route
    /// line is drawn end to end, so dotting only the tail of it looks broken.
    ///
    /// **Superseded:** the stops before the rider's were briefly drawn faded, on
    /// the theory that the part of the route already covered shouldn't compete
    /// with the part ahead. In practice it just looked like a rendering fault —
    /// half the line greyed out for no reason a rider could see. The ends of the
    /// line carry that information better, and honestly: they are filled, so the
    /// route reads as a route rather than as a string of identical beads.
    var routeStops: [RouteStopDisplay] {
        if let trip, let originIndex = trip.index(of: stop.stopCode) {
            let last = trip.stops.count - 1
            return trip.stops.enumerated().compactMap { index, s in
                guard let lat = s.stopLat, let lon = s.stopLon else { return nil }
                return RouteStopDisplay(
                    id: s.stopSequence,
                    name: s.stopName,
                    latitude: lat,
                    longitude: lon,
                    isOrigin: index == originIndex,
                    isTerminus: index == 0 || index == last
                )
            }
        }
        let originIndex = untimedStops.firstIndex { $0.stopCode == stop.stopCode }
        let last = untimedStops.count - 1
        return untimedStops.enumerated().compactMap { index, s in
            guard let lat = s.lat, let lon = s.lon else { return nil }
            return RouteStopDisplay(
                id: s.sequence,
                name: s.stopName,
                latitude: lat,
                longitude: lon,
                isOrigin: index == originIndex,
                isTerminus: index == 0 || index == last
            )
        }
    }

    /// Nothing to show, and nothing still on its way to change that. The view
    /// must not say "nowhere to follow" while this is false.
    var isEmptyAfterLoading: Bool { journey.isEmpty && !isResolving }

    /// Why the times are missing or shaky, when they are. Nil when there is
    /// nothing to apologise for.
    var caveat: String? {
        if departed {
            return "This bus has left \(stop.name). Pick another departure above."
        }
        guard let trip else {
            return untimedStops.isEmpty
                ? nil
                : "Couldn't tell which bus this is, so there are no times for the stops ahead."
        }
        // `pattern` is the expected and only possible rung for a scheduled
        // departure — it has no id to match — so apologising for it there would
        // be noise. On a tracked bus it means the id join missed, which is worth
        // saying.
        if selected?.isLive == true, !trip.match.isCertain {
            return "This bus was matched by its line and destination, not its ID — the stops ahead may belong to a different run."
        }
        if trip.feedExpired {
            return "Times ahead come from a timetable STCP has since replaced. The order of the stops is still right."
        }
        return nil
    }

    // MARK: - Intent

    /// Follow a different departure.
    ///
    /// The old trip is cleared first — leaving it up would show one bus's stops
    /// under another bus's times, which is worse than showing nothing. But
    /// "nothing" is then briefly true, and the view must render that as *loading*
    /// rather than as "nowhere to follow": an empty-state card that appears for
    /// half a second on every tap reads as a broken button, and it says
    /// something false while it's up.
    func select(_ id: String) async {
        guard id != selectedId else { return }
        selectedId = id
        trip = nil
        untimedStops = []
        isResolving = true
        await load()
    }

    // MARK: - Loading

    func load() async {
        if state.isInitialLoad { state = .loading }
        isResolving = true
        defer { isResolving = false }

        // One call does three jobs: the bubbles, the anchor ETA for whichever
        // one is selected, and — when the trip can't be resolved — the direction
        // the route runs in.
        //
        // It passes no `direction_id` of its own on purpose. STCP stop codes are
        // per-direction — CARMO outbound and CARMO inbound are different codes —
        // so the stop already pins it, and the API's own detection agrees.
        // Verified against the live feed: 601 at CMO returns one destination,
        // never both.
        let departures = try? await client.departures(
            stop: stop.stopCode, line: line, serviceId: nil,
            directionId: nil, windowMinutes: nil, limit: 10
        )
        chips = Self.chips(from: departures)
        if selectedId == nil || selected == nil {
            selectedId = Self.initialSelection(in: chips, matching: opened)?.id
        }

        let resolved = await resolveSelectedTrip()
        trip = resolved

        let direction = resolved?.directionId ?? departures?.directionId ?? 0

        // The route line and the fallback stop list are both keyed on direction,
        // so they can only be asked for now.
        async let shapeTask = try? client.lineShape(line: line, directionId: direction)
        async let fallbackTask: RouteDirectionStops? =
            resolved == nil ? try? client.lineStops(line: line, directionId: direction) : nil

        shape = (await shapeTask)?.coordinates.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        } ?? []
        untimedStops = (await fallbackTask)?.stops ?? []

        // Knowing less than we hoped is not a broken screen — the line and its
        // departures are still on the page. Only a total blank is an error.
        state = journey.isEmpty && shape.isEmpty && chips.isEmpty
            ? .failed(APIError.transport("Nothing to show for this line"))
            : .loaded(())
    }

    /// Ask the API to identify the selected departure, handing over every hint
    /// its fallback can use. A 404 means "cannot identify", which is a defined
    /// outcome, not an error — and for a scheduled departure there is no id to
    /// ask by at all, so the hints are the whole question.
    private func resolveSelectedTrip() async -> ResolvedTrip? {
        guard let selected else { return nil }
        return try? await client.tripStops(
            tripId: selected.tripId,
            line: line,
            headsign: selected.destination,
            stop: stop.stopCode,
            etaMinutes: selected.etaMinutes.map { Int($0.rounded()) }
        )
    }

    // MARK: - Building the journey

    private func timedJourney(_ trip: ResolvedTrip) -> [JourneyStopDisplay] {
        guard let index = trip.index(of: stop.stopCode), let selected else {
            // Resolved, but not calling here — a wrong match rather than a
            // missing one. Showing its stops would be confidently wrong.
            return []
        }
        let anchor = selected.etaMinutes ?? 0
        let origin = trip.stops[index]

        let head = JourneyStopDisplay(
            id: origin.stopSequence,
            name: origin.stopName,
            clockText: nil,
            etaText: selected.etaText,
            tone: selected.tone,
            isOrigin: true,
            isTimepoint: origin.timepoint,
            latitude: origin.stopLat,
            longitude: origin.stopLon
        )

        let rest = trip.downstream(from: stop.stopCode, liveEtaMinutes: anchor).map { entry in
            JourneyStopDisplay(
                id: entry.stop.stopSequence,
                name: entry.stop.stopName,
                clockText: Self.clock(inMinutes: entry.etaMinutes),
                etaText: nil,
                // Never `.onTime`: green is reserved for numbers STCP is
                // actually tracking, and none of these are.
                tone: .unknown,
                isOrigin: false,
                isTimepoint: entry.stop.timepoint,
                latitude: entry.stop.stopLat,
                longitude: entry.stop.stopLon
            )
        }
        return [head] + rest
    }

    /// The line's stops from the rider's onward, with no times at all.
    private func untimedJourney() -> [JourneyStopDisplay] {
        guard let index = untimedStops.firstIndex(where: { $0.stopCode == stop.stopCode }) else { return [] }
        return untimedStops[index...].map { s in
            let isOrigin = s.stopCode == stop.stopCode
            return JourneyStopDisplay(
                id: s.sequence,
                name: s.stopName,
                clockText: nil,
                etaText: isOrigin ? selected?.etaText : nil,
                tone: isOrigin ? tone : .unknown,
                isOrigin: isOrigin,
                isTimepoint: false,
                latitude: s.lat,
                longitude: s.lon
            )
        }
    }

    // MARK: - Pure helpers

    /// Every departure as a bubble, in the order the API returned them (already
    /// sorted by time, live and scheduled interleaved).
    static func chips(from departures: StopLineDepartures?) -> [DepartureChipDisplay] {
        guard let departures else { return [] }
        return departures.departures.map { d in
            let isLive = d.source.isRealtime
            return DepartureChipDisplay(
                id: d.tripId ?? d.time,
                tripId: d.tripId,
                etaMinutes: d.etaMinutes,
                etaText: BoardViewModel.etaText(d.etaMinutes),
                clockText: d.time,
                destination: d.destination,
                isLive: isLive,
                // A timetable entry has no on-time truth to report, and the
                // API sends a null status for exactly that reason. `.unknown`
                // renders neutral, which is the whole point.
                tone: isLive ? BoardViewModel.arrivalTone(forStatus: d.status) : .unknown
            )
        }
    }

    /// Which bubble the rider tapped to get here.
    ///
    /// By trip id when both sides have one. Otherwise by ETA — the board and the
    /// departures list are separate upstream calls seconds apart, so the same
    /// bus routinely differs by a minute between them, and nearest-wins is the
    /// only match that survives that.
    static func initialSelection(in chips: [DepartureChipDisplay], matching arrival: Arrival) -> DepartureChipDisplay? {
        if let id = arrival.tripId, let exact = chips.first(where: { $0.tripId == id }) { return exact }
        guard let mine = arrival.arrivalMinutes else { return chips.first }
        return chips
            .compactMap { chip in chip.etaMinutes.map { (chip, abs($0 - mine)) } }
            .min { $0.1 < $1.1 }?.0
            ?? chips.first
    }

    /// Minutes from now -> a wall-clock "HH:MM" in the device's locale.
    ///
    /// Clock times, not "+7 min", because this list answers "when do I get
    /// there" — a question about arriving somewhere, not about waiting here.
    static func clock(inMinutes minutes: Double, from now: Date = .now) -> String {
        now.addingTimeInterval(minutes * 60).formatted(date: .omitted, time: .shortened)
    }
}

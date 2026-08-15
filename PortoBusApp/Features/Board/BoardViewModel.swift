import Foundation
import Observation
import PortoBusKit

/// Display model for one board row — everything preformatted so the View only
/// places strings and colours. `etaText` ("6 min" / "Arriving") is decided here,
/// not in a `Text` ternary (DESIGN.md §4).
struct BoardRowDisplay: Identifiable, Hashable {
    let id: String
    let line: String
    let destination: String
    let etaText: String
    let stopCode: String
    let stopName: String
    let walkText: String
    let tone: ArrivalTone
    let catchable: Bool
    let colorHex: String?
    let textColorHex: String?
}

/// Whether an arrival is running on time or late — trusts STCP's own
/// classification (`status`) rather than re-deriving a threshold from raw
/// delay minutes: STCP already absorbs sub-minute noise into "on time" (a
/// 0.8-minute delay still reports `ON_TIME`), so inventing our own cutoff
/// would risk disagreeing with what STCP's own app shows for the same bus.
/// Colours the ETA itself (green/red) rather than a separate live/not-live
/// indicator — whether a stop is tracked at all turned out to almost never
/// vary in practice, so it carried little information; on-time-vs-delayed
/// visibly does, row to row, in real data.
enum ArrivalTone: Hashable {
    case onTime
    case delayed
    /// No live status to go on — rare in observed data, but the honest
    /// fallback rather than guessing.
    case unknown
}

/// Inputs the Board needs from settings, snapshotted per load so a change in
/// Settings takes effect on the next refresh.
struct BoardConfig {
    var walkMinutes: Int
    var sortByETA: Bool
    var showUnreachable: Bool
    var homeLat: Double
    var homeLon: Double
}

@MainActor
@Observable
final class BoardViewModel {
    private(set) var state: LoadState<LocationBoard> = .idle
    /// True when the most recent *refresh over existing content* failed. Lets the
    /// UI keep showing the last board plus a subtle "couldn't refresh" note,
    /// instead of throwing away good content on one dropped request.
    private(set) var refreshFailed = false
    /// True when the origin came from the saved home coordinates because location
    /// was denied/unavailable — the UI notes it so an unexpected board makes sense.
    private(set) var usingFallbackLocation = false

    private let client: PortoBusClient
    private let location: LocationProvider

    init(client: PortoBusClient, location: LocationProvider) {
        self.client = client
        self.location = location
    }

    /// Rows ready to render. Empty until loaded.
    var rows: [BoardRowDisplay] {
        guard let board = state.value else { return [] }
        return board.departures.map { row in
            BoardRowDisplay(
                id: row.id,
                line: row.line,
                destination: row.destination,
                etaText: Self.etaText(row.etaMinutes),
                stopCode: row.stopCode,
                stopName: row.stopName,
                walkText: "\(row.walkMinutes) min walk",
                tone: Self.arrivalTone(forStatus: row.status),
                catchable: row.catchable,
                colorHex: row.color,
                textColorHex: row.textColor
            )
        }
    }

    /// A note for the empty / partial / truncated cases. Distinguishing "nothing
    /// runs" from "we couldn't look everywhere" is the whole point here
    /// (DESIGN.md §7).
    var statusNote: String? {
        guard let board = state.value else { return nil }
        if board.departures.isEmpty {
            return board.hasFailedStops
                ? "Some nearby stops didn't respond, so this may be incomplete."
                : "Nothing catchable from here right now."
        }
        if board.hasFailedStops {
            return "Some nearby stops didn't respond — a few buses may be missing."
        }
        if board.stopsTruncated == true {
            return "Showing the closest stops only; not every nearby stop was checked."
        }
        return nil
    }

    func load(config: BoardConfig) async {
        if state.isInitialLoad { state = .loading }
        refreshFailed = false

        // Resolve origin: real location, else the saved home coordinates.
        let coordinate = await location.currentCoordinate()
        usingFallbackLocation = (coordinate == nil)
        let lat = coordinate?.latitude ?? config.homeLat
        let lon = coordinate?.longitude ?? config.homeLon

        do {
            let board = try await client.board(
                lat: lat,
                lon: lon,
                walkMinutes: config.walkMinutes,
                sort: config.sortByETA ? .eta : .line,
                includeUnreachable: config.showUnreachable
            )
            state = .loaded(board)
        } catch {
            // Keep good content on a failed refresh; only show the error screen
            // when there's nothing to fall back to.
            if state.value != nil {
                refreshFailed = true
            } else {
                state = .failed(error)
            }
        }
    }

    /// Minutes → rider-facing text. 0 (or negative "already here") is "Arriving";
    /// a missing value is "—" rather than a fabricated number. Upstream minutes
    /// can be fractional, so round to a whole minute for display.
    static func etaText(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        let rounded = Int(minutes.rounded())
        if rounded <= 0 { return "Arriving" }
        return "\(rounded) min"
    }

    /// STCP's raw `status` string -> the coarse tone that colours an ETA.
    /// Shared by Board and the Lines-flow stop screen, both of which show
    /// per-arrival live status.
    static func arrivalTone(forStatus status: String?) -> ArrivalTone {
        switch status {
        case "DELAYED": return .delayed
        case "ON_TIME", "ARRIVING": return .onTime
        default: return .unknown
        }
    }
}

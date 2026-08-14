import Foundation
import Observation
import PortoBusKit

/// Identifies a Departures push and carries just enough to render the header
/// before the data loads (line badge colour, destination). Built from a board
/// row or from a stop's realtime arrival.
struct DeparturesRoute: Hashable {
    let stopCode: String
    let line: String
    let destination: String?
    let colorHex: String?
    let textColorHex: String?

    init(stopCode: String, line: String, destination: String?, colorHex: String?, textColorHex: String?) {
        self.stopCode = stopCode
        self.line = line
        self.destination = destination
        self.colorHex = colorHex
        self.textColorHex = textColorHex
    }

    init(row: BoardRowDisplay) {
        self.init(stopCode: row.stopCode, line: row.line, destination: row.destination,
                  colorHex: row.colorHex, textColorHex: row.textColorHex)
    }
}

/// One combined departure, preformatted. The `isRealtime` flag drives the two
/// unmissably different treatments the screen exists to show (DESIGN.md §6.2):
/// a solid line-coloured pill with the live ETA, or a faded outline with the
/// scheduled clock time.
struct DepartureDisplay: Identifiable, Hashable {
    let id: String
    let destination: String
    let isRealtime: Bool
    /// Realtime: the ETA ("3 min" / "Arriving"). Scheduled: the clock time ("16:38").
    let primary: String
    /// Realtime only: clock time and/or delay ("16:17 · 5 min late"). Nil when scheduled.
    let detail: String?
    let colorHex: String?
    let textColorHex: String?
}

@MainActor
@Observable
final class DeparturesViewModel {
    private(set) var state: LoadState<StopLineDepartures> = .idle

    private let client: PortoBusClient
    let route: DeparturesRoute

    init(client: PortoBusClient, route: DeparturesRoute) {
        self.client = client
        self.route = route
    }

    var rows: [DepartureDisplay] {
        guard let payload = state.value else { return [] }
        return payload.departures.enumerated().map { index, dep in
            let realtime = dep.source.isRealtime
            return DepartureDisplay(
                id: "\(index)-\(dep.time)-\(dep.destination)",
                destination: dep.destination,
                isRealtime: realtime,
                primary: realtime ? BoardViewModel.etaText(dep.etaMinutes) : dep.time,
                detail: realtime ? Self.realtimeDetail(dep) : nil,
                colorHex: dep.color ?? route.colorHex,
                textColorHex: dep.textColor ?? route.textColorHex
            )
        }
    }

    var isEmpty: Bool {
        if let payload = state.value { return payload.departures.isEmpty }
        return false
    }

    func load() async {
        if state.isInitialLoad { state = .loading }
        do {
            let payload = try await client.departures(stop: route.stopCode, line: route.line)
            state = .loaded(payload)
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }

    /// Clock time plus a delay phrase for live entries. "16:17 · 5 min late".
    /// Delay is fractional upstream; round to whole minutes and treat anything
    /// under half a minute as on time.
    private static func realtimeDetail(_ dep: CombinedDeparture) -> String? {
        var parts: [String] = [dep.time]
        if let delay = dep.delayMinutes {
            let m = Int(delay.rounded())
            if m > 0 { parts.append("\(m) min late") }
            else if m < 0 { parts.append("\(-m) min early") }
        }
        return parts.joined(separator: " · ")
    }
}

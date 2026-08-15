import Foundation
import Observation
import PortoBusKit

/// One arrival at a stop, preformatted. Informational only — the station's
/// live board (up to ~1h ahead per line) is already the full picture, so
/// rows don't drill into anything further. The ETA is coloured by
/// `tone` (on-time/delayed), same rule and shared helper as Board.
struct StopArrivalDisplay: Identifiable, Hashable {
    let id: String
    let line: String
    let destination: String
    let etaText: String
    let tone: ArrivalTone
    let colorHex: String?
    let textColorHex: String?
}

/// A stop's live board, across every line serving it — not filtered to one
/// line. Reached from the Lines flow: Lines -> a line -> one of its stops.
/// The point of landing here rather than jumping straight to a single line's
/// Departures is exactly what a shared stop needs: if Santa Justa serves 701,
/// 702 and 703, all three should be visible, not just the one you drilled in
/// from.
@MainActor
@Observable
final class StopDetailViewModel {
    private(set) var state: LoadState<RealtimeStop> = .idle

    private let client: PortoBusClient
    let stop: Stop

    init(client: PortoBusClient, stop: Stop) {
        self.client = client
        self.stop = stop
    }

    var stopName: String { state.value?.stopName ?? stop.name }

    var arrivals: [StopArrivalDisplay] {
        guard let realtime = state.value else { return [] }
        return realtime.arrivals.enumerated().map { index, a in
            StopArrivalDisplay(
                id: "\(index)-\(a.line)-\(a.destination)",
                line: a.line,
                destination: a.destination,
                etaText: BoardViewModel.etaText(a.arrivalMinutes),
                tone: BoardViewModel.arrivalTone(forStatus: a.status),
                colorHex: a.color,
                textColorHex: a.textColor
            )
        }
    }

    var isEmpty: Bool {
        if let realtime = state.value { return realtime.arrivals.isEmpty }
        return false
    }

    func load() async {
        if state.isInitialLoad { state = .loading }
        do {
            let realtime = try await client.realtime(stop: stop.stopCode)
            state = .loaded(realtime)
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }
}

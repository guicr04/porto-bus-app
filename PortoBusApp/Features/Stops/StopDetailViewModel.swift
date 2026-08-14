import Foundation
import Observation
import PortoBusKit

/// One arrival at a stop, preformatted. Tapping it opens the combined Departures
/// screen for that line — hence the embedded route.
struct StopArrivalDisplay: Identifiable, Hashable {
    let id: String
    let line: String
    let destination: String
    let etaText: String
    let colorHex: String?
    let textColorHex: String?
    let route: DeparturesRoute
}

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
                colorHex: a.color,
                textColorHex: a.textColor,
                route: DeparturesRoute(
                    stopCode: stop.stopCode,
                    line: a.line,
                    destination: a.destination,
                    colorHex: a.color,
                    textColorHex: a.textColor
                )
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

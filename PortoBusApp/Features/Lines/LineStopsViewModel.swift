import Foundation
import Observation
import PortoBusKit

/// Lines whose route physically loops back to its own starting point rather
/// than running out-and-back. They have only one meaningful direction, so no
/// invert control is offered for them.
private let circularLines: Set<String> = ["300", "301"]

@MainActor
@Observable
final class LineStopsViewModel {
    private(set) var state: LoadState<RouteDirectionStops> = .idle
    private(set) var directionId: Int = 0

    private let client: PortoBusClient
    let line: Line

    init(client: PortoBusClient, line: Line) {
        self.client = client
        self.line = line
    }

    var isCircular: Bool { circularLines.contains(line.line) }
    var stops: [DirectionStop] { state.value?.stops ?? [] }

    func load() async {
        if state.isInitialLoad { state = .loading }
        do {
            let result = try await client.lineStops(line: line.line, directionId: directionId)
            state = .loaded(result)
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }

    /// Flips direction_id 0<->1 and reloads. A no-op for circular lines — the
    /// view hides the control for them, but guard here too since state is the
    /// source of truth, not the button's visibility.
    func invertDirection() async {
        guard !isCircular else { return }
        directionId = directionId == 0 ? 1 : 0
        state = .loading
        await load()
    }
}

import Foundation
import Observation
import PortoBusKit

@MainActor
@Observable
final class StopsViewModel {
    private(set) var state: LoadState<[Stop]> = .idle

    private let client: PortoBusClient
    private var searchTask: Task<Void, Never>?

    init(client: PortoBusClient) {
        self.client = client
    }

    /// Debounced search (~300 ms). Each keystroke cancels the previous pending
    /// request so a fast typist fires one call, not one per letter.
    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.load(query: trimmed.isEmpty ? nil : trimmed)
        }
    }

    var stops: [Stop] { state.value ?? [] }

    var isEmptyResult: Bool {
        if case .loaded(let stops) = state { return stops.isEmpty }
        return false
    }

    func load(query: String?) async {
        if state.isInitialLoad { state = .loading }
        do {
            let stops = try await client.stops(query: query, limit: 50)
            state = .loaded(stops)
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }
}

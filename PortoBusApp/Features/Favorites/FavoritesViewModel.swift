import Foundation
import Observation
import PortoBusKit

/// One favorited station, rendered with its soonest live arrival across every
/// line serving it — a preview, not the full board. Tapping it pushes into
/// the same all-lines `StopDetailView` the Lines flow uses, which is where
/// the rest of what's coming is.
struct FavoriteRowDisplay: Identifiable, Hashable {
    let id: String
    let stop: Stop
    let stopName: String
    /// Nil when nothing is currently tracked at this stop.
    let line: String?
    let destination: String?
    let etaText: String
    let isRealtime: Bool
    let colorHex: String?
    let textColorHex: String?
}

@MainActor
@Observable
final class FavoritesViewModel {
    private(set) var state: LoadState<[FavoriteRowDisplay]> = .idle

    private let client: PortoBusClient
    private let store: FavoritesStore

    init(client: PortoBusClient, store: FavoritesStore) {
        self.client = client
        self.store = store
    }

    var isEmpty: Bool {
        if case .loaded(let rows) = state { return rows.isEmpty }
        return false
    }

    /// Fetches each favorited station's live board in parallel — there's no
    /// "give me several arbitrary stops at once" endpoint (Board's server-side
    /// multi-stop poll is scoped to stops near one origin, not an arbitrary
    /// set). A station that fails to load still shows, with a blank ETA,
    /// rather than disappearing from the list.
    func load() async {
        let favorites = store.favorites
        guard !favorites.isEmpty else {
            state = .loaded([])
            return
        }
        if state.isInitialLoad { state = .loading }

        let rows = await withTaskGroup(of: FavoriteRowDisplay.self) { group in
            for stop in favorites {
                group.addTask { [client] in
                    await Self.fetchRow(for: stop, client: client)
                }
            }
            var results: [FavoriteRowDisplay] = []
            for await row in group { results.append(row) }
            return results
        }

        // Concurrent completion order isn't the user's favorited order — restore it.
        let order = Dictionary(uniqueKeysWithValues: favorites.enumerated().map { ($1.stopCode, $0) })
        state = .loaded(rows.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) })
    }

    private static func fetchRow(for stop: Stop, client: PortoBusClient) async -> FavoriteRowDisplay {
        do {
            let realtime = try await client.realtime(stop: stop.stopCode)
            let soonest = realtime.arrivals.min { ($0.arrivalMinutes ?? .greatestFiniteMagnitude) < ($1.arrivalMinutes ?? .greatestFiniteMagnitude) }
            return FavoriteRowDisplay(
                id: stop.stopCode,
                stop: stop,
                stopName: realtime.stopName ?? stop.name,
                line: soonest?.line,
                destination: soonest?.destination,
                etaText: soonest.map { BoardViewModel.etaText($0.arrivalMinutes) } ?? "—",
                isRealtime: realtime.dataSource == "realtime",
                colorHex: soonest?.color,
                textColorHex: soonest?.textColor
            )
        } catch {
            return FavoriteRowDisplay(
                id: stop.stopCode,
                stop: stop,
                stopName: stop.name,
                line: nil,
                destination: nil,
                etaText: "—",
                isRealtime: false,
                colorHex: nil,
                textColorHex: nil
            )
        }
    }
}

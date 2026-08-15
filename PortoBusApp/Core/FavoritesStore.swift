import Foundation
import Observation
import PortoBusKit

/// Persisted favorites — specific stations the rider wants fast access to,
/// pinned from a Board row's stop or from the shared stop screen in the Lines
/// flow. Identity is the station (`stopCode`), not a station+line pair: a
/// favorited stop shows every line currently arriving there, same as the
/// Lines-flow stop screen, not just whichever line you happened to favorite it
/// from.
@Observable
@MainActor
final class FavoritesStore {
    private(set) var favorites: [Stop] = []

    private let defaults: UserDefaults
    private let key = "favorites.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Stop].self, from: data) {
            favorites = decoded
        }
    }

    func isFavorite(stopCode: String) -> Bool {
        favorites.contains { $0.stopCode == stopCode }
    }

    /// Adds `stop` if it isn't already favorited, else removes the existing
    /// entry. Safe to call from any of the several screens that can favorite
    /// the same station.
    func toggle(_ stop: Stop) {
        if let index = favorites.firstIndex(where: { $0.stopCode == stop.stopCode }) {
            favorites.remove(at: index)
        } else {
            favorites.append(stop)
        }
        persist()
    }

    func remove(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: key)
    }
}

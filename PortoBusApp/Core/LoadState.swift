import Foundation

/// The single state enum every screen's ViewModel exposes. Loading, empty and
/// error are handled by construction rather than remembered as scattered
/// booleans. Pure Swift — no SwiftUI — so it lives comfortably in the ViewModel
/// layer (see DESIGN.md §4).
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(Error)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// True while the very first load is in flight (nothing to show yet).
    /// A refresh over existing content keeps `.loaded`, so this stays false and
    /// the screen shows content-plus-spinner instead of a blank loading view.
    var isInitialLoad: Bool {
        switch self {
        case .idle, .loading: return true
        default: return false
        }
    }
}

import SwiftUI
import PortoBusKit

/// The bottom sheet behind a tapped pin: that stop's live board.
///
/// Reuses `StopDetailViewModel` unchanged — it already answers "everything
/// arriving at this stop, across every line", which is exactly what a map pin
/// should open (DESIGN.md §6.4). The sheet is a different frame around the same
/// content, not a second implementation of it.
struct MapStopSheet: View {
    let stop: Stop
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: StopDetailViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
                }
            }
            .navigationTitle(model?.stopName ?? stop.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
            }
        }
        // The sheet is drawn over the floating bar, so nothing inside it — this
        // screen or anything pushed from it — should reserve room for the bar.
        .environment(\.floatingBarVisible, false)
        // ...and it is drawn over the map, which is the one that should render
        // any route this sheet describes.
        .environment(\.hostDrawsRoute, true)
        .task(id: scenePhase) { await runRefreshLoop() }
    }

    private var favoriteButton: some View {
        let named = Stop(
            stopCode: stop.stopCode,
            name: model?.stopName ?? stop.name,
            lat: stop.lat,
            lon: stop.lon
        )
        let isFavorite = services.favorites.isFavorite(stopCode: stop.stopCode)
        return Button {
            services.favorites.toggle(named)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(Color.favorite)
        }
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    /// Same 20-second cadence as the pushed stop screen, and it stops when the
    /// sheet goes away — a dismissed sheet must not keep polling.
    private func runRefreshLoop() async {
        if model == nil, let client = services.makeClient() {
            model = StopDetailViewModel(client: client, stop: stop)
        }
        guard scenePhase == .active, let model else { return }
        while !Task.isCancelled {
            await model.load()
            try? await Task.sleep(for: .seconds(20))
        }
    }

    @ViewBuilder
    private func content(_ model: StopDetailViewModel) -> some View {
        LoadStateView(state: model.state, retry: { Task { await model.load() } }) { _ in
            if model.isEmpty {
                StopBoardEmptyView()
            } else {
                StopBoardList(stop: model.stop, groups: model.lineGroups)
            }
        }
        .refreshable { await model.load() }
    }
}

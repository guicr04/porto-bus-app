import SwiftUI
import PortoBusKit

/// A stop's live arrivals, one row per line and direction. Each row follows
/// that bus: where it goes after here, and when (DESIGN.md §11.1). The toolbar
/// heart favorites the whole station, not one line at it, since a favorite is a
/// place you check, not a single route through it.
///
/// The rows themselves live in `StopBoardList`, shared with the Map's sheet.
struct StopDetailView: View {
    let stop: Stop
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: StopDetailViewModel?

    var body: some View {
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
            ToolbarItem(placement: .topBarTrailing) {
                let favoriteStop = Stop(stopCode: stop.stopCode, name: model?.stopName ?? stop.name, lat: stop.lat, lon: stop.lon)
                let isFavorite = services.favorites.isFavorite(stopCode: stop.stopCode)
                Button {
                    services.favorites.toggle(favoriteStop)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(Color.favorite)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
        .task(id: scenePhase) { await runRefreshLoop() }
    }

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
                    .floatingBarInset()
            }
        }
        .refreshable { await model.load() }
    }
}

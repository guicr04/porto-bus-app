import SwiftUI
import PortoBusKit

/// A stop's live arrivals, across every line serving it — informational rows,
/// not links: this board already covers what's coming for the next ~hour per
/// line, so there's nothing further to drill into. The toolbar heart favorites
/// the whole station, not one line at it, since a favorite is a place you
/// check, not a single route through it.
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
                ContentUnavailableView("No arrivals", systemImage: "clock.badge.xmark",
                                       description: Text("Nothing is currently tracked at this stop."))
            } else {
                List(model.arrivals) { arrival in
                    HStack(spacing: 12) {
                        LineBadge(line: arrival.line, color: arrival.colorHex, textColor: arrival.textColorHex)
                        Text(arrival.destination).font(.headline).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(arrival.etaText)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color(tone: arrival.tone))
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .floatingBarInset()
            }
        }
        .refreshable { await model.load() }
    }
}

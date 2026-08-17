import SwiftUI
import PortoBusKit

/// Root of the Favorites tab: pinned stations, each previewed with its
/// soonest live arrival across every line. Tap through for the full board at
/// that station (every line, not just the preview's one). Foreground-only
/// refresh, same cadence as Board.
struct FavoritesScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: FavoritesViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
            }
        }
        .navigationTitle("Favorites")
        .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
        .task(id: scenePhase) { await runRefreshLoop() }
    }

    private func runRefreshLoop() async {
        if model == nil, let client = services.makeClient() {
            model = FavoritesViewModel(client: client, store: services.favorites)
        }
        guard scenePhase == .active, let model else { return }
        while !Task.isCancelled {
            await model.load()
            try? await Task.sleep(for: .seconds(20))
        }
    }

    @ViewBuilder
    private func content(_ model: FavoritesViewModel) -> some View {
        LoadStateView(state: model.state, retry: { Task { await model.load() } }) { _ in
            if model.isEmpty {
                ContentUnavailableView {
                    Label("No favorites yet", systemImage: "heart")
                } description: {
                    Text("Swipe a bus on the Board, or tap the heart on a stop in the Lines flow, to pin it here.")
                }
            } else {
                List {
                    ForEach(favoriteRows(model)) { row in
                        NavigationLink(value: row.stop) {
                            FavoriteRowView(row: row)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                services.favorites.toggle(row.stop)
                                Task { await model.load() }
                            } label: {
                                Label("Remove", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .floatingBarInset()
            }
        }
        .refreshable { await model.load() }
    }

    private func favoriteRows(_ model: FavoritesViewModel) -> [FavoriteRowDisplay] {
        if case .loaded(let rows) = model.state { return rows }
        return []
    }
}

/// A favorite's row: station name, and a preview of its soonest arrival
/// (line badge, destination, ETA) — or a quiet "nothing right now" when the
/// station has no live arrivals to show.
///
/// Rendered like Board's rows and the stop screens': badge, where it's going,
/// and an ETA coloured by its tone. It used to carry a green dot and the word
/// "live" beside the time — the indicator §7 records as *replaced* by
/// tone-colouring, which every other screen had moved on from and this one
/// hadn't.
struct FavoriteRowView: View {
    let row: FavoriteRowDisplay

    var body: some View {
        HStack(spacing: 12) {
            if let line = row.line {
                LineBadge(line: line, color: row.colorHex, textColor: row.textColorHex)
            } else {
                LineBadge(line: "—", color: nil, textColor: nil)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.stopName)
                    .font(.headline)
                    .lineLimit(1)
                Text(row.destination ?? "Nothing tracked right now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(row.etaText)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(tone: row.tone))
        }
        .padding(.vertical, 4)
    }
}

#Preview("Favorites") {
    NavigationStack { FavoritesScreen() }
        .environment(AppServices.preview())
}

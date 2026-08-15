import SwiftUI
import PortoBusKit

/// Root of the Board tab. Owns the ViewModel (built once the client is
/// available) and the foreground-only refresh loop.
struct BoardScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BoardViewModel?

    var body: some View {
        Group {
            if let model {
                BoardContent(model: model, config: config)
            } else {
                // Only reachable when the base URL is malformed.
                ContentUnavailableView {
                    Label("Can't reach the server", systemImage: "network.slash")
                } description: {
                    Text("Check the server address in Settings.")
                }
            }
        }
        .navigationTitle("Board")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .navigationDestination(for: Route.self) { $0.destination }
        .task(id: scenePhase) { await runRefreshLoop() }
    }

    private var config: BoardConfig {
        let s = services.settings
        return BoardConfig(
            walkMinutes: s.walkMinutes,
            sortByETA: s.sortByETA,
            showUnreachable: s.showUnreachable,
            homeLat: s.homeLat,
            homeLon: s.homeLon
        )
    }

    /// Loads on becoming active and re-polls every 20s while foregrounded. The
    /// API caches live arrivals for 15s, so faster polling only wastes battery
    /// (DESIGN.md §7). Cancelled automatically when the tab leaves the screen or
    /// the app backgrounds (scenePhase change re-runs this `.task`).
    private func runRefreshLoop() async {
        if model == nil, let client = services.makeClient() {
            model = BoardViewModel(client: client, location: services.location)
        }
        guard scenePhase == .active, let model else { return }

        while !Task.isCancelled {
            await model.load(config: config)
            try? await Task.sleep(for: .seconds(20))
        }
    }
}

/// The loaded Board: a list of rows, a "using home location" note when relevant,
/// and the empty/partial status line.
private struct BoardContent: View {
    let model: BoardViewModel
    let config: BoardConfig
    @Environment(AppServices.self) private var services

    var body: some View {
        LoadStateView(state: model.state, retry: { Task { await model.load(config: config) } }) { _ in
            List {
                if model.usingFallbackLocation {
                    Label("Using your saved home location", systemImage: "house")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }

                if let note = model.statusNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }

                // Informational, not a NavigationLink: the ETA is the whole
                // answer this row exists to give. Drilling into a single
                // line's schedule from here duplicated what the Lines tab
                // already shows for that stop.
                ForEach(model.rows) { row in
                    BoardRowView(row: row)
                        .swipeActions(edge: .leading) {
                            FavoriteSwipeButton(stop: Stop(stopCode: row.stopCode, name: row.stopName, lat: nil, lon: nil))
                        }
                }
            }
            .listStyle(.plain)
            .floatingBarInset()
            .overlay(alignment: .top) {
                if model.refreshFailed {
                    RefreshFailedBanner()
                }
            }
        }
        .refreshable { await model.load(config: config) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Toggle("Sort by soonest", isOn: sortBinding)
                    Toggle("Show unreachable buses", isOn: unreachableBinding)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var sortBinding: Binding<Bool> {
        Binding(get: { services.settings.sortByETA },
                set: { services.settings.sortByETA = $0; Task { await model.load(config: config) } })
    }

    private var unreachableBinding: Binding<Bool> {
        Binding(get: { services.settings.showUnreachable },
                set: { services.settings.showUnreachable = $0; Task { await model.load(config: config) } })
    }
}

private struct RefreshFailedBanner: View {
    var body: some View {
        Text("Couldn't refresh — showing last known times")
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 4)
    }
}

/// One board row: line badge, destination + origin stop, and the bus's ETA as
/// the dominant figure (DESIGN.md §6.1 — the arrival is a fact; the walk is
/// supporting context the rider judges for themselves). The ETA itself is
/// coloured by on-time/delayed status rather than carrying a separate live
/// indicator — see `ArrivalTone`.
struct BoardRowView: View {
    let row: BoardRowDisplay

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: row.line, color: row.colorHex, textColor: row.textColorHex)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.destination)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(row.stopName)
                    Text("·")
                    Text(row.walkText)
                }
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
        .opacity(row.catchable ? 1 : 0.5)
    }
}

#Preview("Board") {
    NavigationStack { BoardScreen() }
        .environment(AppServices.preview())
}

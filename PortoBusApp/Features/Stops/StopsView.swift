import SwiftUI
import PortoBusKit

/// Root of the Stops tab: search stops by name, tap through to a stop's live
/// board, then to a line's combined departures. Registers the navigation
/// destinations for this tab's stack.
struct StopsScreen: View {
    @Environment(AppServices.self) private var services
    @State private var model: StopsViewModel?
    @State private var query = ""

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
            }
        }
        .navigationTitle("Stops")
        .searchable(text: $query, prompt: "Search stops")
        .onChange(of: query) { _, newValue in model?.search(newValue) }
        .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
        .navigationDestination(for: DeparturesRoute.self) { DeparturesView(route: $0) }
        .navigationDestination(for: Route.self) { $0.destination }
        .task {
            if model == nil, let client = services.makeClient() {
                model = StopsViewModel(client: client)
                await model?.load(query: nil)
            }
        }
    }

    @ViewBuilder
    private func content(_ model: StopsViewModel) -> some View {
        LoadStateView(state: model.state, retry: { Task { await model.load(query: query.isEmpty ? nil : query) } }) { _ in
            if model.isEmptyResult {
                ContentUnavailableView.search(text: query)
            } else {
                List(model.stops) { stop in
                    NavigationLink(value: stop) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name).font(.body)
                            Text(stop.stopCode).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .floatingBarInset()
            }
        }
    }
}

/// A stop's live arrivals board. Each arrival taps through to its line's
/// combined departures — the same destination the Board uses.
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
                    NavigationLink(value: arrival.route) {
                        HStack(spacing: 12) {
                            LineBadge(line: arrival.line, color: arrival.colorHex, textColor: arrival.textColorHex)
                            Text(arrival.destination).font(.headline).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(arrival.etaText)
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .floatingBarInset()
            }
        }
        .refreshable { await model.load() }
    }
}

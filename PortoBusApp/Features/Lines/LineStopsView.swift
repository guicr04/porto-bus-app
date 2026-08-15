import SwiftUI
import PortoBusKit

/// Ordered stops for one line+direction. A toolbar button flips direction_id
/// 0<->1 — except on circular lines (300, 301), which run one loop back to
/// their own start and have no meaningful "other direction" to invert to.
struct LineStopsView: View {
    let line: Line
    @Environment(AppServices.self) private var services
    @State private var model: LineStopsViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
            }
        }
        .navigationTitle(line.line)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil, let client = services.makeClient() {
                model = LineStopsViewModel(client: client, line: line)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: LineStopsViewModel) -> some View {
        LoadStateView(state: model.state, retry: { Task { await model.load() } }) { _ in
            if model.stops.isEmpty {
                ContentUnavailableView("No stops found", systemImage: "mappin.slash")
            } else {
                List(model.stops) { stop in
                    // Push into the shared stop screen — every line serving
                    // this stop, not just the one we drilled in from. A stop
                    // shared by several lines (e.g. Santa Justa: 701/702/703)
                    // should show all of them, not just this one.
                    NavigationLink(value: Stop(stopCode: stop.stopCode, name: stop.stopName, lat: stop.lat, lon: stop.lon)) {
                        Text(stop.stopName)
                    }
                }
                .listStyle(.plain)
                .floatingBarInset()
            }
        }
        .toolbar {
            if !model.isCircular {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.invertDirection() }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Reverse direction")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LineStopsView(line: Line(line: "305", description: "Cordoaria - Matosinhos", routeId: "305_0", color: "#187EC2", textColor: "#FFFFFF"))
    }
    .environment(AppServices.preview())
}

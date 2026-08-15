import SwiftUI
import PortoBusKit

/// Root of the Lines tab: every line, ordered by number and coloured by its
/// official GTFS route colour, drilling down to its stops. Plain push
/// navigation throughout — Lines -> stops for a line+direction -> the shared
/// stop screen (every line currently serving that stop). No accordion, no
/// inline expansion. Registers the destinations for this tab's stack.
struct LinesScreen: View {
    @Environment(AppServices.self) private var services
    @State private var model: LinesViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
            }
        }
        .navigationTitle("Lines")
        .navigationDestination(for: Line.self) { LineStopsView(line: $0) }
        .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
        .task {
            if model == nil, let client = services.makeClient() {
                model = LinesViewModel(client: client)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: LinesViewModel) -> some View {
        LoadStateView(state: model.state, retry: { Task { await model.load() } }) { _ in
            List(model.lines) { line in
                NavigationLink(value: line) {
                    HStack(spacing: 12) {
                        LineBadge(line: line.line, color: line.color, textColor: line.textColor)
                        Text(line.description)
                            .font(.body)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
            .floatingBarInset()
        }
        .refreshable { await model.load() }
    }
}

#Preview {
    NavigationStack { LinesScreen() }
        .environment(AppServices.preview())
}

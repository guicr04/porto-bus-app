import SwiftUI
import PortoBusKit

/// Combined live + scheduled departures for one line at one stop. Pushed from a
/// board row or a stop's arrivals.
struct DeparturesView: View {
    let route: DeparturesRoute
    @Environment(AppServices.self) private var services
    @State private var model: DeparturesViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
            }
        }
        .navigationTitle("Line \(route.line)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil, let client = services.makeClient() {
                model = DeparturesViewModel(client: client, route: route)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: DeparturesViewModel) -> some View {
        LoadStateView(state: model.state, retry: { Task { await model.load() } }) { _ in
            if model.isEmpty {
                ContentUnavailableView("No departures", systemImage: "clock.badge.xmark",
                                       description: Text("Nothing scheduled or tracked for line \(route.line) here right now."))
            } else {
                List {
                    Section {
                        ForEach(model.rows) { DepartureRowView(row: $0) }
                    } header: {
                        legend
                    }
                }
                .listStyle(.plain)
                .floatingBarInset()
            }
        }
        .refreshable { await model.load() }
    }

    /// A tiny legend so the two treatments are self-explanatory the first time.
    private var legend: some View {
        HStack(spacing: 14) {
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
            Label("Scheduled", systemImage: "clock")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

/// Realtime → solid pill in the line colour with the ETA. Scheduled → faded
/// outline with the clock time. If these ever look alike the screen has failed
/// its one job (DESIGN.md §6.2).
struct DepartureRowView: View {
    let row: DepartureDisplay

    private var lineColor: Color { Color(hex: row.colorHex) ?? .accentColor }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.destination)
                    .font(.headline)
                    .lineLimit(1)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            timePill
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var timePill: some View {
        if row.isRealtime {
            Text(row.primary)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color(hex: row.textColorHex) ?? .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(lineColor, in: Capsule())
        } else {
            Text(row.primary)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(.secondary.opacity(0.4)))
        }
    }
}

#Preview("Departures") {
    NavigationStack {
        DeparturesView(route: DeparturesRoute(
            stopCode: "CMO", line: "300", destination: "Aliados",
            colorHex: "#417DBD", textColorHex: "#FFFFFF"))
    }
    .environment(AppServices.preview())
}

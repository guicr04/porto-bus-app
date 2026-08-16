import MapKit
import SwiftUI
import PortoBusKit

/// One bus, followed: the stops it calls at after yours, when it should reach
/// each of them, and every other departure of that line you could take instead
/// (DESIGN.md §11.1, Phase 2).
///
/// **The route is drawn on the Map tab's own map, not here.** Reached from the
/// map's stop sheet, this screen is a card sitting *over* a map — giving it a
/// second, smaller map of its own put the useful one behind the useless one. It
/// publishes to `RouteOverlay` instead and lets the real map render it. Reached
/// from the Lines tab there is no map behind, so it draws its own inline; the
/// environment says which situation this is.
///
/// Deliberately not a directions screen. There is no "get there" button: this
/// app answers "what can I catch", and routing is the `/journey` case that
/// isn't built.
struct LineDetailView: View {
    let stop: Stop
    let arrival: Arrival
    let line: String

    @Environment(AppServices.self) private var services
    @Environment(\.hostDrawsRoute) private var hostDrawsRoute
    @Environment(\.floatingBarVisible) private var floatingBarVisible
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: LineDetailViewModel?
    @State private var camera: MapCameraPosition = .automatic
    @State private var framedRoute: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
            }
        }
        .navigationTitle("Line \(line)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) { await runRefreshLoop() }
        // Leaving takes the route with it. Without this the map keeps drawing a
        // line for a bus nobody is looking at any more.
        .onDisappear { if hostDrawsRoute { services.route.clear() } }
    }

    /// Same 20-second cadence as the stop board it came from: the anchor is a
    /// live ETA, so every projected time below it goes stale at the same rate.
    private func runRefreshLoop() async {
        if model == nil, let client = services.makeClient() {
            model = LineDetailViewModel(client: client, stop: stop, arrival: arrival, line: line)
        }
        guard scenePhase == .active, let model else { return }
        while !Task.isCancelled {
            await model.load()
            publishRoute(model)
            try? await Task.sleep(for: .seconds(20))
        }
    }

    @ViewBuilder
    private func content(_ model: LineDetailViewModel) -> some View {
        LoadStateView(state: model.state, retry: { Task { await model.load() } }) { _ in
            ScrollView {
                VStack(spacing: 0) {
                    if !hostDrawsRoute { inlineMap(model) }
                    header(model)
                    if !model.chips.isEmpty { departures(model) }
                    if let caveat = model.caveat { caveatNote(caveat) }
                    journey(model)
                }
            }
            .floatingBarInsetIfVisible(floatingBarVisible)
        }
        .refreshable { await model.load() }
    }

    // MARK: - The route

    /// Hand the route to the Map tab. Same payload the inline map would draw.
    private func publishRoute(_ model: LineDetailViewModel) {
        guard hostDrawsRoute else { return }
        services.route.show(
            key: model.routeKey,
            coordinates: model.shape,
            stops: model.routeStops.map {
                RouteOverlay.Stop(
                    id: $0.id, name: $0.name,
                    latitude: $0.latitude, longitude: $0.longitude,
                    isOrigin: $0.isOrigin, isTerminus: $0.isTerminus
                )
            },
            colorHex: model.colorHex
        )
    }

    /// The Lines-tab fallback: no map behind this screen, so it brings one.
    private func inlineMap(_ model: LineDetailViewModel) -> some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            if model.shape.count > 1 {
                MapPolyline(coordinates: model.shape)
                    .stroke(routeColor(model), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(model.routeStops) { item in
                Annotation(
                    item.name,
                    coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude),
                    anchor: .center
                ) {
                    RouteStopDot(isOrigin: item.isOrigin, isTerminus: item.isTerminus, color: routeColor(model))
                }
                // Titles left on, and left to MapKit: it declutters colliding
                // labels as the map zooms, which is the only reason showing a
                // name per stop is viable on a 50-stop route at all.
                .annotationTitles(.automatic)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excluding([.publicTransport])))
        .frame(height: 220)
        .onChange(of: model.routeKey) { frameRoute(model) }
        .onAppear { frameRoute(model) }
    }

    /// Fit the map to the journey once per selected departure — not on every
    /// 20-second refresh, because a map that snaps back while you are panning
    /// it is unusable.
    private func frameRoute(_ model: LineDetailViewModel) {
        guard framedRoute != model.routeKey else { return }
        let points = model.routeStops.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard let region = MKCoordinateRegion.fitting(points) else { return }
        framedRoute = model.routeKey
        camera = .region(region)
    }

    private func routeColor(_ model: LineDetailViewModel) -> Color {
        Color(hex: model.colorHex) ?? .accentColor
    }

    // MARK: - Header

    private func header(_ model: LineDetailViewModel) -> some View {
        HStack(spacing: 12) {
            LineBadge(line: line, color: model.colorHex, textColor: model.textColorHex, size: .large)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.destination)
                    .font(.headline)
                    .lineLimit(1)
                Text("from \(model.originName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(model.etaText)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(tone: model.tone))
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
    }

    // MARK: - The departures row

    private func departures(_ model: LineDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Departures from \(model.originName)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.chips) { chip in
                        Button {
                            // Republish afterwards: `select` reloads directly
                            // rather than going through the refresh loop, so
                            // without this the map keeps drawing the previous
                            // departure's route.
                            Task {
                                await model.select(chip.id)
                                publishRoute(model)
                            }
                        } label: {
                            DepartureBubble(chip: chip, isSelected: chip.id == model.selectedId)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                // Room for the selected bubble's ring, which would otherwise be
                // clipped by the scroll view's bounds.
                .padding(.vertical, 3)
            }
        }
        .padding(.bottom, 14)
    }

    private func caveatNote(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 12)
    }

    // MARK: - The stops ahead

    @ViewBuilder
    private func journey(_ model: LineDetailViewModel) -> some View {
        if model.isResolving && model.journey.isEmpty {
            // Tapping a bubble drops the old trip before the new one arrives.
            // Hold the space with a spinner: the empty-state card would be both
            // a lie and a flicker.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if model.isEmptyAfterLoading {
            ContentUnavailableView(
                "Nowhere to follow",
                systemImage: "signpost.right.and.left",
                description: Text("This bus's route isn't in the timetable we hold.")
            )
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stops ahead")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 6)

                ForEach(Array(model.journey.enumerated()), id: \.element.id) { index, item in
                    JourneyRow(
                        item: item,
                        color: routeColor(model),
                        isFirst: index == 0,
                        isLast: index == model.journey.count - 1
                    )
                }
            }
            .padding(.bottom, 8)
        }
    }
}

/// One departure, as a tappable bubble: when it leaves and at what clock time.
///
/// Selection is a ring rather than a fill. A filled chip would have to pick a
/// background colour, and the one piece of colour already on this row means
/// something specific — green is "STCP is tracking this bus" (§7) — so spending
/// fill on selection would put the two in competition.
private struct DepartureBubble: View {
    let chip: DepartureChipDisplay
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(chip.etaText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(chip.isLive ? Color(tone: chip.tone) : Color.primary)
            Text(chip.clockText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chip.etaText), \(chip.isLive ? "tracked" : "scheduled"), at \(chip.clockText)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A stop as drawn on a map.
///
/// Three weights, following Apple Maps: the ends of the line and the rider's own
/// stop are **filled** discs — the stops that say what the line is and where you
/// join it — and everything between them is a hollow ring. The rings are thin on
/// purpose; at 2.5pt on a 10pt circle the stroke was most of the dot, which read
/// as heavy blobs rather than stops.
struct RouteStopDot: View {
    let isOrigin: Bool
    var isTerminus: Bool = false
    let color: Color

    private var isFilled: Bool { isOrigin || isTerminus }
    private var size: CGFloat { isOrigin ? 15 : (isTerminus ? 12 : 9) }

    var body: some View {
        Circle()
            .fill(isFilled ? color : Color(.systemBackground))
            .stroke(isFilled ? Color(.systemBackground) : color, lineWidth: isFilled ? 2 : 1.5)
            .frame(width: size, height: size)
            .shadow(radius: 1)
    }
}

/// One stop on the journey, with the rail running through it.
///
/// The rail is what makes the list read as a single bus's path rather than a
/// set of unrelated predictions — which matters here, because only the top row
/// is measured and the rest are offsets from it.
private struct JourneyRow: View {
    let item: JourneyStopDisplay
    let color: Color
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            rail
            Text(item.name)
                .font(item.isOrigin ? .body.weight(.semibold) : .body)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailingTime
        }
        .padding(.horizontal)
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var rail: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : color).frame(width: 3)
                Rectangle().fill(isLast ? Color.clear : color).frame(width: 3)
            }
            Circle()
                .fill(item.isOrigin ? color : Color(.systemBackground))
                .stroke(color, lineWidth: 3)
                .frame(width: item.isOrigin ? 15 : 11, height: item.isOrigin ? 15 : 11)
        }
        .frame(width: 15)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var trailingTime: some View {
        if let etaText = item.etaText {
            // The rider's own stop: the one measured number on this screen.
            Text(etaText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(tone: item.tone))
        } else if let clockText = item.clockText {
            // Projected. Secondary styling, never green — the gap it was built
            // from is a timetable, not a measurement.
            Text(clockText)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("—")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityText: String {
        if let etaText = item.etaText { return "\(item.name), arriving in \(etaText)" }
        if let clockText = item.clockText { return "\(item.name), around \(clockText)" }
        return "\(item.name), no time available"
    }
}

#Preview("From the Lines tab — draws its own map") {
    NavigationStack {
        LineDetailView(
            stop: Stop.previews[0],
            arrival: RealtimeStop.preview.arrivals[0],
            line: "305"
        )
    }
    .environment(AppServices.preview())
}

#Preview("Unidentifiable bus") {
    NavigationStack {
        LineDetailView(
            stop: Stop.previews[0],
            // No trip_id: the board knew a bus was coming but not which one.
            arrival: RealtimeStop.preview.arrivals[3],
            line: "701"
        )
    }
    .environment(AppServices.preview(client: MockPortoBusClient(lineStopsResult: .preview)))
}

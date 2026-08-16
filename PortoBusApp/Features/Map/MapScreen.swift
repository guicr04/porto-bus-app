import MapKit
import SwiftUI
import PortoBusKit

/// The Map tab: Porto's stops on Apple's basemap, tap one for its live board.
///
/// Why our own annotations rather than Apple's transit POIs (DESIGN.md §11.1):
/// a tapped `MKMapFeatureAnnotation` gives a name and a coordinate but no
/// `stop_code`, so binding it back to our data would be fuzzy name matching that
/// breaks whenever Apple's data shifts. Apple's `.publicTransport` POIs are
/// filtered out for the same reason — two sets of pins disagreeing about the
/// same corner is worse than one.
struct MapScreen: View {
    @Environment(AppServices.self) private var services
    @State private var model: MapViewModel?
    @State private var camera: MapCameraPosition = .region(Self.defaultRegion)
    @State private var selectedStop: Stop?
    @State private var didCenterOnUser = false
    @State private var framedRoute: String?

    /// Central Porto — where the map opens before (or without) a location fix.
    /// Aliados, because a map that opens on the Atlantic while waiting for
    /// permission looks broken.
    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.14823, longitude: -8.61076),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    var body: some View {
        Group {
            if let model {
                map(model)
            } else {
                ContentUnavailableView("Can't reach the server", systemImage: "network.slash")
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
    }

    private func start() async {
        if model == nil, let client = services.makeClient() {
            model = MapViewModel(client: client, location: services.location)
        }
        guard let model, !didCenterOnUser else { return }
        didCenterOnUser = true

        // Ask before MapKit does. `UserAnnotation` and `MapUserLocationButton`
        // never request authorization themselves — they just fail with
        // kCLErrorDenied and log it — so without this the rider sees a dead
        // locate button and no prompt.
        await services.location.requestAuthorizationIfNeeded()

        // Centre on the rider if we can. If not, stay on Porto rather than
        // nagging — the map is still perfectly usable without a fix.
        if let coordinate = await model.currentCoordinate() {
            camera = .region(
                MKCoordinateRegion(center: coordinate, span: Self.defaultRegion.span)
            )
        }
    }

    @ViewBuilder
    private func map(_ model: MapViewModel) -> some View {
        Map(position: $camera, selection: Binding(
            get: { selectedStop?.stopCode },
            set: { code in selectedStop = model.stops.first { $0.stopCode == code } }
        )) {
            UserAnnotation()

            if services.route.isActive {
                let routeColor = Color(hex: services.route.colorHex) ?? .accentColor
                if services.route.coordinates.count > 1 {
                    MapPolyline(coordinates: services.route.coordinates)
                        .stroke(routeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(services.route.stops) { routeStop in
                    Annotation(routeStop.name, coordinate: routeStop.coordinate, anchor: .center) {
                        RouteStopDot(isOrigin: routeStop.isOrigin, isTerminus: routeStop.isTerminus, color: routeColor)
                    }
                    // Titles left on, and left to MapKit: it declutters
                    // colliding labels as the map zooms, which is the only
                    // reason a name per stop is viable on a 50-stop route.
                    .annotationTitles(.automatic)
                }
            }

            // While a route is drawn, the neighbourhood's other pins are noise
            // sitting on top of the one thing being looked at. Apple Maps does
            // the same: a selected transit route gets the map to itself.
            ForEach(services.route.isActive ? [] : model.annotated) { item in
                let stop = item.stop
                // Read while the body evaluates, not inside the annotation's
                // content closure — see MapViewModel.Annotated for why.
                let detail = model.detail
                let isFavorite = services.favorites.isFavorite(stopCode: stop.stopCode)

                if let lat = stop.lat, let lon = stop.lon {
                    Annotation(
                        stop.name,
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        // The mark sits *on* the stop, so anchor its centre
                        // there rather than a balloon tip below it.
                        anchor: .center
                    ) {
                        StopAnnotationView(
                            stop: stop,
                            detail: detail,
                            lines: item.lines,
                            isFavorite: isFavorite
                        )
                        // The whole badge is the hit target; without this only
                        // the drawn pixels take the tap.
                        .contentShape(Rectangle())
                        .onTapGesture { selectedStop = stop }
                    }
                    .annotationTitles(.hidden)
                    .tag(stop.stopCode)
                }
            }
        }
        // Names are drawn by us (or deliberately not at all): Apple's own
        // annotation labels would collide with the line tags at street zoom.
        .mapStyle(.standard(pointsOfInterest: .excluding([.publicTransport])))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let region = context.region
            model.cameraMoved(to: BoundingBox(
                centerLat: region.center.latitude,
                centerLon: region.center.longitude,
                latDelta: region.span.latitudeDelta,
                lonDelta: region.span.longitudeDelta
            ))
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { statusBanner(model) }
        // Frame the route when a different one is picked, and never on the
        // publisher's 20-second refresh: a camera that snapped back mid-pan
        // would be unusable.
        .onChange(of: services.route.key) { frameRoute() }
        // Dismissing the sheet takes the route with it. The pushed screen's own
        // onDisappear covers a pop, but a swipe-down dismissal doesn't always
        // reach it, and a route left drawn for a closed card is a ghost.
        .onChange(of: selectedStop == nil) { if selectedStop == nil { services.route.clear() } }
        .sheet(item: $selectedStop) { stop in
            MapStopSheet(stop: stop)
                // Three stops, as Apple Maps has: shrunk to almost nothing so
                // the map is unobstructed, a working half-height, and full. The
                // small one matters most here — a route drawn across the city
                // is the thing the rider came for, and a card pinned over the
                // bottom half of it is in the way.
                .presentationDetents([.height(120), .fraction(0.45), .large])
                // Keeps the map draggable underneath the sheet, which is the
                // Apple Maps feel and the reason this is a sheet, not a push.
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
                .presentationDragIndicator(.visible)
        }
    }

    /// Fit the visible strip of map — the part the sheet isn't covering — to
    /// the whole route.
    private func frameRoute() {
        let route = services.route
        guard !route.key.isEmpty else {
            framedRoute = nil
            return
        }
        guard framedRoute != route.key else { return }
        let points = route.coordinates.isEmpty ? route.stops.map(\.coordinate) : route.coordinates
        guard let region = MKCoordinateRegion.fitting(points, visibleFraction: 0.55) else { return }
        framedRoute = route.key
        withAnimation(.easeInOut(duration: 0.4)) { camera = .region(region) }
    }

    /// One line of honesty at the top, and only when there is something to say.
    ///
    /// A denied location outranks the rest: the locate button and the blue dot
    /// are both dead in that state, and silence would read as a broken button
    /// rather than a decision the rider made and can reverse.
    @ViewBuilder
    private func statusBanner(_ model: MapViewModel) -> some View {
        Group {
            if services.location.isDenied {
                locationDeniedBanner
            } else if services.route.isActive {
                // A route is the answer to a question the rider just asked.
                // Telling them to zoom in for stop pins they can't see — because
                // the route deliberately hid them — is advice about the wrong
                // screen.
                EmptyView()
            } else if model.zoomedOut {
                banner("Zoom in to see stops", systemImage: "arrow.up.left.and.arrow.down.right")
            } else if model.detail == .dots && !model.stops.isEmpty {
                banner("Zoom in for stop details", systemImage: "arrow.up.left.and.arrow.down.right")
            } else if model.refreshFailed {
                banner("Couldn't load stops", systemImage: "exclamationmark.triangle.fill")
            } else if model.isLoading && model.stops.isEmpty {
                banner("Loading stops…", systemImage: "clock")
            }
        }
        .padding(.top, 8)
    }

    /// Only iOS Settings can undo a denial, so link straight there rather than
    /// asking again — a second `requestWhenInUseAuthorization` is a no-op once
    /// refused, which is exactly the dead end this avoids.
    private var locationDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
            Text("Location is off")
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .shadow(radius: 2, y: 1)
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .shadow(radius: 2, y: 1)
    }
}

#Preview {
    NavigationStack { MapScreen() }
        .environment(AppServices.preview())
}

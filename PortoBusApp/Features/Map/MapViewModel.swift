import CoreLocation
import Foundation
import Observation
import PortoBusKit

/// The stops visible on the map, driven by where the camera is.
///
/// Two decisions shape this whole type, both from DESIGN.md §11.1:
///
/// 1. **The server bounds the set, not the client.** `/stops?bbox=` returns what
///    is on screen, so the app never holds Porto's 2,568 stops in memory and a
///    truncated answer isn't possible.
/// 2. **Zoomed out, no pins at all.** Below the threshold the map would be a
///    solid mass of markers that says nothing. An honest "zoom in" beats a
///    useless smear, and it also stops a continent-sized bbox being fetched.
@MainActor
@Observable
final class MapViewModel {
    private(set) var stops: [Stop] = []
    private(set) var isLoading = false
    /// Set when a fetch fails but pins are already on screen — the map keeps the
    /// stale pins and mentions it, rather than blanking on one dropped request.
    private(set) var refreshFailed = false
    /// How much each stop currently shows. Drives the view; also decides whether
    /// line numbers are worth fetching.
    private(set) var detail: MapDetailLevel = .marks
    /// Line numbers per stop code, populated only at the tightest zoom.
    private(set) var linesByStop: [String: [StopLine]] = [:]

    /// True when the camera is too far out for stops to be meaningful.
    var zoomedOut: Bool { !detail.showsStops }

    /// Fetch this much beyond the visible box so a small pan is already covered.
    private static let overfetch = 0.35

    private let client: PortoBusClient
    private let location: LocationProvider

    /// What the current `stops` actually cover, so a camera move that stays
    /// inside it doesn't refetch. This is the whole reason panning feels free.
    private var loadedBox: BoundingBox?
    private var fetchTask: Task<Void, Never>?
    /// What `linesByStop` covers. Separate from `loadedBox` because line numbers
    /// are fetched for a tighter region and only at the deepest zoom.
    private var loadedLinesBox: BoundingBox?
    private var linesTask: Task<Void, Never>?

    init(client: PortoBusClient, location: LocationProvider) {
        self.client = client
        self.location = location
    }

    /// The rider's coordinate, or nil if location is unavailable — the map falls
    /// back to a default region rather than blocking on permission.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        await location.currentCoordinate()
    }

    /// React to the camera settling on a new region.
    ///
    /// Debounced rather than fetched per frame: `onMapCameraChange` fires
    /// continuously through a pan, and firing a request for each one would be
    /// both wasteful and out of order. The in-flight task is cancelled so only
    /// the region the rider actually stopped on gets loaded.
    func cameraMoved(to box: BoundingBox) {
        fetchTask?.cancel()
        detail = MapDetailLevel.forSpan(box.latSpan)

        guard detail.showsStops else {
            linesTask?.cancel()
            stops = []
            linesByStop = [:]
            loadedBox = nil
            loadedLinesBox = nil
            isLoading = false
            return
        }

        loadLines(for: box)

        // Already covered by what's on screen — nothing to do.
        if let loadedBox, loadedBox.contains(box) { return }

        fetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.load(box: box.expanded(by: Self.overfetch))
        }
    }

    /// Line numbers are fetched only at the deepest zoom, and dropped as soon as
    /// the camera pulls back out.
    ///
    /// This is one request for the whole region rather than one per stop — the
    /// API derives stop->lines at ingest, so the answer is a primary-key lookup
    /// instead of a scan over 850k rows. Without that, labelling a screenful of
    /// stops would cost a round trip each and the feature wouldn't be worth it.
    private func loadLines(for box: BoundingBox) {
        linesTask?.cancel()

        guard detail.showsLines else {
            linesByStop = [:]
            loadedLinesBox = nil
            return
        }
        if let loadedLinesBox, loadedLinesBox.contains(box) { return }

        // No overfetch margin here: at street zoom the box is small, and lines
        // are cosmetic — better to re-ask than to pull a wide region eagerly.
        linesTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            do {
                let fetched = try await client.stopLines(bbox: box)
                guard !Task.isCancelled else { return }
                linesByStop = Dictionary(
                    uniqueKeysWithValues: fetched.map { ($0.stopCode, $0.lines) }
                )
                loadedLinesBox = box
            } catch {
                // No banner: the marks are still correct without their labels,
                // and "couldn't load line numbers" is noise on a working map.
                // It does get logged, though — a silent failure here once hid a
                // decode bug behind what looked like a deliberate design choice.
                #if DEBUG
                print("[map] line labels unavailable: \(error)")
                #endif
            }
        }
    }

    /// One stop as the map needs it: the stop plus whatever labels apply now.
    ///
    /// Exists so the annotation's inputs are resolved while the view's body is
    /// being evaluated. Reading `linesByStop` inside an `Annotation`'s content
    /// closure instead looks equivalent and is not: that closure runs outside
    /// the body's observation scope, so a labels-only update — which changes no
    /// stop — never redraws anything, and the tags silently never appear.
    struct Annotated: Identifiable, Hashable {
        let stop: Stop
        let lines: [StopLine]
        var id: String { stop.stopCode }
    }

    /// The annotations to draw, labels included, in one observed read.
    var annotated: [Annotated] {
        stops.map { Annotated(stop: $0, lines: linesByStop[$0.stopCode] ?? []) }
    }

    /// Fetch the stops for a box. Exposed for the retry button and for tests.
    func load(box: BoundingBox) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await client.stops(bbox: box)
            guard !Task.isCancelled else { return }
            stops = fetched.filter { $0.lat != nil && $0.lon != nil }
            loadedBox = box
            refreshFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            // Keep whatever is already drawn; an empty map would read as
            // "no stops here", which is a different and wrong claim.
            refreshFailed = true
            if stops.isEmpty { loadedBox = nil }
        }
    }
}

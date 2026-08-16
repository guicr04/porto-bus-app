import CoreLocation
import Observation

/// Thin async wrapper over CoreLocation. Exposes one thing the Board needs: the
/// current coordinate, or nil when location is denied/unavailable so the caller
/// can fall back to the saved home coordinates (DESIGN.md §7). `whenInUse` only.
///
/// The delegate callbacks are `nonisolated` (CoreLocation calls them on the main
/// run loop) and hop back onto the main actor via `assumeIsolated`, which keeps
/// the class `@MainActor` under Swift 6 strict concurrency without data races.
@Observable
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// True when the rider has actively refused, or is barred by policy. The UI
    /// needs to distinguish this from "not asked yet": the first is a dead end
    /// only Settings can undo, the second is one prompt away.
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Prompt for permission if we've never asked.
    ///
    /// Exists so a screen can ask *before* MapKit's own location manager tries
    /// and fails — `UserAnnotation`/`MapUserLocationButton` don't request
    /// authorization themselves, they just fail with `kCLErrorDenied` and log
    /// it. Asking first turns that into a prompt the rider can answer.
    func requestAuthorizationIfNeeded() async {
        guard authorization == .notDetermined else { return }
        await withCheckedContinuation { cont in
            authWaiters.append(cont)
            manager.requestWhenInUseAuthorization()
            scheduleTimeout(seconds: 5) { [weak self] in self?.resumeAuthWaiters() }
        }
    }

    /// Current coordinate, prompting for permission the first time. Returns nil
    /// when permission is denied/restricted or the fix fails — never throws, so
    /// the Board can quietly fall back to home coordinates.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        // In SwiftUI previews there is no location stack and the auth prompt
        // never resolves — return nil so screens fall back to home coordinates
        // instead of hanging.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return nil
        }

        // Safety net inside: if the auth decision never calls back, we unblock
        // so the board can proceed with fallback coordinates.
        await requestAuthorizationIfNeeded()

        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { cont in
            locationWaiters.append(cont)
            manager.requestLocation()
            // A one-shot fix can silently never arrive (notably on the
            // simulator). Time out to nil so the caller falls back to home
            // coordinates rather than spinning forever.
            scheduleTimeout(seconds: 4) { [weak self] in self?.resumeLocationWaiters(with: nil) }
        }
    }

    private func scheduleTimeout(seconds: Double, _ body: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            body()
        }
    }

    private func resumeAuthWaiters() {
        let waiters = authWaiters
        authWaiters.removeAll()
        for w in waiters { w.resume() }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the Sendable value here; never capture the non-Sendable `manager`
        // into the main-actor closure (that would risk a data race under Swift 6).
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            resumeAuthWaiters()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Extract the Sendable coordinate before hopping actors.
        let coordinate = locations.last?.coordinate
        MainActor.assumeIsolated {
            resumeLocationWaiters(with: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            resumeLocationWaiters(with: nil)
        }
    }

    private func resumeLocationWaiters(with coordinate: CLLocationCoordinate2D?) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        for w in waiters { w.resume(returning: coordinate) }
    }
}

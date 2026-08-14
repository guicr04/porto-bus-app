import Foundation
import Testing
@testable import PortoBusKit

/// Endpoint construction tests. The one that matters most is `service_id`
/// encoding: STCP matches it exactly server-side, and a space sent as `+`
/// breaks the lookup (per the API README).
struct EndpointTests {
    let base = URL(string: "http://192.168.1.20:8000")!

    @Test func boardBuildsLatLon() throws {
        let url = try #require(API.board(lat: 41.1496, lon: -8.6109).url(relativeTo: base))
        let s = url.absoluteString
        #expect(s.hasPrefix("http://192.168.1.20:8000/board?"))
        #expect(s.contains("lat=41.1496"))
        #expect(s.contains("lon=-8.6109"))
    }

    @Test func omitsNilQueryItems() throws {
        // No query params supplied → clean path, no dangling "?".
        let url = try #require(API.stops().url(relativeTo: base))
        #expect(url.absoluteString == "http://192.168.1.20:8000/stops")
    }

    @Test func serviceIdEncodesSpacesAsPercent20NeverPlus() throws {
        let serviceId = "DOM|FERIADO:FLUXO 3.1 20260718"
        let url = try #require(
            API.lineSchedule(line: "300", serviceId: serviceId, directionId: 0).url(relativeTo: base)
        )
        let s = url.absoluteString

        // The exact failure the README calls out.
        #expect(!s.contains("+"))
        // Space → %20, pipe → %7C, colon → %3A.
        #expect(s.contains("service_id=DOM%7CFERIADO%3AFLUXO%203.1%2020260718"))
    }

    @Test func departuresRequiresLineAndEncodesIt() throws {
        let url = try #require(API.departures(stop: "CMO", line: "1M").url(relativeTo: base))
        #expect(url.absoluteString.contains("/stops/CMO/departures?"))
        #expect(url.absoluteString.contains("line=1M"))
    }

    @Test func queryOrderingIsDeterministic() throws {
        // Sorted pairs → stable string for cache keys and assertions.
        let url = try #require(
            API.board(lat: 1, lon: 2, walkMinutes: 10, sort: .eta, includeUnreachable: true)
                .url(relativeTo: base)
        )
        let query = try #require(url.query)
        let keys = query.split(separator: "&").map { $0.split(separator: "=")[0] }
        #expect(keys == keys.sorted())
    }

    @Test func pathSegmentsResolveAgainstBaseWithNoTrailingSlash() throws {
        // Base has no trailing slash; path has no leading slash. Must still join.
        let url = try #require(API.realtime(stop: "CMO").url(relativeTo: base))
        #expect(url.absoluteString == "http://192.168.1.20:8000/stops/CMO/realtime")
    }
}

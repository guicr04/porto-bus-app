import Foundation
import Observation
import PortoBusKit

@MainActor
@Observable
final class LinesViewModel {
    private(set) var state: LoadState<[Line]> = .idle

    private let client: PortoBusClient

    init(client: PortoBusClient) {
        self.client = client
    }

    var lines: [Line] { state.value ?? [] }

    func load() async {
        if state.isInitialLoad { state = .loading }
        do {
            let fetched = try await client.lines()
            state = .loaded(fetched.sorted { Self.compareLines($0.line, $1.line) })
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }

    /// Numeric line ordering, matching the API's own `compareLines` (the rule
    /// behind `/board`'s default sort): leading number ascending, a suffixed
    /// variant right after its bare number ("1" before "1M"), lettered lines
    /// last. `/lines` carries no ordering guarantee, so the app applies the
    /// same rule client-side for one consistent reading order across the app.
    static func compareLines(_ a: String, _ b: String) -> Bool {
        func leadingNumber(_ s: String) -> Int? {
            let digits = s.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
        let na = leadingNumber(a)
        let nb = leadingNumber(b)
        if let na, let nb {
            if na != nb { return na < nb }
            return a < b
        }
        if na != nil { return true }
        if nb != nil { return false }
        return a < b
    }
}

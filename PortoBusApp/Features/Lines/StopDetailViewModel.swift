import Foundation
import Observation
import PortoBusKit

/// Every bus of one line heading one way, collapsed into a single row: the
/// badge, where it goes, and when the next two leave.
///
/// Grouped by line **and destination**, not line alone. A line usually serves a
/// stop in both directions, and merging those would put a Matosinhos bus and a
/// Cordoaria bus under one heading with interleaved times — a row that is wrong
/// in the only way that matters.
struct StopLineGroupDisplay: Identifiable, Hashable {
    let id: String
    let line: String
    let destination: String
    /// The next two, on one line: "6, 21 min".
    let etaText: String
    let tone: ArrivalTone
    let colorHex: String?
    let textColorHex: String?
    /// The soonest bus of this group — the one the line detail follows.
    let next: Arrival
}

/// A stop's live board, across every line serving it — not filtered to one
/// line. Shared by the Lines flow (Lines -> a line -> one of its stops) and by
/// the Map's bottom sheet, which is the same content in a different frame
/// (DESIGN.md §6.4, §11.1). If Santa Justa serves 701, 702 and 703, all three
/// are here, not just the one you drilled in from.
@MainActor
@Observable
final class StopDetailViewModel {
    private(set) var state: LoadState<RealtimeStop> = .idle

    private let client: PortoBusClient
    let stop: Stop

    init(client: PortoBusClient, stop: Stop) {
        self.client = client
        self.stop = stop
    }

    var stopName: String { state.value?.stopName ?? stop.name }

    /// The board as rows, one per line+destination.
    ///
    /// Group order is the order the lines first appear in the response, which is
    /// already sorted by ETA server-side — so the soonest bus leads, and the app
    /// never re-sorts into disagreeing with what the API decided.
    var lineGroups: [StopLineGroupDisplay] {
        guard let realtime = state.value else { return [] }

        var order: [String] = []
        var buckets: [String: [Arrival]] = [:]
        for arrival in realtime.arrivals {
            let key = "\(arrival.line)|\(arrival.destination)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(arrival)
        }

        return order.compactMap { key in
            guard let group = buckets[key], let first = group.first else { return nil }
            return StopLineGroupDisplay(
                id: key,
                line: first.line,
                destination: first.destination,
                etaText: Self.groupedEtaText(group.map(\.arrivalMinutes)),
                // The soonest bus sets the tone: it is the one being caught, and
                // a later bus running late says nothing about this one.
                tone: BoardViewModel.arrivalTone(forStatus: first.status),
                colorHex: group.first(where: { $0.color != nil })?.color,
                textColorHex: group.first(where: { $0.textColor != nil })?.textColor,
                next: first
            )
        }
    }

    var isEmpty: Bool {
        if let realtime = state.value { return realtime.arrivals.isEmpty }
        return false
    }

    func load() async {
        if state.isInitialLoad { state = .loading }
        do {
            let realtime = try await client.realtime(stop: stop.stopCode)
            state = .loaded(realtime)
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }

    /// The next two departures as one string: "6, 21 min".
    ///
    /// The unit is said once at the end because the row is scanned, not read —
    /// "6 min, 21 min" is the same information taking twice the width.
    static func groupedEtaText(_ minutes: [Double?]) -> String {
        let values = minutes.compactMap { $0 }.prefix(2).map { Int($0.rounded()) }
        guard let first = values.first else { return "—" }
        let head = first <= 0 ? "Arriving" : "\(first)"
        guard values.count > 1 else { return first <= 0 ? "Arriving" : "\(first) min" }
        return "\(head), \(values[1]) min"
    }
}

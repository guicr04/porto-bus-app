import SwiftUI
import PortoBusKit

/// A stop's board, one row per line and direction — the shared body of both the
/// pushed stop screen and the Map's bottom sheet.
///
/// It lives on its own because those two must not drift: §6.4 calls them one
/// screen in two frames, and the moment the grouping existed in only one of them
/// that stopped being true. The frame (title, toolbar, refresh cadence) belongs
/// to the caller; what a stop *says* belongs here.
///
/// Modelled on Apple Maps' transit stop card (DESIGN.md §11.1): line, where it
/// goes, the next two times. Tapping a row follows that specific bus.
struct StopBoardList: View {
    let stop: Stop
    let groups: [StopLineGroupDisplay]

    var body: some View {
        List(groups) { group in
            NavigationLink {
                LineDetailView(stop: stop, arrival: group.next, line: group.line)
            } label: {
                row(group)
            }
        }
        .listStyle(.plain)
    }

    private func row(_ group: StopLineGroupDisplay) -> some View {
        HStack(spacing: 12) {
            LineBadge(line: group.line, color: group.colorHex, textColor: group.textColorHex)
            Text(group.destination)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(group.etaText)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(tone: group.tone))
                // Two times ("6, 21 min") must not push the destination out;
                // the destination is what identifies the row.
                .layoutPriority(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Line \(group.line) to \(group.destination), \(group.etaText)")
    }
}

/// The one thing a stop can say that isn't a list of buses.
///
/// Empty is not broken (DESIGN.md §8): "nothing is tracked here right now" is a
/// real answer, and it must not look like a failure.
struct StopBoardEmptyView: View {
    var body: some View {
        ContentUnavailableView(
            "No arrivals",
            systemImage: "clock.badge.xmark",
            description: Text("Nothing is currently tracked at this stop.")
        )
    }
}

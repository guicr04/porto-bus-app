import SwiftUI
import PortoBusKit

/// What a stop looks like on the map at a given zoom.
///
/// `Annotation` rather than `Marker` throughout: `Marker` always draws Apple's
/// teardrop balloon and only lets you set a tint and a glyph, and a balloon is
/// the wrong shape for a thing that sits *at* a point rather than pointing at
/// one. Apple's own transit stops are flat roundels for the same reason.
struct StopAnnotationView: View {
    let stop: Stop
    let detail: MapDetailLevel
    let lines: [StopLine]
    let isFavorite: Bool

    var body: some View {
        switch detail {
        case .hidden:
            EmptyView()
        case .dots:
            dot
        case .marks:
            badge
        case .marksWithLines:
            HStack(spacing: 3) {
                badge
                lineTags
            }
        }
    }

    /// District zoom: presence, not identity. Small enough that a few hundred
    /// read as texture rather than clutter.
    private var dot: some View {
        Circle()
            .fill(isFavorite ? Color.pink : Self.blue)
            .frame(width: 7, height: 7)
            .overlay(Circle().stroke(.white, lineWidth: 1.2))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }

    /// The mark on a light disc. The disc is what makes it legible: the map
    /// underneath is textured, and the mark's own negative space needs a clean
    /// ground to read against at this size.
    private var badge: some View {
        PortoBusMark()
            .padding(4)
            .frame(width: 26, height: 26)
            .background(badgeFill, in: Circle())
            .overlay(
                Circle().stroke(isFavorite ? Color.pink : .black.opacity(0.12),
                                lineWidth: isFavorite ? 2 : 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
    }

    /// Street zoom only: which lines actually stop here, in their own colours —
    /// the thing that makes a stop worth looking at before you tap it.
    private var lineTags: some View {
        // More than three and the row starts colliding with its neighbours;
        // the sheet has the full list a tap away.
        let shown = lines.prefix(3)
        return HStack(spacing: 2) {
            ForEach(Array(shown), id: \.line) { line in
                Text(line.line)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: line.textColor) ?? .white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1.5)
                    .background(Color(hex: line.color) ?? Self.blue, in: RoundedRectangle(cornerRadius: 3))
            }
            if lines.count > shown.count {
                Text("+\(lines.count - shown.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }

    /// Matches the mark's own blue, so a dot at district zoom and the mark at
    /// neighbourhood zoom read as the same thing getting closer.
    static let blue = Color(hex: "#1B6EC7") ?? .blue

    private var badgeFill: some ShapeStyle {
        // A material rather than a flat colour: it picks up light and dark mode
        // without a second palette, the same way Apple's own map badges do.
        .thickMaterial
    }
}

#Preview {
    let stop = Stop(stopCode: "CMO", name: "CARMO", lat: 41.147, lon: -8.617)
    let lines = [
        StopLine(line: "500", color: "#187EC2", textColor: "#FFFFFF"),
        StopLine(line: "203", color: "#C2185B", textColor: "#FFFFFF"),
        StopLine(line: "ZC", color: "#2E7D32", textColor: "#FFFFFF"),
        StopLine(line: "701", color: "#E64A19", textColor: "#FFFFFF"),
    ]
    return VStack(alignment: .leading, spacing: 24) {
        StopAnnotationView(stop: stop, detail: .dots, lines: [], isFavorite: false)
        StopAnnotationView(stop: stop, detail: .marks, lines: [], isFavorite: false)
        StopAnnotationView(stop: stop, detail: .marks, lines: [], isFavorite: true)
        StopAnnotationView(stop: stop, detail: .marksWithLines, lines: lines, isFavorite: false)
    }
    .padding()
}

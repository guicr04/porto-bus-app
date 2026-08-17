import SwiftUI

extension Color {
    /// Parse a `#RRGGBB` (or `#RGB` / `#RRGGBBAA`) hex string from the API into a
    /// Color. Returns nil for null/garbage so callers can fall back to a neutral
    /// badge rather than rendering black. This mapping is deliberately in the
    /// View layer — the ViewModel exposes the raw hex string (DESIGN.md §4).
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        guard let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: Double
        switch s.count {
        case 3: // RGB
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
            a = 1
        case 6: // RRGGBB
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Favourited — the heart, the swipe action, and the ring around a
    /// favourited stop on the map. One colour, so the three read as the same
    /// idea.
    ///
    /// It is the app mark's own green (`PortoBusMark.mint`, `#74DFB5` — the
    /// lower half of the ring), taken deeper at the same hue. The mint itself
    /// is too light to use here: white swipe-action labels are set by the
    /// system and would sit on it at about 1.6:1, and a 7pt dot in it
    /// disappears against Apple's pale basemap. `#189E69` is the same hue at
    /// ~3.4:1 against white, which carries a bold label and a small dot.
    ///
    /// Superseded: this was `.pink`, which belonged to nothing else in the app.
    static let favorite = Color(hex: "#189E69") ?? .green

    /// Maps an arrival's on-time/delayed tone to the colour its ETA renders
    /// in. See `ArrivalTone` for why this replaced a separate live indicator.
    init(tone: ArrivalTone) {
        switch tone {
        case .onTime: self = .green
        case .delayed: self = .red
        case .unknown: self = .primary
        }
    }
}

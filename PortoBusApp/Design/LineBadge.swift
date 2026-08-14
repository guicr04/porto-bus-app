import SwiftUI

/// The coloured line-number chip used across every screen. Colour comes from the
/// realtime feed's `color`/`text_color` — the *true* line colour, not the coarse
/// family colour the routes endpoints return (DESIGN.md §7). A null colour falls
/// back to a neutral chip rather than an accidental black one.
struct LineBadge: View {
    let line: String
    var color: String?
    var textColor: String?
    var size: Size = .regular

    enum Size {
        case regular, large

        var font: Font {
            switch self {
            case .regular: .subheadline.weight(.bold)
            case .large: .title3.weight(.bold)
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .regular: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .large: EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .regular: 40
            case .large: 52
            }
        }
    }

    private var background: Color { Color(hex: color) ?? Color(.secondarySystemFill) }
    private var foreground: Color {
        if let textColor, let c = Color(hex: textColor) { return c }
        // No text colour given: fall back to something legible on the badge.
        return Color(hex: color) == nil ? .primary : .white
    }

    var body: some View {
        Text(line)
            .font(size.font)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(size.padding)
            .frame(minWidth: size.minWidth)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 12) {
        LineBadge(line: "305", color: "#417DBD", textColor: "#FFFFFF")
        LineBadge(line: "1M", color: "#E8A200", textColor: "#000000", size: .large)
        LineBadge(line: "ZC", color: nil, textColor: nil)
    }
    .padding()
}

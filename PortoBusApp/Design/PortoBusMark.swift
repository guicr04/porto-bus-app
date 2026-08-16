import SwiftUI

/// The Porto Bus mark, drawn as vectors rather than shipped as a bitmap.
///
/// It is the app icon and the map's stop symbol, at sizes from 1024pt down to
/// about 16pt, so a raster would either be huge or mush. Everything is a stroke
/// — including the two nodes, which are stroked rings rather than filled
/// circles with a punched hole — so the centres stay transparent and the mark
/// works on a light badge and a dark one without a second asset.
///
/// Proportions are taken from the source artwork, normalised to a 200-unit box:
/// ring radius 55, stroke 15, node outer 25, node hole 10.
struct PortoBusMark: View {
    var blue: Color = Color(hex: "#1B6EC7") ?? .blue
    var mint: Color = Color(hex: "#74DFB5") ?? .green

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let ringR = s * 0.275
            let ringW = s * 0.075
            // The node's band sits between its outer edge (0.125) and hole
            // (0.05), so stroke the mid-radius with the band's width.
            let nodeR = s * 0.0875
            let nodeW = s * 0.075

            ZStack {
                // Blue over the top, mint under the bottom, meeting at the nodes.
                //
                // The arcs stop at the nodes' outer edges rather than running to
                // their centres. Solving |P(θ) − nodeCentre| = nodeOuter puts
                // those cuts at θ ≈ 26.3° and 206.3°, which keeps the nodes'
                // holes empty — so the mark needs no opaque fill behind them and
                // reads on a white badge and a dark one alike.
                arc(center: c, radius: ringR, from: 206.3, to: 333.7)
                    .stroke(blue, lineWidth: ringW)
                arc(center: c, radius: ringR, from: 26.3, to: 153.7)
                    .stroke(mint, lineWidth: ringW)

                // Nodes sit on the ring at 9 and 3 o'clock.
                Circle()
                    .strokeBorder(mint, lineWidth: nodeW)
                    .frame(width: nodeR * 2 + nodeW, height: nodeR * 2 + nodeW)
                    .position(x: c.x - ringR, y: c.y)
                Circle()
                    .strokeBorder(blue, lineWidth: nodeW)
                    .frame(width: nodeR * 2 + nodeW, height: nodeR * 2 + nodeW)
                    .position(x: c.x + ringR, y: c.y)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func arc(center: CGPoint, radius: CGFloat, from: Double, to: Double) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(from),
                endAngle: .degrees(to),
                clockwise: false
            )
        }
    }
}

#Preview("Sizes") {
    VStack(spacing: 20) {
        ForEach([120.0, 64.0, 32.0, 20.0, 16.0], id: \.self) { size in
            HStack(spacing: 16) {
                PortoBusMark().frame(width: size, height: size)
                PortoBusMark()
                    .frame(width: size, height: size)
                    .padding(size * 0.18)
                    .background(.white, in: Circle())
                    .shadow(radius: 1, y: 0.5)
            }
        }
    }
    .padding()
}

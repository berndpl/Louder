import SwiftUI

/// The app icon's foreground illustration, recreated as a vector mark: two
/// overlapping semicircles — a blue lower half and a pink upper half — whose
/// intersection darkens to the same navy as `AppIcon.icon` (a `.darken` blend
/// of the two colours). Used as the idle / zero-state illustration so the empty
/// window mirrors the app icon instead of the old waveform glyph.
///
/// Geometry mirrors `AppIcon-0.svg` (blue) and `AppIcon-1.svg` (pink): two
/// equal-radius circles whose centres are offset, each contributing one half.
struct IconForegroundMark: View {
    // Icon foreground colours (sRGB), matching the bundled SVGs.
    private let blue = Color(red: 0.0, green: 0.502, blue: 1.0)
    private let pink = Color(red: 1.0, green: 0.0, blue: 0.569)

    // Centres in units of the shared circle radius (from the SVG paths, with
    // the icon's 0.8193 group scale folded in): the pink circle sits up and to
    // the right of the blue one by this offset.
    private let offset = CGSize(width: 0.650, height: 0.350)

    var body: some View {
        Canvas { context, size in
            let aCenter = CGPoint(x: 0, y: 0)
            let bCenter = CGPoint(x: offset.width, y: offset.height)

            // Combined bounding box in circle-radius units.
            let minX = -1.0
            let maxX = bCenter.x + 1.0
            let minY = bCenter.y - 1.0
            let maxY = 1.0
            let bboxW = maxX - minX
            let bboxH = maxY - minY

            // Fit the bbox inside the view, preserving aspect ratio.
            let r = min(size.width / bboxW, size.height / bboxH)
            let originX = (size.width - bboxW * r) / 2 - minX * r
            let originY = (size.height - bboxH * r) / 2 - minY * r

            func place(_ p: CGPoint) -> CGPoint {
                CGPoint(x: originX + p.x * r, y: originY + p.y * r)
            }

            // Half-disc: a straight diameter plus an arc bulging to one side.
            // `down == true` bulges toward +y (lower half), else toward -y.
            func halfDisc(_ c: CGPoint, down: Bool) -> Path {
                var path = Path()
                let center = place(c)
                path.addArc(
                    center: center,
                    radius: r,
                    startAngle: .degrees(down ? 0 : 180),
                    endAngle: .degrees(down ? 180 : 360),
                    clockwise: false
                )
                path.closeSubpath()
                return path
            }

            context.fill(halfDisc(aCenter, down: true), with: .color(blue))
            context.blendMode = .darken
            context.fill(halfDisc(bCenter, down: false), with: .color(pink))
        }
        .accessibilityHidden(true)
    }
}

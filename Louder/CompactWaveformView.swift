import AppKit
import SwiftUI

struct CompactWaveformView: View {
    let series: [LoudnessSeries]
    let highlightedPreset: ProcessingPreset?
    let selectedSeriesID: UUID?
    let hoveredSeriesID: UUID?
    let activeSeriesID: UUID?
    let playbackProgress: Double
    let onHover: (UUID?) -> Void
    let onSelect: (LoudnessSeries) -> Void

    /// 0 = true loudness contours (undistorted glance view); 1 = fully spread
    /// into separate lanes so overlapping lines stay individually tappable.
    /// Animates in only while the pointer is over the graph.
    @State private var spread: Double = 0

    private let plotSize = CGSize(width: 160, height: 58)

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: (geometry.size.width - plotSize.width) / 2,
                y: (geometry.size.height - plotSize.height) / 2,
                width: plotSize.width,
                height: plotSize.height
            )
            let hitCurves = curves(in: plotRect, spread: spread)
            let waveCurves = waveCurves(in: plotRect)

            AnimatableWave(
                spread: spread,
                curves: waveCurves,
                playbackProgress: playbackProgress
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    NSCursor.pointingHand.set()
                    onHover(nearestCurve(to: location, curves: hitCurves)?.series.id)
                case .ended:
                    NSCursor.arrow.set()
                    onHover(nil)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let curve = nearestCurve(to: value.location, curves: hitCurves) {
                            onSelect(curve.series)
                        }
                    }
            )
        }
        .frame(height: 86)
        .onChange(of: hoveredSeriesID) { _, newValue in
            withAnimation(.easeOut(duration: 0.22)) {
                spread = newValue == nil ? 0 : 1
            }
        }
        .accessibilityRepresentation {
            VStack {
                ForEach(series) { item in
                    Button(accessibilityLabel(for: item)) {
                        onSelect(item)
                    }
                    .accessibilityValue(
                        item.id == activeSeriesID
                            ? "Current playback selection"
                            : ""
                    )
                }
            }
        }
    }

    private struct Curve {
        let series: LoudnessSeries
        let points: [CGPoint]
    }

    private func curves(in rect: CGRect, spread: Double) -> [Curve] {
        let allValues = series.flatMap { smoothedValues(for: $0) }
        let minimum = allValues.min() ?? -40
        let maximum = allValues.max() ?? -10
        let span = max(maximum - minimum, 6)

        // Loudness-normalized versions trace almost the same contour, so plotting
        // them by absolute level stacks the lines on top of each other. While the
        // pointer is over the graph we fan each series into its own vertical lane
        // so every line stays individually pickable; at rest (spread == 0) we
        // plot the true loudness contour so a glance shows an undistorted
        // comparison.
        let laneCount = max(series.count, 1)
        let laneSpread = 0.64
        let wiggleAmplitude = 0.20
        let usableHeight = rect.height - 14

        return series.enumerated().map { index, item in
            let lanePosition = laneCount > 1
                ? Double(index) / Double(laneCount - 1)
                : 0.5
            let laneOffset = (lanePosition - 0.5) * laneSpread

            let values = smoothedValues(for: item)
            let points = values.enumerated().map { valueIndex, value in
                let progress = values.count > 1
                    ? Double(valueIndex) / Double(values.count - 1)
                    : 0
                let normalized = (value - minimum) / span
                let wiggle = (normalized - 0.5) * wiggleAmplitude
                // Glance: place the line at its true normalized loudness.
                // Spread: collapse to a per-series lane plus a small loudness wiggle.
                let glanceNormalized = normalized
                let spreadNormalized = 0.5 + laneOffset + wiggle
                let laneNormalized = glanceNormalized + (spreadNormalized - glanceNormalized) * spread
                return CGPoint(
                    x: rect.minX + rect.width * progress,
                    y: rect.maxY - 7 - usableHeight * laneNormalized
                )
            }
            return Curve(series: item, points: points)
        }
    }

    /// Precomputes each series' geometry at both ends of the spread animation
    /// (contour at spread 0, lanes at spread 1) plus its baked style, in draw
    /// order. `AnimatableWave` interpolates between the two endpoints per frame.
    private func waveCurves(in rect: CGRect) -> [WaveCurve] {
        let contour = curves(in: rect, spread: 0)
        let lanes = curves(in: rect, spread: 1)
        return Array(zip(contour, lanes))
            .sorted { drawingOrder($0.0, $1.0) }
            .map { glance, spread in
                WaveCurve(
                    id: glance.series.id,
                    contourPoints: glance.points,
                    spreadPoints: spread.points,
                    color: color(for: glance.series),
                    opacity: opacity(for: glance.series),
                    lineWidth: lineWidth(for: glance.series),
                    isActive: glance.series.id == activeSeriesID
                )
            }
    }

    private func smoothedValues(for series: LoudnessSeries) -> [Double] {
        let raw = series.metrics.points.map(\.lufs)
        let firstMeasuredIndex = raw.firstIndex(where: { $0 > -69.5 }) ?? 0
        let source = Array(raw.dropFirst(firstMeasuredIndex))
        guard !source.isEmpty else { return [] }
        let count = min(16, source.count)
        let bins = (0..<count).map { index -> Double in
            let start = index * source.count / count
            let end = max((index + 1) * source.count / count, start + 1)
            let slice = source[start..<min(end, source.count)]
            return slice.reduce(0, +) / Double(slice.count)
        }
        guard bins.count > 2 else { return bins }
        return bins.indices.map { index in
            let lower = max(0, index - 1)
            let upper = min(bins.count - 1, index + 1)
            let values = bins[lower...upper]
            return values.reduce(0, +) / Double(values.count)
        }
    }

    private func nearestCurve(to location: CGPoint, curves: [Curve]) -> Curve? {
        curves
            .map { ($0, distance(from: location, to: $0.points)) }
            .filter { $0.1 <= 16 }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private func distance(from location: CGPoint, to points: [CGPoint]) -> CGFloat {
        guard points.count > 1,
              let first = points.first,
              let last = points.last,
              location.x >= first.x - 8,
              location.x <= last.x + 8 else {
            return .greatestFiniteMagnitude
        }
        let progress = (location.x - first.x) / max(last.x - first.x, 1)
        guard let curvePoint = point(on: points, progress: Double(progress)) else {
            return .greatestFiniteMagnitude
        }
        return abs(location.y - curvePoint.y)
    }

    private func point(on points: [CGPoint], progress: Double) -> CGPoint? {
        guard let first = points.first else { return nil }
        guard points.count > 1 else { return first }
        let clamped = min(max(progress, 0), 1)
        let position = clamped * Double(points.count - 1)
        let lower = min(Int(position.rounded(.down)), points.count - 1)
        let upper = min(lower + 1, points.count - 1)
        let fraction = position - Double(lower)
        return CGPoint(
            x: points[lower].x + (points[upper].x - points[lower].x) * fraction,
            y: points[lower].y + (points[upper].y - points[lower].y) * fraction
        )
    }

    private func drawingOrder(_ lhs: Curve, _ rhs: Curve) -> Bool {
        priority(lhs.series) < priority(rhs.series)
    }

    private func priority(_ series: LoudnessSeries) -> Int {
        if series.id == activeSeriesID { return 3 }
        if series.id == hoveredSeriesID { return 2 }
        if series.preset == highlightedPreset { return 1 }
        return 0
    }

    private func color(for series: LoudnessSeries) -> Color {
        // Only the selected file carries the prominent tint; everything else stays neutral.
        guard series.id == selectedSeriesID else { return .secondary }
        return series.preset?.tint ?? .secondary
    }

    private func opacity(for series: LoudnessSeries) -> Double {
        if let hoveredSeriesID {
            return series.id == hoveredSeriesID ? 1 : 0.12
        }
        if series.id == activeSeriesID { return 1 }
        if series.isOriginal { return 0.2 }
        return series.preset == highlightedPreset ? 1 : 0.16
    }

    private func lineWidth(for series: LoudnessSeries) -> CGFloat {
        if series.id == activeSeriesID || series.id == hoveredSeriesID { return 3.5 }
        if series.preset == highlightedPreset { return 3 }
        return 2
    }

    private func accessibilityLabel(for series: LoudnessSeries) -> String {
        let action = series.id == activeSeriesID ? "Play or pause" : "Play"
        return "\(action) \(series.displayName) for \(series.sourceName)"
    }
}

/// One curve's animation endpoints plus its baked style. Built by the parent;
/// `AnimatableWave` interpolates between `contourPoints` and `spreadPoints`.
private struct WaveCurve: Identifiable {
    let id: UUID
    let contourPoints: [CGPoint]
    let spreadPoints: [CGPoint]
    let color: Color
    let opacity: Double
    let lineWidth: CGFloat
    let isActive: Bool
}

/// Canvas that interpolates every curve between its contour (glance) and lane
/// (touchable) geometry. Conforming to `Animatable` with `spread` as the
/// `animatableData` makes SwiftUI re-render the canvas on every frame of the
/// hover-in/out transition, so the lines smoothly fan out and collapse instead
/// of snapping.
private struct AnimatableWave: View, Animatable {
    var spread: Double
    var curves: [WaveCurve]
    var playbackProgress: Double

    var animatableData: Double {
        get { spread }
        set { spread = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            for curve in curves {
                let points = Self.interpolate(curve.contourPoints, curve.spreadPoints, spread)
                context.stroke(
                    Self.path(for: points),
                    with: .color(curve.color.opacity(curve.opacity)),
                    style: StrokeStyle(lineWidth: curve.lineWidth, lineCap: .round, lineJoin: .round)
                )
            }

            if let active = curves.first(where: { $0.isActive }) {
                let points = Self.interpolate(active.contourPoints, active.spreadPoints, spread)
                if let dot = Self.point(on: points, progress: playbackProgress) {
                    let dotRect = CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: dotRect), with: .color(active.color))
                    context.stroke(
                        Path(ellipseIn: dotRect.insetBy(dx: -1, dy: -1)),
                        with: .color(.white.opacity(0.9)),
                        lineWidth: 1.5
                    )
                }
            }
        }
    }

    private static func interpolate(_ a: [CGPoint], _ b: [CGPoint], _ t: Double) -> [CGPoint] {
        guard a.count == b.count else { return b }
        let amount = CGFloat(t)
        return zip(a, b).map { start, end in
            CGPoint(
                x: start.x + (end.x - start.x) * amount,
                y: start.y + (end.y - start.y) * amount
            )
        }
    }

    private static func path(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    private static func point(on points: [CGPoint], progress: Double) -> CGPoint? {
        guard let first = points.first else { return nil }
        guard points.count > 1 else { return first }
        let clamped = min(max(progress, 0), 1)
        let position = clamped * Double(points.count - 1)
        let lower = min(Int(position.rounded(.down)), points.count - 1)
        let upper = min(lower + 1, points.count - 1)
        let fraction = CGFloat(position - Double(lower))
        return CGPoint(
            x: points[lower].x + (points[upper].x - points[lower].x) * fraction,
            y: points[lower].y + (points[upper].y - points[lower].y) * fraction
        )
    }
}

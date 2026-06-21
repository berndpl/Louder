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

    private let plotSize = CGSize(width: 160, height: 58)

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: (geometry.size.width - plotSize.width) / 2,
                y: (geometry.size.height - plotSize.height) / 2,
                width: plotSize.width,
                height: plotSize.height
            )
            let curves = curves(in: plotRect)

            Canvas { context, _ in
                for curve in curves.sorted(by: drawingOrder) {
                    context.stroke(
                        path(for: curve.points),
                        with: .color(color(for: curve.series).opacity(opacity(for: curve.series))),
                        style: StrokeStyle(
                            lineWidth: lineWidth(for: curve.series),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                if let active = curves.first(where: { $0.series.id == activeSeriesID }),
                   let dot = point(on: active.points, progress: playbackProgress) {
                    let dotRect = CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(color(for: active.series))
                    )
                    context.stroke(
                        Path(ellipseIn: dotRect.insetBy(dx: -1, dy: -1)),
                        with: .color(.white.opacity(0.9)),
                        lineWidth: 1.5
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    NSCursor.pointingHand.set()
                    onHover(nearestCurve(to: location, curves: curves)?.series.id)
                case .ended:
                    NSCursor.arrow.set()
                    onHover(nil)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let curve = nearestCurve(to: value.location, curves: curves) {
                            onSelect(curve.series)
                        }
                    }
            )
        }
        .frame(height: 86)
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

    private func curves(in rect: CGRect) -> [Curve] {
        let allValues = series.flatMap { smoothedValues(for: $0) }
        let minimum = allValues.min() ?? -40
        let maximum = allValues.max() ?? -10
        let span = max(maximum - minimum, 6)

        // Loudness-normalized versions trace almost the same contour, so plotting
        // them by absolute level stacks the lines on top of each other and makes
        // them impossible to pick apart. Instead, give each series its own
        // vertical lane and keep only a small loudness wiggle within that lane so
        // every line stays clearly separated and individually selectable.
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
                let laneNormalized = 0.5 + laneOffset + wiggle
                return CGPoint(
                    x: rect.minX + rect.width * progress,
                    y: rect.maxY - 7 - usableHeight * laneNormalized
                )
            }
            return Curve(series: item, points: points)
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

    private func path(for points: [CGPoint]) -> Path {
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

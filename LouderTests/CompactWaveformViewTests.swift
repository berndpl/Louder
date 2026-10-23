import AppKit
import SwiftUI
import XCTest
@testable import Louder

final class CompactWaveformViewTests: XCTestCase {
    @MainActor
    func testDraggingPlayheadSeeksWithoutSelectingFile() async throws {
        let series = recording()
        var positions: [Double] = []
        var starts = 0
        var ends = 0
        var selections = 0
        var deselections = 0
        let view = CompactWaveformView(
            series: [series],
            highlightedPreset: nil,
            selectedSeriesID: series.id,
            hoveredSeriesID: nil,
            activeSeriesID: series.id,
            playbackProgress: 0.2,
            onHover: { _ in },
            onSelect: { _ in selections += 1 },
            onDeselect: { deselections += 1 },
            onScrubStart: { starts += 1 },
            onScrub: { positions.append($0) },
            onScrubEnd: { ends += 1 }
        )
        let window = host(
            VStack { view }
                .contentShape(Rectangle())
                .onTapGesture { deselections += 1 }
        )
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))

        try await send(.leftMouseDown, at: CGPoint(x: 146, y: 21), to: window)
        try await send(.leftMouseDragged, at: CGPoint(x: 242, y: 21), to: window)
        try await send(.leftMouseDragged, at: CGPoint(x: 130, y: 21), to: window)
        try await send(.leftMouseDragged, at: CGPoint(x: 330, y: 21), to: window)
        try await send(.leftMouseDragged, at: CGPoint(x: 80, y: 21), to: window)
        try await send(.leftMouseUp, at: CGPoint(x: 80, y: 21), to: window)

        XCTAssertEqual(starts, 1)
        XCTAssertEqual(ends, 1)
        XCTAssertTrue(positions.contains { abs($0 - 0.8) < 0.01 })
        XCTAssertTrue(positions.contains { abs($0 - 0.1) < 0.01 })
        XCTAssertTrue(positions.contains(1))
        XCTAssertEqual(try XCTUnwrap(positions.last), 0)
        XCTAssertEqual(selections, 0)
        XCTAssertEqual(deselections, 0)
    }

    @MainActor
    func testClickingLineStillSelectsFile() async throws {
        let series = recording()
        var selected: UUID?
        var scrubbed = false
        let view = CompactWaveformView(
            series: [series],
            highlightedPreset: nil,
            selectedSeriesID: nil,
            hoveredSeriesID: nil,
            activeSeriesID: nil,
            playbackProgress: 0,
            onHover: { _ in },
            onSelect: { selected = $0.id },
            onDeselect: {},
            onScrubStart: { scrubbed = true },
            onScrub: { _ in scrubbed = true },
            onScrubEnd: { scrubbed = true }
        )
        let window = host(view)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))

        try await send(.leftMouseDown, at: CGPoint(x: 194, y: 21), to: window)
        try await send(.leftMouseUp, at: CGPoint(x: 194, y: 21), to: window)

        XCTAssertEqual(selected, series.id)
        XCTAssertFalse(scrubbed)
    }

    @MainActor
    private func host<Content: View>(_ view: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 388, height: 86),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: 388, height: 86))
        window.orderBack(nil)
        return window
    }

    @MainActor
    private func send(_ type: NSEvent.EventType, at point: CGPoint, to window: NSWindow) async throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
        window.sendEvent(event)
        try await Task.sleep(for: .milliseconds(50))
    }

    @MainActor
    private func recording() -> LoudnessSeries {
        LoudnessSeries(
            sourceID: UUID(),
            sourceName: "Preview.mp4",
            url: URL(fileURLWithPath: "/tmp/LouderWaveformPreview.mp4"),
            preset: nil,
            metrics: AudioMetrics(
                integratedLUFS: -16,
                estimatedSNR: nil,
                snrConfidence: .unavailable,
                points: [.init(time: 0, lufs: -16), .init(time: 30, lufs: -16)]
            )
        )
    }
}

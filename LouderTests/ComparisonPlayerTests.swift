import AVFoundation
import XCTest
@testable import Louder

final class ComparisonPlayerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LouderPlaybackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testSeeksForwardAndBackwardWhilePaused() async throws {
        let (controller, player, series) = try preview()
        defer { controller.stop() }
        controller.toggle(series)
        controller.toggle(series)

        controller.seek(to: 8)
        XCTAssertEqual(controller.currentTime, 8)
        try await waitUntil { abs(player.currentTime().seconds - 8) < 0.05 }
        controller.seek(to: 2)
        try await waitUntil { abs(player.currentTime().seconds - 2) < 0.05 }

        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(controller.activeSeriesID, series.id)
        XCTAssertEqual(player.rate, 0)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func testScrubbingResumesOnlyPreviouslyPlayingPreview() async throws {
        let (controller, player, series) = try preview()
        defer { controller.stop() }
        controller.toggle(series)
        controller.beginScrubbing()
        XCTAssertEqual(controller.state, .paused)
        XCTAssertTrue(controller.isScrubbing)
        controller.seek(to: 7)
        controller.seek(to: 3)
        controller.endScrubbing()

        try await waitUntil { player.rate > 0 && player.currentTime().seconds >= 3 }
        XCTAssertEqual(controller.state, .playing)
        XCTAssertFalse(controller.isScrubbing)
        XCTAssertEqual(controller.activeSeriesID, series.id)

        controller.toggle(series)
        controller.beginScrubbing()
        controller.seek(to: 1)
        controller.endScrubbing()
        try await waitUntil { abs(player.currentTime().seconds - 1) < 0.05 }
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(player.rate, 0)
    }

    @MainActor
    func testSeekingFromEndLeavesPreviewPausedAndCanReplay() async throws {
        let (controller, player, series) = try preview()
        defer { controller.stop() }
        controller.toggle(series)
        controller.seek(to: controller.duration)
        XCTAssertEqual(controller.state, .ended)
        controller.beginScrubbing()
        controller.seek(to: 4)
        controller.endScrubbing()

        try await waitUntil { abs(player.currentTime().seconds - 4) < 0.05 }
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(player.rate, 0)

        controller.seek(to: controller.duration)
        controller.toggle(series)
        try await waitUntil { player.rate > 0 && player.currentTime().seconds < 1 }
        XCTAssertEqual(controller.state, .playing)
    }

    @MainActor
    func testScrubbingToEndDoesNotResume() async throws {
        let (controller, player, series) = try preview()
        defer { controller.stop() }
        controller.toggle(series)
        controller.beginScrubbing()
        controller.seek(to: controller.duration)
        controller.endScrubbing()

        XCTAssertEqual(controller.state, .ended)
        try await waitUntil { abs(player.currentTime().seconds - controller.duration) < 0.05 }
        XCTAssertEqual(player.rate, 0)
    }

    @MainActor
    func testSeekClampsToFileBoundsAndRejectsInvalidPosition() throws {
        let (controller, _, series) = try preview()
        defer { controller.stop() }
        controller.toggle(series)
        controller.toggle(series)
        controller.seek(to: -20)
        XCTAssertEqual(controller.currentTime, 0)
        controller.seek(to: 100)
        XCTAssertEqual(controller.currentTime, controller.duration)
        XCTAssertEqual(controller.state, .ended)
        controller.seek(to: .nan)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(controller.currentTime, controller.duration)
        XCTAssertEqual(controller.activeSeriesID, series.id)
    }

    @MainActor
    func testSwitchingFileUsesScrubbedTimeAndClampsToShorterFile() async throws {
        let (controller, player, series) = try preview()
        defer { controller.stop() }
        let shorter = try recording("shorter.wav", duration: 5)
        controller.toggle(series)
        controller.beginScrubbing()
        controller.seek(to: 8)
        controller.endScrubbing()
        controller.toggle(shorter)

        XCTAssertEqual(controller.activeSeriesID, shorter.id)
        XCTAssertEqual(controller.currentTime, 4.95, accuracy: 0.001)
        try await waitUntil { player.currentTime().seconds >= 4.9 }
        XCTAssertEqual(controller.activeSeriesID, shorter.id)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func testStoppedPreviewIgnoresPendingSeekCompletion() async throws {
        let (controller, player, series) = try preview()
        controller.toggle(series)
        controller.beginScrubbing()
        controller.seek(to: 8)
        controller.endScrubbing()
        controller.stop()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(controller.state, .stopped)
        XCTAssertNil(controller.activeSeriesID)
        XCTAssertEqual(controller.currentTime, 0)
        XCTAssertFalse(controller.isScrubbing)
        XCTAssertFalse(controller.canSeek)
        XCTAssertNil(player.currentItem)
        XCTAssertEqual(player.rate, 0)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    private func preview() throws -> (ComparisonPlayer, AVPlayer, LoudnessSeries) {
        let player = AVPlayer()
        player.volume = 0
        return (ComparisonPlayer(player: player), player, try recording("preview.wav", duration: 12))
    }

    @MainActor
    private func recording(_ name: String, duration: Double) throws -> LoudnessSeries {
        let url = root.appendingPathComponent(name)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let count = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
        buffer.frameLength = count
        try XCTUnwrap(buffer.floatChannelData)[0].initialize(repeating: 0, count: Int(count))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return LoudnessSeries(
            sourceID: UUID(),
            sourceName: name,
            url: url,
            preset: nil,
            metrics: AudioMetrics(
                integratedLUFS: -16,
                estimatedSNR: nil,
                snrConfidence: .unavailable,
                points: [.init(time: 0, lufs: -16), .init(time: duration, lufs: -16)]
            )
        )
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Playback did not reach the requested state")
    }
}

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ComparisonPlayer {
    enum State {
        case stopped
        case playing
        case paused
        case ended
    }

    private let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var seekRequestID = UUID()
    private var isSeeking = false
    private var resumeAfterScrubbing = false

    private(set) var activeSeriesID: UUID?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var state: State = .stopped
    private(set) var isScrubbing = false
    private(set) var errorMessage: String?
    var onSelectionChange: (() -> Void)?

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite, !self.isSeeking, !self.isScrubbing {
                    self.currentTime = max(0, seconds)
                }
                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var canSeek: Bool {
        activeSeriesID != nil && duration > 0
    }

    func seek(to seconds: Double) {
        guard canSeek else { return }
        guard seconds.isFinite else {
            errorMessage = "Could not seek to an invalid playback position."
            return
        }
        errorMessage = nil
        let target = min(max(seconds, 0), duration)
        if !isScrubbing {
            if target == duration {
                player.pause()
                state = .ended
            } else if state == .ended {
                state = .paused
            }
        }
        performSeek(to: target)
    }

    func beginScrubbing() {
        guard canSeek, !isScrubbing else { return }
        resumeAfterScrubbing = state == .playing
        isScrubbing = true
        player.pause()
        state = .paused
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        let target = min(currentTime, duration)
        state = target == duration ? .ended : (resumeAfterScrubbing ? .playing : .paused)
        resumeAfterScrubbing = false
        performSeek(to: target)
    }

    func toggle(_ series: LoudnessSeries) {
        errorMessage = nil
        isScrubbing = false
        resumeAfterScrubbing = false

        if activeSeriesID == series.id {
            switch state {
            case .playing:
                player.pause()
                state = .paused
            case .paused:
                state = .playing
                if !isSeeking { player.play() }
            case .ended:
                state = .playing
                performSeek(to: 0)
            case .stopped:
                load(series, at: 0)
            }
            return
        }

        let switchTime = state == .ended ? 0 : currentTime
        load(series, at: switchTime)
    }

    func stop() {
        seekRequestID = UUID()
        isSeeking = false
        isScrubbing = false
        resumeAfterScrubbing = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeEndObserver()
        activeSeriesID = nil
        currentTime = 0
        duration = 0
        state = .stopped
        errorMessage = nil
        onSelectionChange?()
    }

    private func load(_ series: LoudnessSeries, at requestedTime: Double) {
        guard FileManager.default.fileExists(atPath: series.url.path) else {
            errorMessage = "\(series.url.lastPathComponent) is no longer available"
            return
        }

        let item = AVPlayerItem(url: series.url)
        player.pause()
        player.replaceCurrentItem(with: item)
        activeSeriesID = series.id
        currentTime = 0
        let measuredDuration = series.metrics.points.last?.time ?? 0
        duration = measuredDuration.isFinite ? max(measuredDuration, 0) : 0
        state = .playing
        onSelectionChange?()
        observeEnd(of: item)

        let target = min(max(requestedTime, 0), max(duration - 0.05, 0))
        performSeek(to: target)
    }

    private func performSeek(to seconds: Double) {
        guard let item = player.currentItem else { return }
        let requestID = UUID()
        seekRequestID = requestID
        isSeeking = true
        currentTime = seconds
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item,
                      self.player.currentItem === item,
                      self.seekRequestID == requestID else { return }
                self.isSeeking = false
                guard finished else {
                    self.player.pause()
                    self.state = .paused
                    self.resumeAfterScrubbing = false
                    self.errorMessage = item.error?.localizedDescription
                        ?? "Could not move the playhead in the selected file."
                    return
                }
                if self.state == .playing, !self.isScrubbing {
                    self.player.play()
                }
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            MainActor.assumeIsolated {
                guard let self, let item,
                      self.player.currentItem === item,
                      !self.isSeeking, !self.isScrubbing else { return }
                self.currentTime = max(self.duration, self.currentTime)
                self.state = .ended
            }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

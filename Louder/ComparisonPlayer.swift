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

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private(set) var activeSeriesID: UUID?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var state: State = .stopped
    private(set) var errorMessage: String?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
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

    func toggle(_ series: LoudnessSeries) {
        errorMessage = nil

        if activeSeriesID == series.id {
            switch state {
            case .playing:
                player.pause()
                state = .paused
            case .paused:
                player.play()
                state = .playing
            case .ended:
                seek(to: 0) { [weak self] in
                    self?.player.play()
                    self?.state = .playing
                }
            case .stopped:
                load(series, at: 0)
            }
            return
        }

        let switchTime = state == .ended ? 0 : currentTime
        load(series, at: switchTime)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeEndObserver()
        activeSeriesID = nil
        currentTime = 0
        duration = 0
        state = .stopped
        errorMessage = nil
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
        duration = series.metrics.points.last?.time ?? 0
        state = .paused
        observeEnd(of: item)

        let target = min(max(requestedTime, 0), max(duration - 0.05, 0))
        seek(to: target) { [weak self] in
            guard let self else { return }
            player.play()
            state = .playing
        }
    }

    private func seek(to seconds: Double, completion: @escaping @MainActor () -> Void) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in completion() }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
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

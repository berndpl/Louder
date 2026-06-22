import Foundation
import SoundAnalysis
import CoreMedia

/// Detects time windows that are confidently NON-speech (background sound such
/// as children playing, a lawn mower, a dog, crying) using Apple's built-in
/// SoundAnalysis classifier.
///
/// Label-agnostic on purpose: a window is flagged when *speech* confidence is
/// low while some non-speech sound dominates. That way the user's own voice is
/// preserved and only the gaps between speech are eligible for ducking — which
/// is the honest limit of event gating (it suppresses intermittent noise, not
/// noise that continuously overlaps the voice).
enum SoundEventDetector {
    struct NoiseWindow: Sendable {
        let start: Double
        let end: Double
    }

    /// Analyse `url` and return merged non-speech windows. Runs synchronously.
    static func noiseWindows(
        in url: URL,
        speechMaxConfidence: Double = 0.3,
        noiseMinConfidence: Double = 0.55
    ) throws -> [NoiseWindow] {
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let observer = Observer(speechMax: speechMaxConfidence, noiseMin: noiseMinConfidence)
        try analyzer.add(request, withObserver: observer)
        analyzer.analyze() // synchronous; observer is delivered before this returns
        return observer.merged()
    }

    private final class Observer: NSObject, SNResultsObserving {
        private let speechMax: Double
        private let noiseMin: Double
        private var raw: [(Double, Double)] = []

        init(speechMax: Double, noiseMin: Double) {
            self.speechMax = speechMax
            self.noiseMin = noiseMin
        }

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            let start = result.timeRange.start.seconds
            let end = result.timeRange.end.seconds
            guard end > start else { return }

            let speech = result.classification(forIdentifier: "speech")?.confidence ?? 0
            guard speech < speechMax else { return }

            var topNonSpeech = 0.0
            for classification in result.classifications where classification.identifier != "speech" {
                topNonSpeech = max(topNonSpeech, classification.confidence)
            }
            if topNonSpeech >= noiseMin {
                raw.append((start, end))
            }
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {}
        func requestDidComplete(_ request: SNRequest) {}

        /// Coalesce near-adjacent windows so the duck envelope has few edges.
        func merged() -> [NoiseWindow] {
            guard !raw.isEmpty else { return [] }
            let sorted = raw.sorted { $0.0 < $1.0 }
            var windows: [NoiseWindow] = []
            var currentStart = sorted[0].0
            var currentEnd = sorted[0].1
            for window in sorted.dropFirst() {
                if window.0 <= currentEnd + 0.2 {
                    currentEnd = max(currentEnd, window.1)
                } else {
                    windows.append(NoiseWindow(start: currentStart, end: currentEnd))
                    currentStart = window.0
                    currentEnd = window.1
                }
            }
            windows.append(NoiseWindow(start: currentStart, end: currentEnd))
            return windows
        }
    }
}

/// Native (Apple SoundAnalysis) event-gating stage: detects non-speech windows
/// and ducks them with an ffmpeg `volume` envelope. If nothing is detected the
/// stage is a pure pass-through (returns the input unchanged) — no side effects.
struct EventGateStage: AudioStage {
    let id = "gate.soundanalysis.v1"
    let progressLabel = "Muting background noise…"

    /// Linear gain applied inside flagged windows (~ -22 dB).
    private let attenuation = 0.08
    /// Safety cap on the number of envelope segments in the filter string.
    private let maxWindows = 300

    func process(input: URL, workDir: URL) async throws -> URL {
        let windows = (try? SoundEventDetector.noiseWindows(in: input)) ?? []
        guard !windows.isEmpty else { return input }

        let duck = windows.prefix(maxWindows).map { window in
            "volume=\(posix(attenuation)):enable='between(t,\(posix(window.start)),\(posix(window.end)))'"
        }.joined(separator: ",")

        let outputDir = workDir.appendingPathComponent("gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let output = outputDir.appendingPathComponent(input.lastPathComponent)

        let result = try await FFmpeg.run(tool: "ffmpeg", arguments: [
            "-hide_banner", "-y", "-i", input.path,
            "-af", duck,
            "-ar", "48000", "-c:a", "pcm_s16le", output.path
        ])
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw LouderError.processingFailed(FFmpeg.lastLines(of: result.error))
        }
        return output
    }

    private func posix(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

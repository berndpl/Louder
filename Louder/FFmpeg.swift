import Foundation

enum LouderError: LocalizedError {
    case ffmpegMissing
    case deepFilterMissing(String)
    case deepFilterFailed(String)
    case noAudioTrack
    case processingFailed(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            "ffmpeg is not installed. Fix: open Terminal and run \"brew install ffmpeg\""
        case .deepFilterMissing(let message):
            "DeepFilterNet unavailable: \(message)"
        case .deepFilterFailed(let message):
            "DeepFilterNet failed: \(message)"
        case .noAudioTrack:
            "File has no audio track"
        case .processingFailed(let message):
            "Processing failed: \(message)"
        case .backupFailed(let message):
            "Could not create backup: \(message)"
        }
    }
}

enum FFmpeg {
    private static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    struct ToolResult: Sendable {
        let exitCode: Int32
        let output: String
        let error: String
    }

    static func locate(_ tool: String) -> URL? {
        for directory in searchDirectories {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func run(tool: String, arguments: [String]) async throws -> ToolResult {
        guard let executable = locate(tool) else {
            throw LouderError.ffmpegMissing
        }
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    process.standardInput = FileHandle.nullDevice
                    box.store(process)

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }

                    let output = ProcessOutput()
                    let readers = DispatchGroup()
                    readers.enter()
                    DispatchQueue.global(qos: .utility).async {
                        output.standardOutput = outPipe.fileHandleForReading.readDataToEndOfFile()
                        readers.leave()
                    }
                    readers.enter()
                    DispatchQueue.global(qos: .utility).async {
                        output.standardError = errPipe.fileHandleForReading.readDataToEndOfFile()
                        readers.leave()
                    }
                    process.waitUntilExit()
                    readers.wait()

                    continuation.resume(returning: ToolResult(
                        exitCode: process.terminationStatus,
                        output: String(data: output.standardOutput, encoding: .utf8) ?? "",
                        error: String(data: output.standardError, encoding: .utf8) ?? ""
                    ))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    /// Inspects a finished output file and returns human-readable playback
    /// limitations, if any. The video stream is copied from the source, so these
    /// mostly reflect how the original was recorded.
    static func compatibilityWarnings(for url: URL) async -> [String] {
        let result = try? await run(tool: "ffprobe", arguments: [
            "-v", "error",
            "-show_entries", "stream=codec_type,codec_name,pix_fmt,sample_rate,duration",
            "-of", "json",
            url.path
        ])
        guard let result, result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = root["streams"] as? [[String: Any]] else {
            return []
        }

        var warnings: [String] = []
        var videoDuration: Double?
        var audioDuration: Double?

        for stream in streams {
            let type = stream["codec_type"] as? String
            let codec = (stream["codec_name"] as? String)?.lowercased() ?? ""
            let duration = (stream["duration"] as? String).flatMap(Double.init)
            if type == "video" {
                videoDuration = duration ?? videoDuration
                if codec == "hevc" || codec == "h265" {
                    warnings.append("Video is H.265 (HEVC), copied from your recording. It plays on recent Apple devices but not on many older phones, TVs, or web browsers — record in H.264 for the widest reach.")
                } else if !codec.isEmpty, codec != "h264" {
                    warnings.append("Video uses \(codec.uppercased()), copied from your recording. H.264 is the format that plays virtually everywhere.")
                }
                if let pix = stream["pix_fmt"] as? String, !pix.isEmpty, pix != "yuv420p" {
                    warnings.append("Video is \(pix) (high bit-depth or 4:2:2/4:4:4). Many devices only decode 8-bit 4:2:0.")
                }
            } else if type == "audio" {
                audioDuration = duration ?? audioDuration
                if let rate = (stream["sample_rate"] as? String).flatMap(Int.init), rate > 48000 {
                    warnings.append("Audio is \(rate) Hz; some devices only support up to 48 kHz.")
                }
                if !codec.isEmpty, codec != "aac", codec != "mp3" {
                    warnings.append("Audio uses \(codec.uppercased()); AAC is the most broadly supported format.")
                }
            }
        }

        if let v = videoDuration, let a = audioDuration, abs(v - a) > 0.75 {
            warnings.append(String(format: "Audio and video lengths differ by %.1fs, which can cause sync drift.", abs(v - a)))
        }

        return warnings
    }

    static func audioTrackCount(of url: URL) async throws -> Int {
        let result = try await run(tool: "ffprobe", arguments: [
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=index",
            "-of", "csv=p=0",
            url.path
        ])
        guard result.exitCode == 0 else {
            throw LouderError.processingFailed(lastLines(of: result.error))
        }
        return result.output.split(whereSeparator: \.isNewline).count
    }

    /// The highest channel count across the file's audio streams (0 if unknown).
    /// Used to detect surround/multi-channel sources that need a mono downmix
    /// for reliable playback.
    static func maxAudioChannels(of url: URL) async -> Int {
        let result = try? await run(tool: "ffprobe", arguments: [
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=channels",
            "-of", "csv=p=0",
            url.path
        ])
        guard let result, result.exitCode == 0 else { return 0 }
        return result.output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .max() ?? 0
    }

    /// Height in pixels of the first video stream, or `nil` for audio-only files
    /// or when it can't be determined. Used to decide whether a downscale is
    /// needed for the chosen output quality.
    static func videoHeight(of url: URL) async -> Int? {
        let result = try? await run(tool: "ffprobe", arguments: [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=height",
            "-of", "csv=p=0",
            url.path
        ])
        guard let result, result.exitCode == 0 else { return nil }
        return result.output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .first
    }

    static func audioMetrics(of url: URL) async throws -> AudioMetrics {
        let result = try await run(tool: "ffmpeg", arguments: [
            "-hide_banner",
            "-nostats",
            "-loglevel", "verbose",
            "-i", url.path,
            "-map", "0:a:0",
            "-filter:a", "ebur128=framelog=verbose",
            "-f", "null",
            "-"
        ])
        guard result.exitCode == 0 else {
            throw LouderError.processingFailed(lastLines(of: result.error))
        }

        let expression = try NSRegularExpression(
            pattern: #"t:\s*([0-9.]+).*?M:\s*(-?[0-9.]+).*?I:\s*(-?[0-9.]+)\s+LUFS"#
        )
        let text = result.error
        let range = NSRange(text.startIndex..., in: text)
        var points: [LoudnessPoint] = []
        var integratedLUFS: Double?
        expression.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let timeRange = Range(match.range(at: 1), in: text),
                  let momentaryRange = Range(match.range(at: 2), in: text),
                  let integratedRange = Range(match.range(at: 3), in: text),
                  let time = Double(text[timeRange]),
                  let momentary = Double(text[momentaryRange]),
                  let integrated = Double(text[integratedRange]) else {
                return
            }
            points.append(LoudnessPoint(time: time, lufs: max(momentary, -70)))
            integratedLUFS = integrated
        }

        guard let integratedLUFS, !points.isEmpty else {
            throw LouderError.processingFailed("Could not measure audio loudness")
        }

        let snr = estimateSNR(from: points)
        return AudioMetrics(
            integratedLUFS: integratedLUFS,
            estimatedSNR: snr.value,
            snrConfidence: snr.confidence,
            points: downsample(points, maximumCount: 360)
        )
    }

    /// Measures how much of the prepared audio an isolation stage removed, by
    /// comparing the stage's input and output sample-for-sample. Returns the
    /// share of the input's energy that was stripped out (0…1), or `nil` when no
    /// isolation stage ran (`input == output`) or the measurement can't be made.
    ///
    /// The residual `input − output` is exactly the non-voice content the model
    /// took away — background, hiss, the tail of a room. Expressed relative to
    /// the input it answers "how much work did the model do", independent of any
    /// later loudness normalisation and without needing quiet gaps to sample.
    static func isolationRemoval(input: URL, output: URL) async -> Double? {
        guard input.path != output.path else { return nil }
        guard let inputDb = await rmsLevel(of: input),
              let residualDb = await residualRMSLevel(input: input, output: output),
              inputDb.isFinite, residualDb.isFinite else {
            return nil
        }
        // The dB gap between the removed energy and the input energy is a power
        // ratio; convert it to a 0…1 fraction of the input that was removed.
        let fraction = pow(10, (residualDb - inputDb) / 10)
        guard fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1)
    }

    private static func rmsLevel(of url: URL) async -> Double? {
        guard let result = try? await run(tool: "ffmpeg", arguments: [
            "-hide_banner", "-nostats", "-i", url.path,
            "-af", "astats=measure_perchannel=none",
            "-f", "null", "-"
        ]) else {
            return nil
        }
        return parseRMSLevel(from: result.error)
    }

    private static func residualRMSLevel(input: URL, output: URL) async -> Double? {
        // residual = input + (−output): invert the output's polarity and sum
        // without normalising, so the mix is a true sample-wise difference.
        guard let result = try? await run(tool: "ffmpeg", arguments: [
            "-hide_banner", "-nostats", "-i", input.path, "-i", output.path,
            "-filter_complex",
            "[1:a]aeval=-val(0):c=same[inv];"
                + "[0:a][inv]amix=inputs=2:duration=shortest:normalize=0[res];"
                + "[res]astats=measure_perchannel=none[out]",
            "-map", "[out]", "-f", "null", "-"
        ]) else {
            return nil
        }
        return parseRMSLevel(from: result.error)
    }

    /// Pulls the overall RMS level (dB) from an `astats` log line, e.g.
    /// `RMS level dB: -21.891707`.
    private static func parseRMSLevel(from log: String) -> Double? {
        let marker = "RMS level dB:"
        let value = log
            .split(whereSeparator: \.isNewline)
            .last { $0.contains(marker) }?
            .components(separatedBy: marker)
            .last?
            .trimmingCharacters(in: .whitespaces)
        return value.flatMap(Double.init)
    }

    /// Best-effort duration used for positioning an audio fade-out.
    static func audioDuration(of url: URL) async -> Double? {
        if let streamDuration = await duration(of: url, arguments: [
            "-select_streams", "a:0",
            "-show_entries", "stream=duration"
        ]) {
            return streamDuration
        }
        return await duration(of: url, arguments: ["-show_entries", "format=duration"])
    }

    /// Boundaries of speech within an audio file, used to trim leading and
    /// trailing silence. Returns `nil` when the savings would be negligible.
    /// `start`/`end` already include the configured speech padding and are
    /// clamped to `[0, totalDuration]`.
    static func speechBounds(
        of audioURL: URL,
        totalDuration: Double?
    ) async -> (start: Double, end: Double)? {
        let filter = "silencedetect=n=\(TrimSilence.thresholdDB)dB:d=\(TrimSilence.minSilence)"
        let result: ToolResult
        do {
            result = try await run(tool: "ffmpeg", arguments: [
                "-hide_banner", "-nostats",
                "-i", audioURL.path,
                "-map", "0:a:0",
                "-af", filter,
                "-f", "null", "-"
            ])
        } catch {
            return nil
        }
        guard result.exitCode == 0 else { return nil }

        let total: Double?
        if let totalDuration {
            total = totalDuration
        } else {
            total = await audioDuration(of: audioURL)
        }
        guard let total, total > 0 else { return nil }

        // silencedetect prints, in stderr, "silence_start: X" and
        // "silence_end: Y" lines. A leading silence is one starting at ~0; a
        // trailing silence is a start with no matching end before EOF.
        var leadingEnd = 0.0
        var trailingStart = total
        let text = result.error
        var pendingStart: Double?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let value = value(after: "silence_start:", in: line) {
                pendingStart = value
            } else if let value = value(after: "silence_end:", in: line) {
                if let start = pendingStart, start <= 0.05 {
                    leadingEnd = max(leadingEnd, value)
                }
                pendingStart = nil
            }
        }
        // A dangling silence_start with no end runs to EOF: trailing silence.
        if let start = pendingStart, start > leadingEnd {
            trailingStart = start
        }

        let start = max(0, leadingEnd - TrimSilence.pad)
        let end = min(total, trailingStart + TrimSilence.pad)
        guard end - start > 0 else { return nil }

        let savings = (start) + (total - end)
        guard savings >= TrimSilence.minSavings else { return nil }
        return (start, end)
    }

    /// Timestamp of the latest video keyframe at or before `time`, used to
    /// decide whether a trim cut can stream-copy. Probing is limited to the
    /// region before `time` and to keyframes only, so it stays fast.
    static func nearestKeyframe(in videoURL: URL, atOrBefore time: Double) async -> Double? {
        guard time > 0 else { return 0 }
        let window = String(format: "%%+%.3f", time + 0.5)
        let result: ToolResult
        do {
            result = try await run(tool: "ffprobe", arguments: [
                "-v", "error",
                "-select_streams", "v:0",
                "-skip_frame", "nokey",
                "-show_entries", "frame=pts_time",
                "-of", "csv=p=0",
                "-read_intervals", window,
                videoURL.path
            ])
        } catch {
            return nil
        }
        guard result.exitCode == 0 else { return nil }

        var best: Double?
        for token in result.output.split(whereSeparator: { $0 == "\n" || $0 == "," }) {
            guard let value = Double(token), value.isFinite, value <= time else { continue }
            if best == nil || value > best! {
                best = value
            }
        }
        return best
    }

    private static func value(after key: String, in line: String) -> Double? {
        guard let range = line.range(of: key) else { return nil }
        let tail = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let token = tail.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? tail
        return Double(token)
    }

    private static func duration(of url: URL, arguments: [String]) async -> Double? {
        do {
            let result = try await run(tool: "ffprobe", arguments: [
                "-v", "error",
            ] + arguments + [
                "-of", "default=noprint_wrappers=1:nokey=1",
                url.path
            ])
            guard result.exitCode == 0,
                  let value = result.output.split(whereSeparator: \.isNewline).first,
                  let duration = Double(value),
                  duration.isFinite,
                  duration > 0 else {
                return nil
            }
            return duration
        } catch {
            return nil
        }
    }

    static func lastLines(of text: String, count: Int = 3) -> String {
        text.split(whereSeparator: \.isNewline).suffix(count).joined(separator: "\n")
    }

    private static func estimateSNR(
        from points: [LoudnessPoint]
    ) -> (value: Double?, confidence: MetricConfidence) {
        let values = points.map(\.lufs).filter { $0 > -69.5 }.sorted()
        guard values.count >= 20 else {
            return (nil, .unavailable)
        }

        let noiseCount = max(4, values.count / 5)
        let activeStart = values.count / 2
        let noise = median(Array(values.prefix(noiseCount)))
        let active = median(Array(values.suffix(from: activeStart)))
        let separation = active - noise
        guard separation >= 6 else {
            return (nil, .unavailable)
        }
        return (separation, separation >= 12 ? .high : .medium)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    private static func downsample(
        _ points: [LoudnessPoint],
        maximumCount: Int
    ) -> [LoudnessPoint] {
        guard points.count > maximumCount else { return points }
        let stride = Double(points.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            points[Int((Double(index) * stride).rounded())]
        }
    }

    private final class ProcessOutput: @unchecked Sendable {
        var standardOutput = Data()
        var standardError = Data()
    }
}

/// Thread-safe holder so a task cancellation handler can terminate a running
/// `Process` that is created inside a continuation on another queue.
nonisolated final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func store(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            process.terminate()
        } else {
            self.process = process
        }
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning {
            process.terminate()
        }
    }
}

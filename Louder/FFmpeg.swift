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

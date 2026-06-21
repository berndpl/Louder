import Foundation

enum ProcessingPreset: String, CaseIterable, Identifiable, Sendable {
    case boost
    case boostDenoise
    case gentleBoostDenoise
    case studioBooth

    static let preferenceKey = "processingPreset"

    /// Presets offered in the menu picker.
    static var pickerCases: [ProcessingPreset] { [.gentleBoostDenoise, .studioBooth] }

    /// Presets generated when Compare fans out, in display order.
    static var comparePresets: [ProcessingPreset] {
        [.gentleBoostDenoise, .studioBooth]
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .boost: "Boost"
        case .boostDenoise: "Boost + Denoise"
        case .gentleBoostDenoise: "Louder"
        case .studioBooth: "Studio"
        }
    }

    /// Label shown in the menu picker (matches `title`).
    var pickerTitle: String { title }

    /// One-line description of the processing path applied for this option,
    /// shown as a subtitle under the dropdown.
    var pathDescription: String {
        switch self {
        case .studioBooth: "Denoise + studio EQ + compression"
        default: "Denoise + gentle loudness boost"
        }
    }

    var fileSuffix: String { title }

    var iconName: String {
        switch self {
        case .boost: "bolt.fill"
        case .boostDenoise: "wand.and.sparkles"
        case .gentleBoostDenoise: "leaf.fill"
        case .studioBooth: "radio.fill"
        }
    }

    var targetLUFS: Int {
        switch self {
        case .boost, .boostDenoise: -14
        case .gentleBoostDenoise, .studioBooth: -16
        }
    }

    var usesDenoising: Bool {
        self != .boost
    }

    /// Studio Booth tuning, or `nil` for presets that only loudness-normalize.
    var studioBooth: StudioBoothParameters? {
        switch self {
        case .studioBooth: .light
        default: nil
        }
    }

    /// True-peak ceiling for loudnorm. Studio Booth aims slightly lower than the
    /// Gentle baseline to leave headroom for the inter-sample peaks the AAC
    /// encoder re-introduces on its HF-richer output.
    var truePeak: Double {
        studioBooth == nil ? -1 : -1.5
    }

    var loudnormFilter: String {
        let tp = String(format: "%g", truePeak)
        return "loudnorm=I=\(targetLUFS):TP=\(tp):LRA=11"
    }

    static var persisted: Self {
        if let rawValue = UserDefaults.standard.string(forKey: preferenceKey) {
            if let preset = Self(rawValue: rawValue) {
                return preset
            }
            // Collapse the former Studio Booth variants (Light/Medium/Heavy) onto
            // the single Studio Booth preset.
            if rawValue.hasPrefix("studioBooth") {
                UserDefaults.standard.set(studioBooth.rawValue, forKey: preferenceKey)
                return .studioBooth
            }
        }

        // Migrate the two controls used before presets were introduced.
        let oldLoudness = UserDefaults.standard.string(forKey: "loudnessLevel") ?? "gentle"
        let oldCleanup = UserDefaults.standard.string(forKey: "audioCleanupMode") ?? "deepFilter"
        let migrated: Self
        if oldCleanup == "none" {
            migrated = .boost
        } else if oldLoudness == "full" {
            migrated = .boostDenoise
        } else {
            migrated = .gentleBoostDenoise
        }
        UserDefaults.standard.set(migrated.rawValue, forKey: preferenceKey)
        return migrated
    }
}

/// Per-variant tuning for the Studio Booth chain, scaled around values measured
/// from real EarPods voice recordings (dark, boomy, muffled, somewhat roomy).
/// Voiced for a warm, smooth radio tone: body is preserved, presence is added
/// gently, and the harsh 7–9 kHz region is tamed. Heavier variants push
/// presence/air, compression and gating further.
struct StudioBoothParameters: Sendable {
    /// Low-shelf warmth lift around 200 Hz for body/chest.
    let warmth: Double
    /// Narrow boom cut around 120 Hz (proximity rumble).
    let boomCut: Double
    /// Boxiness cut around 350 Hz.
    let boxCut: Double
    /// High-shelf presence lift (de-muffle), starting at 3.5 kHz.
    let presenceShelf: Double
    /// Peak presence lift around 4.5 kHz.
    let presencePeak: Double
    /// Harshness/sibilance tame around 7.5 kHz (a cut).
    let deHarsh: Double
    /// Air lift around 12 kHz; `0` skips it (noise/room-sensitive).
    let air: Double
    /// Compressor ratio (`ratio:1`).
    let compRatio: Double
    /// `aexciter` harmonic amount; `0` skips the exciter.
    let exciter: Double

    static let light = StudioBoothParameters(
        warmth: 1, boomCut: -2, boxCut: -1, presenceShelf: 2, presencePeak: 1.5,
        deHarsh: -1, air: 0, compRatio: 2.5, exciter: 0
    )
}

/// Individually toggleable Studio Booth stages, exposed in the UI so the user
/// can hear which part of the chain is responsible for an over-processed result.
/// Each stage defaults to ON. Only the Studio Booth presets read these; the
/// gentle preset is unaffected.
struct StudioBoothStages: Sendable, Equatable {
    /// Dynamics compression.
    var compression: Bool
    /// Corrective tone shaping (warmth, boom/box cuts, presence and air).
    var eq: Bool

    static let all = StudioBoothStages(compression: true, eq: true)
}

enum AudioFades {
    static let preferenceKey = "addFades"
    static let duration = 0.25

    static var persisted: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }
}

enum RenameOriginal {
    static let preferenceKey = "renameOriginal"

    /// Defaults to `true`, preserving the original in-place replacement behavior.
    static var persisted: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }
}

enum TrimSilence {
    static let preferenceKey = "trimSilence"

    /// Level below which audio counts as silence for head/tail detection.
    static let thresholdDB = -45.0
    /// Minimum continuous silence run to treat as trimmable dead air.
    static let minSilence = 0.35
    /// Speech head/tail kept so words are never clipped.
    static let pad = 0.12
    /// Skip trimming unless at least this much total time would be removed.
    static let minSavings = 0.25
    /// A start cut within this distance of a video keyframe can stream-copy.
    static let keyframeTolerance = 0.3

    /// Defaults to `false`; trimming changes clip length, so it is opt-in.
    static var persisted: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? false
    }
}

enum MetricConfidence: String, Sendable {
    case high
    case medium
    case unavailable
}

struct LoudnessPoint: Identifiable, Sendable {
    let time: Double
    let lufs: Double

    var id: Double { time }
}

struct AudioMetrics: Sendable {
    let integratedLUFS: Double
    let estimatedSNR: Double?
    let snrConfidence: MetricConfidence
    let points: [LoudnessPoint]
}

struct LoudnessSeries: Identifiable, Sendable {
    let id = UUID()
    let sourceID: UUID
    let sourceName: String
    let url: URL
    let preset: ProcessingPreset?
    let metrics: AudioMetrics

    var isOriginal: Bool { preset == nil }
    var displayName: String { preset?.title ?? "Original" }
}

enum UndoOperation: Sendable {
    case restore(originalURL: URL, backupURL: URL)
    case delete(url: URL)
}

struct BatchTransaction: Sendable {
    let operations: [UndoOperation]

    var isEmpty: Bool { operations.isEmpty }
}

struct ProcessingResult: Sendable {
    let series: [LoudnessSeries]
    let undoOperations: [UndoOperation]
    let warnings: [String]
    let outputURLs: [URL]
    /// Seconds of leading/trailing silence removed, when trimming was applied.
    var trimmedSeconds: Double? = nil
}

/// A computed plan for trimming leading/trailing silence from a source clip.
/// Computed once per source so every Compare lane shares an identical cut and
/// stays frame-aligned. `videoStart` is the actual cut applied to both the
/// video and audio streams: a keyframe when stream-copying, or the exact
/// speech start when re-encoding.
struct TrimPlan: Sendable {
    let speechStart: Double
    let speechEnd: Double
    let videoStart: Double
    let reencode: Bool

    var windowLength: Double { max(0, speechEnd - videoStart) }
}

/// Processes one source file and returns every artifact needed by the queue UI.
enum Processor {
    static func process(
        _ url: URL,
        preset: ProcessingPreset,
        compare: Bool,
        addFades: Bool,
        trimSilence: Bool,
        renameOriginal: Bool,
        stages: StudioBoothStages,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessingResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LouderError.processingFailed("File not found: \(url.path)")
        }

        let trackCount = try await FFmpeg.audioTrackCount(of: url)
        guard trackCount > 0 else {
            throw LouderError.noAudioTrack
        }

        let duration = await FFmpeg.audioDuration(of: url)
        let sourceID = UUID()
        onProgress("Measuring original audio…")
        let originalMetrics = try await FFmpeg.audioMetrics(of: url)
        let originalSeries = LoudnessSeries(
            sourceID: sourceID,
            sourceName: url.lastPathComponent,
            url: url,
            preset: nil,
            metrics: originalMetrics
        )

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("louder-\(UUID().uuidString)", isDirectory: true)
        let preparedURL = workDirectory.appendingPathComponent("prepared.wav")
        let cleanedDirectory = workDirectory.appendingPathComponent("cleaned", isDirectory: true)
        let cleanedURL = cleanedDirectory.appendingPathComponent("prepared.wav")
        try FileManager.default.createDirectory(at: cleanedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        onProgress(trackCount > 1
            ? "Preparing and merging \(trackCount) audio tracks…"
            : "Preparing audio…")
        try await prepareAudio(url, at: preparedURL, trackCount: trackCount)

        var trimPlan: TrimPlan?
        if trimSilence {
            onProgress("Detecting silence…")
            if let bounds = await FFmpeg.speechBounds(of: preparedURL, totalDuration: duration) {
                let keyframe = await FFmpeg.nearestKeyframe(in: url, atOrBefore: bounds.start)
                if let keyframe, bounds.start - keyframe <= TrimSilence.keyframeTolerance {
                    trimPlan = TrimPlan(
                        speechStart: bounds.start,
                        speechEnd: bounds.end,
                        videoStart: keyframe,
                        reencode: false
                    )
                } else {
                    trimPlan = TrimPlan(
                        speechStart: bounds.start,
                        speechEnd: bounds.end,
                        videoStart: bounds.start,
                        reencode: true
                    )
                }
            }
        }

        let presets = compare ? ProcessingPreset.comparePresets : [preset]
        var denoiseError: String?
        if presets.contains(where: \.usesDenoising) {
            onProgress("Cleaning voice with DeepFilterNet…")
            do {
                try await DeepFilter.clean(preparedURL, outputDirectory: cleanedDirectory)
                guard FileManager.default.fileExists(atPath: cleanedURL.path) else {
                    throw LouderError.deepFilterFailed("DeepFilterNet did not create cleaned audio")
                }
            } catch {
                if compare {
                    denoiseError = error.localizedDescription
                } else {
                    throw error
                }
            }
        }

        let trimmedSeconds: Double? = trimPlan.flatMap { plan in
            let trimmed = (duration ?? 0) - plan.windowLength
            return trimmed > 0.05 ? trimmed : nil
        }

        if compare {
            var result = await processComparison(
                sourceURL: url,
                sourceID: sourceID,
                originalSeries: originalSeries,
                preparedURL: preparedURL,
                cleanedURL: cleanedURL,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                denoiseError: denoiseError,
                stages: stages,
                onProgress: onProgress
            )
            result.trimmedSeconds = trimmedSeconds
            return result
        }

        var result = try await processReplacement(
            sourceURL: url,
            sourceID: sourceID,
            originalSeries: originalSeries,
            preset: preset,
            preparedURL: preparedURL,
            cleanedURL: cleanedURL,
            duration: duration,
            addFades: addFades,
            trimPlan: trimPlan,
            renameOriginal: renameOriginal,
            stages: stages,
            onProgress: onProgress
        )
        result.trimmedSeconds = trimmedSeconds
        return result
    }

    private static func prepareAudio(
        _ inputURL: URL,
        at outputURL: URL,
        trackCount: Int
    ) async throws {
        var arguments = ["-hide_banner", "-y", "-i", inputURL.path]
        if trackCount > 1 {
            arguments += [
                "-filter_complex",
                "amix=inputs=\(trackCount):duration=longest:normalize=0[aout]",
                "-map", "[aout]"
            ]
        } else {
            arguments += ["-map", "0:a:0"]
        }
        arguments += ["-ar", "48000", "-c:a", "pcm_s16le", outputURL.path]

        let result = try await FFmpeg.run(tool: "ffmpeg", arguments: arguments)
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw LouderError.processingFailed(FFmpeg.lastLines(of: result.error))
        }
    }

    private static func processReplacement(
        sourceURL: URL,
        sourceID: UUID,
        originalSeries: LoudnessSeries,
        preset: ProcessingPreset,
        preparedURL: URL,
        cleanedURL: URL,
        duration: Double?,
        addFades: Bool,
        trimPlan: TrimPlan?,
        renameOriginal: Bool,
        stages: StudioBoothStages,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessingResult {
        if !renameOriginal {
            return try await processSeparate(
                sourceURL: sourceURL,
                sourceID: sourceID,
                originalSeries: originalSeries,
                preset: preset,
                preparedURL: preparedURL,
                cleanedURL: cleanedURL,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                stages: stages,
                onProgress: onProgress
            )
        }

        let backupURL = freeBackupURL(for: sourceURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: backupURL)
        } catch {
            throw LouderError.backupFailed(error.localizedDescription)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("louder-output-\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let metrics: AudioMetrics
        do {
            onProgress("Creating \(preset.title)…")
            try await render(
                sourceURL: sourceURL,
                audioURL: preset.usesDenoising ? cleanedURL : preparedURL,
                outputURL: tempURL,
                preset: preset,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                stages: stages
            )

            onProgress("Measuring result…")
            metrics = try await FFmpeg.audioMetrics(of: tempURL)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: backupURL)
            throw error
        }

        do {
            try FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.moveItem(at: tempURL, to: sourceURL)

            let backupSeries = LoudnessSeries(
                sourceID: sourceID,
                sourceName: sourceURL.lastPathComponent,
                url: backupURL,
                preset: nil,
                metrics: originalSeries.metrics
            )
            let outputSeries = LoudnessSeries(
                sourceID: sourceID,
                sourceName: sourceURL.lastPathComponent,
                url: sourceURL,
                preset: preset,
                metrics: metrics
            )
            return ProcessingResult(
                series: [backupSeries, outputSeries],
                undoOperations: [.restore(originalURL: sourceURL, backupURL: backupURL)],
                warnings: [],
                outputURLs: [sourceURL]
            )
        } catch {
            throw error
        }
    }

    /// Non-destructive single-preset processing: the original file is left
    /// untouched and the improved version is written to a new sibling name.
    private static func processSeparate(
        sourceURL: URL,
        sourceID: UUID,
        originalSeries: LoudnessSeries,
        preset: ProcessingPreset,
        preparedURL: URL,
        cleanedURL: URL,
        duration: Double?,
        addFades: Bool,
        trimPlan: TrimPlan?,
        stages: StudioBoothStages,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessingResult {
        let outputURL = freeComparisonURL(for: sourceURL, preset: preset)
        do {
            onProgress("Creating \(preset.title)…")
            try await render(
                sourceURL: sourceURL,
                audioURL: preset.usesDenoising ? cleanedURL : preparedURL,
                outputURL: outputURL,
                preset: preset,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                stages: stages
            )

            try Task.checkCancellation()
            onProgress("Measuring result…")
            let metrics = try await FFmpeg.audioMetrics(of: outputURL)

            let outputSeries = LoudnessSeries(
                sourceID: sourceID,
                sourceName: sourceURL.lastPathComponent,
                url: outputURL,
                preset: preset,
                metrics: metrics
            )
            return ProcessingResult(
                series: [originalSeries, outputSeries],
                undoOperations: [.delete(url: outputURL)],
                warnings: [],
                outputURLs: [outputURL]
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func processComparison(
        sourceURL: URL,
        sourceID: UUID,
        originalSeries: LoudnessSeries,
        preparedURL: URL,
        cleanedURL: URL,
        duration: Double?,
        addFades: Bool,
        trimPlan: TrimPlan?,
        denoiseError: String?,
        stages: StudioBoothStages,
        onProgress: @Sendable @escaping (String) -> Void
    ) async -> ProcessingResult {
        var series = [originalSeries]
        var operations: [UndoOperation] = []
        var warnings: [String] = []
        var outputs: [URL] = []

        if let denoiseError {
            warnings.append("Denoised presets unavailable: \(denoiseError)")
        }

        for preset in ProcessingPreset.comparePresets {
            if Task.isCancelled {
                for url in outputs {
                    try? FileManager.default.removeItem(at: url)
                }
                outputs.removeAll()
                operations.removeAll()
                series = [originalSeries]
                break
            }
            let outputURL = freeComparisonURL(for: sourceURL, preset: preset)
            if preset.usesDenoising, denoiseError != nil {
                continue
            }
            do {
                onProgress("Creating \(preset.title)…")
                try await render(
                    sourceURL: sourceURL,
                    audioURL: preset.usesDenoising ? cleanedURL : preparedURL,
                    outputURL: outputURL,
                    preset: preset,
                    duration: duration,
                    addFades: addFades,
                    trimPlan: trimPlan,
                    stages: stages
                )
                try Task.checkCancellation()
                onProgress("Measuring \(preset.title)…")
                let metrics = try await FFmpeg.audioMetrics(of: outputURL)
                series.append(LoudnessSeries(
                    sourceID: sourceID,
                    sourceName: sourceURL.lastPathComponent,
                    url: outputURL,
                    preset: preset,
                    metrics: metrics
                ))
                operations.append(.delete(url: outputURL))
                outputs.append(outputURL)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                warnings.append("\(preset.title): \(error.localizedDescription)")
            }
        }

        return ProcessingResult(
            series: series,
            undoOperations: operations,
            warnings: warnings,
            outputURLs: outputs
        )
    }

    private static func render(
        sourceURL: URL,
        audioURL: URL,
        outputURL: URL,
        preset: ProcessingPreset,
        duration: Double?,
        addFades: Bool,
        trimPlan: TrimPlan?,
        stages: StudioBoothStages
    ) async throws {
        // When trimming, both the video source and the processed-audio input
        // are seeked to the same start so they stay in sync; the output is
        // bounded to the trimmed window length and the audio fades land on the
        // trimmed edges.
        let effectiveDuration = trimPlan.map { $0.windowLength } ?? duration
        let audioFilter = filter(
            for: preset,
            addFades: addFades,
            duration: effectiveDuration,
            stages: stages
        )

        var arguments = ["-hide_banner", "-y"]
        if let trimPlan {
            let start = posix(trimPlan.videoStart)
            arguments += ["-ss", start, "-i", sourceURL.path]
            arguments += ["-ss", start, "-i", audioURL.path]
        } else {
            arguments += ["-i", sourceURL.path, "-i", audioURL.path]
        }
        arguments += [
            "-map", "0:v:0?",
            "-map", "1:a:0",
            "-af", audioFilter
        ]
        if let trimPlan, trimPlan.reencode {
            arguments += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]
        } else {
            arguments += ["-c:v", "copy"]
        }
        if let trimPlan {
            arguments += ["-t", posix(trimPlan.windowLength)]
        }
        arguments += ["-c:a", "aac", outputURL.path]

        let result = try await FFmpeg.run(tool: "ffmpeg", arguments: arguments)
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw LouderError.processingFailed(FFmpeg.lastLines(of: result.error))
        }
    }

    private static func filter(
        for preset: ProcessingPreset,
        addFades: Bool,
        duration: Double?,
        stages: StudioBoothStages
    ) -> String {
        var filters = processingChain(for: preset, stages: stages)
        if addFades, let duration, duration >= AudioFades.duration * 2 {
            let fadeOutStart = posix(duration - AudioFades.duration)
            filters += [
                "afade=t=in:st=0:d=\(AudioFades.duration):curve=qsin",
                "afade=t=out:st=\(fadeOutStart):d=\(AudioFades.duration):curve=qsin"
            ]
        }
        if let duration {
            filters += ["apad", "atrim=duration=\(posix(duration))"]
        }
        return filters.joined(separator: ",")
    }

    /// Core DSP chain for a preset, before fades/padding. Gentle presets only
    /// loudness-normalize; Studio Booth layers corrective EQ, a de-muffling
    /// presence/air lift, compression and saturation on top of the denoised
    /// signal before the final loudness target.
    private static func processingChain(for preset: ProcessingPreset, stages: StudioBoothStages) -> [String] {
        guard let booth = preset.studioBooth else {
            return [preset.loudnormFilter]
        }

        var chain: [String] = ["highpass=f=80"]
        // Tone shaping: keep body, tame boom/box, add gentle presence + air,
        // and pull down the harsh 7–9 kHz region.
        if stages.eq {
            chain.append("bass=f=200:g=\(posix(booth.warmth))")
            chain.append("equalizer=f=120:t=q:w=1.4:g=\(posix(booth.boomCut))")
            chain.append("equalizer=f=350:t=q:w=1.2:g=\(posix(booth.boxCut))")
            chain.append("treble=f=3500:g=\(posix(booth.presenceShelf))")
            chain.append("equalizer=f=4500:t=q:w=1.2:g=\(posix(booth.presencePeak))")
            chain.append("equalizer=f=7500:t=q:w=1.5:g=\(posix(booth.deHarsh))")
            if booth.air > 0 {
                chain.append("equalizer=f=12000:t=q:w=1.0:g=\(posix(booth.air))")
            }
        }
        if stages.compression {
            chain.append("acompressor=threshold=-20dB:ratio=\(posix(booth.compRatio)):attack=20:release=160")
        }
        if booth.exciter > 0 {
            chain.append("aexciter=amount=\(posix(booth.exciter))")
        }
        chain.append(preset.loudnormFilter)
        // Oversampled brick-wall safety: catch inter-sample peaks before AAC by
        // limiting at 4x rate (level=disabled so it never auto-normalizes up).
        chain.append("aresample=192000")
        chain.append("alimiter=limit=0.95:level=disabled")
        chain.append("aresample=48000")
        return chain
    }

    private static func posix(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func freeBackupURL(for url: URL) -> URL {
        freeSiblingURL(for: url, suffix: "original")
    }

    private static func freeComparisonURL(for url: URL, preset: ProcessingPreset) -> URL {
        freeSiblingURL(for: url, suffix: preset.fileSuffix)
    }

    private static func freeSiblingURL(for url: URL, suffix: String) -> URL {
        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = directory.appendingPathComponent("\(name) - \(suffix).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) - \(suffix) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

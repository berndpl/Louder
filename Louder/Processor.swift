import Foundation

/// A documentation link for a model or framework used by a signal step.
struct DocLink: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let url: URL

    init(_ title: String, _ urlString: String) {
        self.title = title
        self.url = URL(string: urlString)!
    }
}

/// One stompbox in a preset's signal chain, used by the info popover to draw a
/// little schematic of pedals the audio passes through, in order.
struct SignalStep: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let systemImage: String
    /// Plain-language detail: which model runs and the parameters applied.
    let detail: String
    /// Documentation links for the model/framework this step uses.
    let docs: [DocLink]
}

enum ProcessingPreset: String, CaseIterable, Identifiable, Sendable {
    case boost
    case boostDenoise
    case gentleBoostDenoise
    case studioBooth
    case focus
    case clean

    static let preferenceKey = "processingPreset"

    /// Presets offered in the menu picker.
    static var pickerCases: [ProcessingPreset] { [.gentleBoostDenoise, .studioBooth, .focus, .clean] }

    /// Presets generated when Compare fans out, in display order. Mirrors the
    /// picker so every available preset produces a variant to compare.
    static var comparePresets: [ProcessingPreset] {
        pickerCases
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .boost: "Boost"
        case .boostDenoise: "Boost + Denoise"
        case .gentleBoostDenoise: "Louder"
        case .studioBooth: "Studio"
        case .focus: "Focus"
        case .clean: "Clean"
        }
    }

    /// Label shown in the menu picker (matches `title`).
    var pickerTitle: String { title }

    /// One-line description of the processing path applied for this option,
    /// shown as a subtitle under the dropdown.
    var pathDescription: String {
        switch self {
        case .studioBooth: "Denoise + studio EQ + compression"
        case .focus: "Mute background noise + denoise + boost"
        case .clean: "AI speech cleanup + loudness boost"
        default: "Denoise + gentle loudness boost"
        }
    }

    var fileSuffix: String { title }

    /// Ordered schematic of the signal chain applied to the voice, expressed as
    /// connected "stompboxes" for the info popover. Mirrors `audioStages` plus
    /// the terminal render (Studio EQ/compression and the loudness boost), and
    /// names the actual model and parameters used at each step.
    var signalChain: [SignalStep] {
        var steps: [SignalStep] = []
        switch self {
        case .boost:
            break
        case .boostDenoise, .gentleBoostDenoise:
            steps.append(Self.denoiseStep)
        case .studioBooth:
            steps.append(Self.denoiseStep)
            if let booth = studioBooth {
                steps.append(SignalStep(
                    name: "Studio EQ",
                    systemImage: "slider.horizontal.3",
                    detail: "Corrective tone shaping (ffmpeg biquads): high-pass at 80 Hz, then "
                        + "\(Self.db(booth.warmth)) low-shelf @200 Hz (warmth), "
                        + "\(Self.db(booth.boomCut)) @120 Hz (cut boom), "
                        + "\(Self.db(booth.boxCut)) @350 Hz (cut box), "
                        + "\(Self.db(booth.presenceShelf)) treble shelf @3.5 kHz and "
                        + "\(Self.db(booth.presencePeak)) @4.5 kHz (presence), "
                        + "\(Self.db(booth.deHarsh)) @7.5 kHz (de-harsh).",
                    docs: [DocLink("ffmpeg audio filters", "https://ffmpeg.org/ffmpeg-filters.html#Audio-Filters")]
                ))
                steps.append(SignalStep(
                    name: "Compress",
                    systemImage: "rectangle.compress.vertical",
                    detail: "ffmpeg acompressor: \(Self.num(booth.compRatio)):1 ratio, −20 dB "
                        + "threshold, 20 ms attack, 160 ms release — evens out level dynamics for a steadier, broadcast feel.",
                    docs: [DocLink("ffmpeg acompressor", "https://ffmpeg.org/ffmpeg-filters.html#acompressor")]
                ))
            }
        case .focus:
            steps.append(SignalStep(
                name: "Noise Gate",
                systemImage: "speaker.slash.fill",
                detail: "Apple SoundAnalysis (SNClassifySoundRequest, version1 classifier). Flags "
                    + "windows where speech confidence < 0.30 while a non-speech class scores ≥ 0.55, "
                    + "then ducks those windows by ~−22 dB (linear gain 0.08). Suppresses intermittent "
                    + "background events between words, not noise that overlaps the voice.",
                docs: [DocLink("Apple SoundAnalysis", "https://developer.apple.com/documentation/soundanalysis")]
            ))
            steps.append(Self.denoiseStep)
        case .clean:
            steps.append(SignalStep(
                name: "AI Enhance",
                systemImage: "wand.and.stars",
                detail: "GTCRN waveform-to-waveform Core ML model (gtcrn_w2w) at 16 kHz, run on-device "
                    + "in 6 s windows with 2 s overlap-add crossfade to stay responsive on long clips. "
                    + "Output is band-limited to ~8 kHz (cleaner but duller), then resampled back to 48 kHz.",
                docs: [
                    DocLink("GTCRN model", "https://github.com/Xiaobin-Rong/gtcrn"),
                    DocLink("Core ML", "https://developer.apple.com/documentation/coreml")
                ]
            ))
        }

        let tp = truePeak == truePeak.rounded() ? "−\(Int(-truePeak))" : "−1.5"
        var loudnessDetail = "ffmpeg loudnorm (two-pass EBU R128) → \(targetLUFS) LUFS integrated, "
            + "true-peak \(tp) dBTP, loudness range 11 LU. Encoded as 48 kHz AAC-LC."
        if studioBooth != nil {
            loudnessDetail += " A 4× oversampled brick-wall limiter (alimiter 0.95) follows to catch "
                + "inter-sample peaks before AAC."
        }
        steps.append(SignalStep(
            name: "Loudness",
            systemImage: "speaker.wave.3.fill",
            detail: loudnessDetail,
            docs: [
                DocLink("ffmpeg loudnorm", "https://ffmpeg.org/ffmpeg-filters.html#loudnorm"),
                DocLink("EBU R128", "https://tech.ebu.ch/publications/r128")
            ]
        ))
        return steps
    }

    /// The shared DeepFilterNet denoise pedal (used by several presets).
    private static let denoiseStep = SignalStep(
        name: "Denoise",
        systemImage: "wand.and.sparkles",
        detail: "DeepFilterNet3 (ONNX), a full-band 48 kHz deep-learning speech denoiser running as a "
            + "bundled native binary on-device. Removes steady background noise and hiss while keeping the voice intact.",
        docs: [DocLink("DeepFilterNet", "https://github.com/Rikorose/DeepFilterNet")]
    )

    /// Format a dB gain with an explicit sign and a typographic minus.
    private static func db(_ value: Double) -> String {
        let magnitude = num(abs(value))
        if value > 0 { return "+\(magnitude) dB" }
        if value < 0 { return "−\(magnitude) dB" }
        return "0 dB"
    }

    /// Format a number, dropping a trailing `.0`.
    private static func num(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    var iconName: String {
        switch self {
        case .boost: "bolt.fill"
        case .boostDenoise: "wand.and.sparkles"
        case .gentleBoostDenoise: "leaf.fill"
        case .studioBooth: "radio.fill"
        case .focus: "speaker.slash.fill"
        case .clean: "wand.and.stars"
        }
    }

    var targetLUFS: Int {
        switch self {
        case .boost, .boostDenoise: -14
        case .gentleBoostDenoise, .studioBooth, .focus, .clean: -16
        }
    }

    var usesDenoising: Bool {
        self != .boost
    }

    /// Human label for the isolation model a preset runs, shown in the
    /// "Isolation" assessment box. `nil` for presets that don't isolate.
    var isolationLabel: String? {
        switch self {
        case .boost: nil
        case .clean: "AI enhance"
        case .focus: "Gate + DeepFilterNet"
        case .boostDenoise, .gentleBoostDenoise, .studioBooth: "DeepFilterNet"
        }
    }

    /// Ordered, side-effect-free WAV stages applied to the prepared audio before
    /// the terminal render (loudnorm / Studio EQ+comp). Declaring the chain here
    /// is what keeps the pipeline modular: a step is added or removed by editing
    /// this list, with no effect on the others.
    var audioStages: [AudioStage] {
        switch self {
        case .boost:
            []
        case .focus:
            [EventGateStage(), DenoiseDFNStage()]
        case .clean:
            [EnhanceStage()]
        case .boostDenoise, .gentleBoostDenoise, .studioBooth:
            [DenoiseDFNStage()]
        }
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

/// Output video quality, expressed as a maximum height the video may keep.
/// A source at or below the cap is copied untouched (the long-standing
/// behavior); a source above the cap is downscaled to the cap and re-encoded to
/// broadly-compatible H.264.
enum OutputResolution: String, Sendable, CaseIterable, Identifiable {
    case uhd4k = "4K"
    case fullHD = "1080p"

    var id: String { rawValue }

    /// Maximum video height kept for this quality.
    var capHeight: Int {
        switch self {
        case .uhd4k: return 2160
        case .fullHD: return 1080
        }
    }

    /// Short label for the segmented control.
    var label: String { rawValue }

    static let preferenceKey = "outputResolution"

    /// Defaults to `.uhd4k`, preserving today's copy-untouched behavior for the
    /// typical (≤4K) recording.
    static var persisted: OutputResolution {
        guard let raw = UserDefaults.standard.string(forKey: preferenceKey),
              let value = OutputResolution(rawValue: raw) else {
            return .uhd4k
        }
        return value
    }

    static func persist(_ value: OutputResolution) {
        UserDefaults.standard.set(value.rawValue, forKey: preferenceKey)
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
    /// Share of the prepared signal's energy the isolation stage removed (0…1),
    /// or `nil` for the original / presets without an isolation stage.
    var isolationRemoval: Double? = nil
    /// Size in bytes of the original input file (baseline for the Size card).
    var originalBytes: Int64? = nil
    /// Size in bytes of the produced output file.
    var outputBytes: Int64? = nil
    /// Whether the video stream was re-encoded (downscale and/or trim). The Size
    /// card only appears when this is true.
    var videoReencoded: Bool = false
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
    var warnings: [String]
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
        resolution: OutputResolution,
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
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        onProgress(trackCount > 1
            ? "Preparing and merging \(trackCount) audio tracks…"
            : "Preparing audio…")
        let sourceChannels = await FFmpeg.maxAudioChannels(of: url)
        let mergedFromChannels = sourceChannels > 2 ? sourceChannels : nil
        try await prepareAudio(
            url,
            at: preparedURL,
            trackCount: trackCount,
            downmixToMono: mergedFromChannels != nil
        )
        let mergeNote = mergedFromChannels.map {
            "Merged \($0)-channel audio to mono to avoid playback issues on some devices."
        }

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
                workDir: workDirectory,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                resolution: resolution,
                stages: stages,
                onProgress: onProgress
            )
            result.trimmedSeconds = trimmedSeconds
            if let mergeNote { result.warnings.insert(mergeNote, at: 0) }
            return result
        }

        let audioURL = try await AudioPipeline.run(
            preset.audioStages,
            input: preparedURL,
            workDir: workDirectory,
            onProgress: onProgress
        )
        let isolationRemoval = await FFmpeg.isolationRemoval(
            input: preparedURL,
            output: audioURL
        )

        var result = try await processReplacement(
            sourceURL: url,
            sourceID: sourceID,
            originalSeries: originalSeries,
            preset: preset,
            audioURL: audioURL,
            isolationRemoval: isolationRemoval,
            duration: duration,
            addFades: addFades,
            trimPlan: trimPlan,
            renameOriginal: renameOriginal,
            resolution: resolution,
            stages: stages,
            onProgress: onProgress
        )
        result.trimmedSeconds = trimmedSeconds
        if let mergeNote { result.warnings.insert(mergeNote, at: 0) }
        return result
    }

    private static func prepareAudio(
        _ inputURL: URL,
        at outputURL: URL,
        trackCount: Int,
        downmixToMono: Bool
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
        if downmixToMono {
            arguments += ["-ac", "1"]
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
        audioURL: URL,
        isolationRemoval: Double?,
        duration: Double?,
        addFades: Bool,
        trimPlan: TrimPlan?,
        renameOriginal: Bool,
        resolution: OutputResolution,
        stages: StudioBoothStages,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessingResult {
        if !renameOriginal {
            return try await processSeparate(
                sourceURL: sourceURL,
                sourceID: sourceID,
                originalSeries: originalSeries,
                preset: preset,
                audioURL: audioURL,
                isolationRemoval: isolationRemoval,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                resolution: resolution,
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
            let originalBytes = fileSize(of: sourceURL)
            let videoReencoded = try await render(
                sourceURL: sourceURL,
                audioURL: audioURL,
                outputURL: tempURL,
                preset: preset,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                resolution: resolution,
                stages: stages
            )

            onProgress("Measuring result…")
            var measured = try await FFmpeg.audioMetrics(of: tempURL)
            measured.isolationRemoval = isolationRemoval
            measured.originalBytes = originalBytes
            measured.outputBytes = fileSize(of: tempURL)
            measured.videoReencoded = videoReencoded
            metrics = measured
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
                warnings: await FFmpeg.compatibilityWarnings(for: sourceURL),
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
        audioURL: URL,
        isolationRemoval: Double?,
        duration: Double?,
        addFades: Bool,
        trimPlan: TrimPlan?,
        resolution: OutputResolution,
        stages: StudioBoothStages,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessingResult {
        let outputURL = freeComparisonURL(for: sourceURL, preset: preset)
        do {
            onProgress("Creating \(preset.title)…")
            let originalBytes = fileSize(of: sourceURL)
            let videoReencoded = try await render(
                sourceURL: sourceURL,
                audioURL: audioURL,
                outputURL: outputURL,
                preset: preset,
                duration: duration,
                addFades: addFades,
                trimPlan: trimPlan,
                resolution: resolution,
                stages: stages
            )

            try Task.checkCancellation()
            onProgress("Measuring result…")
            var metrics = try await FFmpeg.audioMetrics(of: outputURL)
            metrics.isolationRemoval = isolationRemoval
            metrics.originalBytes = originalBytes
            metrics.outputBytes = fileSize(of: outputURL)
            metrics.videoReencoded = videoReencoded

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
                warnings: await FFmpeg.compatibilityWarnings(for: outputURL),
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
        workDir: URL,
        duration: Double?,
        addFades: Bool,
        trimPlan: TrimPlan?,
        resolution: OutputResolution,
        stages: StudioBoothStages,
        onProgress: @Sendable @escaping (String) -> Void
    ) async -> ProcessingResult {
        var series = [originalSeries]
        var operations: [UndoOperation] = []
        var warnings: [String] = []
        var outputs: [URL] = []
        // Shared across compared presets so an identical stage (e.g. denoise)
        // runs only once.
        var stageCache: [String: Result<URL, Error>] = [:]

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

            let audioURL: URL
            do {
                audioURL = try await AudioPipeline.run(
                    preset.audioStages,
                    input: preparedURL,
                    workDir: workDir,
                    cache: &stageCache,
                    onProgress: onProgress
                )
            } catch {
                warnings.append("\(preset.title): \(error.localizedDescription)")
                continue
            }

            do {
                onProgress("Creating \(preset.title)…")
                let originalBytes = fileSize(of: sourceURL)
                let videoReencoded = try await render(
                    sourceURL: sourceURL,
                    audioURL: audioURL,
                    outputURL: outputURL,
                    preset: preset,
                    duration: duration,
                    addFades: addFades,
                    trimPlan: trimPlan,
                    resolution: resolution,
                    stages: stages
                )
                try Task.checkCancellation()
                onProgress("Measuring \(preset.title)…")
                var metrics = try await FFmpeg.audioMetrics(of: outputURL)
                metrics.isolationRemoval = await FFmpeg.isolationRemoval(
                    input: preparedURL,
                    output: audioURL
                )
                metrics.originalBytes = originalBytes
                metrics.outputBytes = fileSize(of: outputURL)
                metrics.videoReencoded = videoReencoded
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

        if let firstOutput = outputs.first {
            warnings.append(contentsOf: await FFmpeg.compatibilityWarnings(for: firstOutput))
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
        resolution: OutputResolution,
        stages: StudioBoothStages
    ) async throws -> Bool {
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

        // Downscale only when the source video exceeds the chosen height cap;
        // anything at or below the cap is copied untouched.
        let sourceHeight = await FFmpeg.videoHeight(of: sourceURL)
        let downscaleHeight: Int? = sourceHeight.flatMap {
            $0 > resolution.capHeight ? resolution.capHeight : nil
        }
        let reencodeVideo = (trimPlan?.reencode ?? false) || downscaleHeight != nil

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
        if reencodeVideo {
            // -2 keeps the width auto-computed to an even number, preserving
            // aspect ratio. H.264 8-bit 4:2:0 for the broadest playback support.
            if let downscaleHeight {
                arguments += ["-vf", "scale=-2:\(downscaleHeight)"]
            }
            arguments += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]
        } else {
            arguments += ["-c:v", "copy"]
        }
        if let trimPlan {
            arguments += ["-t", posix(trimPlan.windowLength)]
        }
        // Encode broadly-compatible 48 kHz AAC-LC. loudnorm otherwise resamples
        // to 96 kHz, which several hardware decoders refuse to play; pin 48 kHz.
        arguments += ["-c:a", "aac", "-b:a", "192k", "-ar", "48000"]
        // Move the moov atom to the front so the file starts playing immediately
        // everywhere (progressive download, web players, embedded viewers).
        if ["mp4", "m4v", "mov", "m4a"].contains(outputURL.pathExtension.lowercased()) {
            arguments += ["-movflags", "+faststart"]
        }
        arguments += [outputURL.path]

        let result = try await FFmpeg.run(tool: "ffmpeg", arguments: arguments)
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw LouderError.processingFailed(FFmpeg.lastLines(of: result.error))
        }
        return reencodeVideo
    }

    /// Size in bytes of a file on disk, or `nil` if it can't be read.
    private static func fileSize(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64
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

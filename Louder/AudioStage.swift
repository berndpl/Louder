import Foundation

/// A side-effect-free, file→file audio transform applied to the prepared WAV
/// before the terminal FFmpeg render. Stages never mutate their input: each
/// reads `input` and writes a *new* file under `workDir`, returning its URL.
///
/// This is what makes the processing pipeline modular — a preset's pre-render
/// chain is just an ordered `[AudioStage]`, so adding or removing a step (a
/// denoiser, an event gate, an AI enhancer, a speaker isolator) has no side
/// effect on the others.
protocol AudioStage: Sendable {
    /// Stable identifier used to memoise/share a stage's output across presets
    /// (e.g. denoise is computed once when Compare fans out to several presets).
    var id: String { get }

    /// Progress message shown while the stage runs.
    var progressLabel: String { get }

    /// Transform `input` into a new WAV under `workDir`; return its URL.
    func process(input: URL, workDir: URL) async throws -> URL
}

/// Runs an ordered list of `AudioStage`s, folding the working file through each.
///
/// Outputs are memoised in `cache` keyed by `(stage.id, input path)`, so an
/// identical stage shared by multiple presets (Compare) runs only once —
/// caching both successes and failures to avoid recomputation.
enum AudioPipeline {
    static func run(
        _ stages: [AudioStage],
        input: URL,
        workDir: URL,
        cache: inout [String: Result<URL, Error>],
        onProgress: @Sendable (String) -> Void
    ) async throws -> URL {
        var current = input
        for stage in stages {
            let key = "\(stage.id)::\(current.path)"
            if let cached = cache[key] {
                current = try cached.get()
                continue
            }
            onProgress(stage.progressLabel)
            do {
                let output = try await stage.process(input: current, workDir: workDir)
                cache[key] = .success(output)
                current = output
            } catch {
                cache[key] = .failure(error)
                throw error
            }
        }
        return current
    }

    /// Convenience for single-preset runs that don't need cross-preset caching.
    static func run(
        _ stages: [AudioStage],
        input: URL,
        workDir: URL,
        onProgress: @Sendable (String) -> Void
    ) async throws -> URL {
        var cache: [String: Result<URL, Error>] = [:]
        return try await run(stages, input: input, workDir: workDir, cache: &cache, onProgress: onProgress)
    }
}

/// DeepFilterNet3 stationary-noise suppression — the original denoise step,
/// now expressed as a modular stage.
struct DenoiseDFNStage: AudioStage {
    let id = "denoise.deepfilternet3"
    let progressLabel = "Cleaning voice with DeepFilterNet…"

    func process(input: URL, workDir: URL) async throws -> URL {
        let outputDir = workDir.appendingPathComponent("denoise-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try await DeepFilter.clean(input, outputDirectory: outputDir)
        let output = outputDir.appendingPathComponent(input.lastPathComponent)
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw LouderError.deepFilterFailed("DeepFilterNet did not create cleaned audio")
        }
        return output
    }
}

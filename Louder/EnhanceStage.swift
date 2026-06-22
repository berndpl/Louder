import Foundation
import CoreML
import AVFoundation

/// AI speech enhancement stage. Runs a self-contained waveform→waveform Core ML
/// model that suppresses noise and restores speech, then hands a clean WAV back
/// to the pipeline for loudness normalisation.
///
/// The model is intentionally model-agnostic plumbing: it takes a mono Float32
/// signal at `modelSampleRate` and returns one of the same rate. Swapping in a
/// different (e.g. 48 kHz MossFormer2) model later only means replacing the
/// bundled `.mlpackage` and `modelSampleRate` — no other code changes.
///
/// NOTE: the current bundled model (GTCRN) runs at 16 kHz, so its output is
/// band-limited to ~8 kHz — cleaner but duller than the 48 kHz DeepFilterNet
/// path. This is the deliberate baseline; a full-band model can replace it.
struct EnhanceStage: AudioStage {
    let id = "enhance.gtcrn16k"
    let progressLabel = "Enhancing voice with AI…"

    /// Sample rate the bundled Core ML model expects/produces.
    let modelSampleRate = 16_000

    /// Resource name of the compiled Core ML model in the app bundle.
    private let modelResource = "gtcrn_w2w"

    func process(input: URL, workDir: URL) async throws -> URL {
        let dir = workDir.appendingPathComponent("enhance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Down-mix/resample the prepared audio to the model's rate (mono f32).
        let modelInput = dir.appendingPathComponent("model-in.wav")
        try await resample(input, to: modelInput, sampleRate: modelSampleRate, codec: "pcm_f32le")

        // 2. Read samples, run the model, write the enhanced signal back out.
        let samples = try Self.readMonoFloatSamples(modelInput)
        let enhanced = try await Self.runModel(samples, resource: modelResource)
        let modelOutput = dir.appendingPathComponent("model-out.wav")
        try Self.writeMonoFloatSamples(enhanced, to: modelOutput, sampleRate: Double(modelSampleRate))

        // 3. Resample back to the pipeline's 48 kHz 16-bit WAV, matching siblings.
        let output = dir.appendingPathComponent(input.lastPathComponent)
        try await resample(modelOutput, to: output, sampleRate: 48_000, codec: "pcm_s16le")
        return output
    }

    // MARK: - Resampling (via the bundled ffmpeg, like the rest of the pipeline)

    private func resample(_ input: URL, to output: URL, sampleRate: Int, codec: String) async throws {
        let result = try await FFmpeg.run(tool: "ffmpeg", arguments: [
            "-y", "-i", input.path,
            "-ac", "1", "-ar", String(sampleRate), "-c:a", codec,
            output.path
        ])
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: output.path) else {
            let message = FFmpeg.lastLines(of: result.error, count: 5)
            throw LouderError.processingFailed(
                message.isEmpty ? "Resampling failed before AI enhancement" : message
            )
        }
    }

    // MARK: - Core ML inference

    /// The model accepts a flexible input length, but feeding a whole long
    /// recording as one giant tensor allocates enormous intermediate buffers and
    /// runs as a single multi-minute, un-cancellable inference — which freezes
    /// the app (beach ball) and, past the model's max length, fails outright.
    ///
    /// So we run the model over the signal in bounded, overlapping windows and
    /// crossfade them back together. GTCRN is causal with a short receptive
    /// field, so a ~2 s overlap makes the stitched output indistinguishable from
    /// a single whole-file pass while keeping memory flat and the UI responsive.
    /// Clips that already fit comfortably in one window keep the exact original
    /// single-shot path (no behavioural change for the common short case).

    /// Window of samples fed to the model per inference (6 s at 16 kHz — the
    /// model's tuned default length).
    private static let chunkWindow = 96_000
    /// Overlap between consecutive windows, crossfaded to hide boundaries (2 s).
    /// Wide enough that the stitched output stays ~37 dB below the whole-file
    /// reference — inaudible — while keeping per-inference memory bounded.
    private static let chunkOverlap = 32_000
    /// CoreML minimum accepted input length for this model.
    private static let minChunk = 512

    private static func runModel(_ samples: [Float], resource: String) async throws -> [Float] {
        let model = try loadModel(resource)

        // Short clips: keep the original exact single-shot behaviour.
        if samples.count <= chunkWindow {
            return try predict(samples, with: model)
        }

        let total = samples.count
        let hop = chunkWindow - chunkOverlap
        var output = [Float](repeating: 0, count: total)
        var weight = [Float](repeating: 0, count: total)

        var start = 0
        while start < total {
            try Task.checkCancellation()

            var windowStart = start
            let windowEnd = min(start + chunkWindow, total)
            // Guarantee the model's minimum input length on a tiny final remainder
            // by extending backwards into already-covered (overlapping) samples.
            if windowEnd - windowStart < minChunk {
                windowStart = max(0, windowEnd - minChunk)
            }

            let chunk = Array(samples[windowStart..<windowEnd])
            let enhanced = try predict(chunk, with: model)

            let rampIn = windowStart > 0
            let rampOut = windowEnd < total
            let n = min(enhanced.count, windowEnd - windowStart)
            for i in 0..<n {
                var w: Float = 1
                if rampIn && i < chunkOverlap {
                    w *= Float(i) / Float(chunkOverlap)
                }
                let fromEnd = n - 1 - i
                if rampOut && fromEnd < chunkOverlap {
                    w *= Float(fromEnd) / Float(chunkOverlap)
                }
                let g = windowStart + i
                output[g] += enhanced[i] * w
                weight[g] += w
            }

            if windowEnd >= total { break }
            start += hop
            await Task.yield()
        }

        // Normalise by accumulated crossfade weight (1.0 in non-overlap regions).
        for i in 0..<total where weight[i] > 1e-6 {
            output[i] /= weight[i]
        }
        return output
    }

    private static func loadModel(_ resource: String) throws -> MLModel {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: resource, withExtension: "mlpackage") else {
            throw LouderError.processingFailed("The bundled AI enhancement model is missing")
        }

        let config = MLModelConfiguration()
        // CRITICAL: the recurrent layers mis-compute on the ANE/GPU — only CPU
        // reproduces the reference output. Do not change without re-validating.
        config.computeUnits = .cpuOnly

        return try MLModel(contentsOf: url, configuration: config)
    }

    private static func predict(_ samples: [Float], with model: MLModel) throws -> [Float] {
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first,
              let outputName = model.modelDescription.outputDescriptionsByName.keys.first else {
            throw LouderError.processingFailed("AI enhancement model has no I/O description")
        }

        let count = samples.count
        let array = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .float32)
        samples.withUnsafeBufferPointer { src in
            let dst = array.dataPointer.bindMemory(to: Float.self, capacity: count)
            dst.update(from: src.baseAddress!, count: count)
        }

        let provider = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(multiArray: array)]
        )
        let prediction = try model.prediction(from: provider)
        guard let out = prediction.featureValue(for: outputName)?.multiArrayValue else {
            throw LouderError.processingFailed("AI enhancement model returned no audio")
        }

        let outCount = out.count
        let ptr = out.dataPointer.bindMemory(to: Float.self, capacity: outCount)
        return Array(UnsafeBufferPointer(start: ptr, count: outCount))
    }

    // MARK: - WAV I/O (AVFoundation)

    private static func readMonoFloatSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw LouderError.processingFailed("Could not read audio for AI enhancement")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw LouderError.processingFailed("AI enhancement expected float audio")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func writeMonoFloatSamples(_ samples: [Float], to url: URL, sampleRate: Double) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw LouderError.processingFailed("Could not create audio format for AI enhancement")
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(samples.count)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw LouderError.processingFailed("Could not buffer enhanced audio")
        }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }
}

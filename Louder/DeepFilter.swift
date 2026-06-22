import Foundation

enum DeepFilter {
    private static let modelName = "DeepFilterNet3_onnx"

    static func clean(_ inputURL: URL, outputDirectory: URL) async throws {
        guard let executableURL = executableURL else {
            throw LouderError.deepFilterMissing(
                "The bundled DeepFilterNet executable is missing for this Mac"
            )
        }
        guard let modelURL = Bundle.main.url(
            forResource: modelName,
            withExtension: "tar.gz"
        ) else {
            throw LouderError.deepFilterMissing("The bundled DeepFilterNet model is missing")
        }

        let result = try await run(
            executableURL: executableURL,
            arguments: [
                "-m", modelURL.path,
                "-a", "18",
                "-D",
                "-o", outputDirectory.path,
                inputURL.path
            ]
        )
        guard result.exitCode == 0 else {
            let message = FFmpeg.lastLines(of: result.error, count: 5)
            throw LouderError.deepFilterFailed(
                message.isEmpty ? "DeepFilterNet exited with code \(result.exitCode)" : message
            )
        }
    }

    private static var executableURL: URL? {
        #if arch(arm64)
        let name = "deep-filter-aarch64-apple-darwin"
        #else
        return nil
        #endif

        return Bundle.main.url(
            forResource: name,
            withExtension: nil
        )
    }

    private static func run(
        executableURL: URL,
        arguments: [String]
    ) async throws -> FFmpeg.ToolResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardInput = FileHandle.nullDevice

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    guard box.store(process) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(
                            throwing: LouderError.deepFilterFailed(error.localizedDescription)
                        )
                        return
                    }
                    box.confirmRunning()

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

                    continuation.resume(returning: FFmpeg.ToolResult(
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

    private final class ProcessOutput: @unchecked Sendable {
        var standardOutput = Data()
        var standardError = Data()
    }
}

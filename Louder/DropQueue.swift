import Foundation
import Observation

@MainActor
@Observable
final class DropQueue {
    struct Item: Identifiable {
        enum Status {
            case waiting
            case processing(String)
            case done(String?)
            case failed(String)
        }

        let id = UUID()
        let url: URL
        let preset: ProcessingPreset
        let compare: Bool
        let addFades: Bool
        let trimSilence: Bool
        let renameOriginal: Bool
        let stages: StudioBoothStages
        var status: Status = .waiting
    }

    private(set) var items: [Item] = []
    private(set) var series: [LoudnessSeries] = []
    /// Seconds of silence trimmed per source, keyed by sourceID, for surfacing a note.
    private(set) var trimmedSecondsBySource: [UUID: Double] = [:]
    private(set) var latestTransaction: BatchTransaction?
    private(set) var isUndoing = false
    private(set) var isCancelling = false
    private(set) var undoError: String?
    var compareMode = false
    private var isRunning = false
    private var processingTask: Task<Void, Never>?
    private var transactionOperations: [UndoOperation] = []

    /// Called whenever a batch finishes; receives the number of failed or partial items.
    var onAllDone: ((_ failures: Int) -> Void)?
    var onStateChange: (() -> Void)?
    var onWillBeginBatch: (() -> Void)?
    var onWillUndo: (() -> Void)?

    var isIdle: Bool { !isRunning && !isUndoing && !isCancelling }
    var canUndo: Bool { latestTransaction?.isEmpty == false && isIdle }
    var canCancel: Bool { isRunning && !isCancelling }

    func enqueue(
        _ urls: [URL],
        preset: ProcessingPreset,
        compare: Bool,
        addFades: Bool,
        trimSilence: Bool,
        renameOriginal: Bool,
        stages: StudioBoothStages
    ) {
        if !isRunning {
            onWillBeginBatch?()
            items = []
            series = []
            trimmedSecondsBySource = [:]
            latestTransaction = nil
            transactionOperations = []
            undoError = nil
        }
        onStateChange?()
        items.append(contentsOf: urls.map {
            Item(
                url: $0,
                preset: preset,
                compare: compare,
                addFades: addFades,
                trimSilence: trimSilence,
                renameOriginal: renameOriginal,
                stages: stages
            )
        })
        runIfNeeded()
    }

    /// Removes the comparison artifact files created during a compare run and
    /// resets the queue. Used when the user switches away from Compare so the
    /// generated versions that are no longer shown don't linger on disk.
    func discardComparison() {
        guard isIdle else { return }
        for operation in latestTransaction?.operations ?? transactionOperations {
            if case .delete(let url) = operation {
                try? FileManager.default.removeItem(at: url)
            }
        }
        series = []
        items = []
        latestTransaction = nil
        transactionOperations = []
        undoError = nil
        trimmedSecondsBySource = [:]
        onStateChange?()
    }

    /// Requests cancellation of the in-flight batch. The running tool is
    /// terminated, every artifact this batch produced is removed, any replaced
    /// originals are restored, and the queue returns to the idle/empty state.
    func cancelProcessing() {
        guard canCancel else { return }
        isCancelling = true
        onStateChange?()
        processingTask?.cancel()
    }

    private func rollbackCancelledBatch() {
        // Reverse anything already committed by completed items in this batch.
        try? applyUndo(transactionOperations)
        transactionOperations = []
        latestTransaction = nil
        series = []
        items = []
        undoError = nil
        trimmedSecondsBySource = [:]
    }

    func undoLatestBatch() {
        guard let transaction = latestTransaction, !transaction.isEmpty, isIdle else { return }
        onWillUndo?()
        isUndoing = true
        onStateChange?()
        undoError = nil

        do {
            try preflight(transaction.operations)
            try applyUndo(transaction.operations)
            latestTransaction = nil
            transactionOperations = []
            series = []
            items = []
            trimmedSecondsBySource = [:]
        } catch {
            undoError = error.localizedDescription
        }
        isUndoing = false
        onStateChange?()
    }

    private func preflight(_ operations: [UndoOperation]) throws {
        for operation in operations {
            switch operation {
            case .restore(let originalURL, let backupURL):
                guard FileManager.default.fileExists(atPath: originalURL.path) else {
                    throw LouderError.processingFailed(
                        "Cannot undo because \(originalURL.lastPathComponent) is missing"
                    )
                }
                guard FileManager.default.fileExists(atPath: backupURL.path) else {
                    throw LouderError.processingFailed(
                        "Cannot undo because \(backupURL.lastPathComponent) is missing"
                    )
                }
            case .delete(let url):
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw LouderError.processingFailed(
                        "Cannot undo because \(url.lastPathComponent) is missing"
                    )
                }
            }
        }
    }

    private func applyUndo(_ operations: [UndoOperation]) throws {
        // Comparison artifacts are safe to delete first. Replacements are then restored.
        for operation in operations {
            if case .delete(let url) = operation {
                try FileManager.default.removeItem(at: url)
            }
        }
        for operation in operations {
            if case .restore(let originalURL, let backupURL) = operation {
                try FileManager.default.removeItem(at: originalURL)
                try FileManager.default.moveItem(at: backupURL, to: originalURL)
            }
        }
    }

    private func update(id: UUID, status: Item.Status) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
        onStateChange?()
    }

    private func updateProgress(id: UUID, message: String) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .processing = items[index].status else {
            return
        }
        items[index].status = .processing(message)
        onStateChange?()
    }

    private func runIfNeeded() {
        guard !isRunning else { return }
        isRunning = true
        onStateChange?()
        processingTask = Task {
            while !Task.isCancelled, let next = items.first(where: {
                if case .waiting = $0.status { return true } else { return false }
            }) {
                let id = next.id
                update(id: id, status: .processing("Starting…"))
                do {
                    let result = try await Processor.process(
                        next.url,
                        preset: next.preset,
                        compare: next.compare,
                        addFades: next.addFades,
                        trimSilence: next.trimSilence,
                        renameOriginal: next.renameOriginal,
                        stages: next.stages
                    ) { message in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(id: id, message: message)
                        }
                    }
                    if Task.isCancelled {
                        // Discard this result; rollback removes its artifacts.
                        for operation in result.undoOperations {
                            if case .delete(let url) = operation {
                                try? FileManager.default.removeItem(at: url)
                            }
                        }
                        break
                    }
                    series.append(contentsOf: result.series)
                    if let trimmed = result.trimmedSeconds,
                       let sourceID = result.series.first?.sourceID {
                        trimmedSecondsBySource[sourceID] = trimmed
                    }
                    transactionOperations.append(contentsOf: result.undoOperations)
                    let detail = result.warnings.isEmpty
                        ? nil
                        : result.warnings.joined(separator: "\n")
                    update(id: id, status: .done(detail))
                } catch {
                    if Task.isCancelled { break }
                    update(id: id, status: .failed(error.localizedDescription))
                }
            }

            processingTask = nil
            isRunning = false

            if isCancelling {
                rollbackCancelledBatch()
                isCancelling = false
                onStateChange?()
                return
            }

            latestTransaction = BatchTransaction(operations: transactionOperations)
            onStateChange?()
            let failures = items.filter {
                switch $0.status {
                case .failed: true
                case .done(let detail): detail != nil
                case .waiting, .processing: false
                }
            }.count
            onAllDone?(failures)
        }
    }
}

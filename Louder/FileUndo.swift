import Foundation

/// Pure, side-effect-focused application of `UndoOperation`s. Kept free of any
/// actor isolation or UI state so the data-safety rules (never delete an
/// untouched original, always restore a replaced original, reverse relocations
/// last) can be unit-tested directly against a temporary directory.
enum FileUndo {
    /// Verifies every file an undo will need is present, so the batch either
    /// fully reverses or fails without half-applying.
    static func preflight(_ operations: [UndoOperation]) throws {
        for operation in operations {
            switch operation {
            case .restore(let originalURL, let backupURL):
                try requireExists(originalURL)
                try requireExists(backupURL)
            case .delete(let url):
                try requireExists(url)
            case .relocate(let movedTo, _):
                try requireExists(movedTo)
            case .deleteRelocatedCopy(let url):
                try requireExists(url)
            }
        }
    }

    /// Applies the undo in three ordered passes so operations never clobber one
    /// another:
    /// 1. delete generated artifacts,
    /// 2. restore replaced originals from their backups,
    /// 3. reverse the relocation (Move: return the file to its origin; Copy:
    ///    delete the copy left in the target folder — run last so a Copy's
    ///    just-restored file is removed too).
    static func apply(_ operations: [UndoOperation]) throws {
        for operation in operations {
            if case .delete(let url) = operation {
                try FileManager.default.removeItem(at: url)
            }
        }
        for operation in operations {
            if case .restore(let originalURL, let backupURL) = operation {
                if FileManager.default.fileExists(atPath: originalURL.path) {
                    try FileManager.default.removeItem(at: originalURL)
                }
                try FileManager.default.moveItem(at: backupURL, to: originalURL)
            }
        }
        for operation in operations {
            switch operation {
            case .relocate(let movedTo, let originalURL):
                if FileManager.default.fileExists(atPath: originalURL.path) {
                    try FileManager.default.removeItem(at: originalURL)
                }
                try FileManager.default.moveItem(at: movedTo, to: originalURL)
            case .deleteRelocatedCopy(let url):
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            case .restore, .delete:
                break
            }
        }
    }

    private static func requireExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LouderError.processingFailed(
                "Cannot undo because \(url.lastPathComponent) is missing")
        }
    }
}

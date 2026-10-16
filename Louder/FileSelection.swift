import Foundation

/// Commits one recording's chosen version without scanning or cleaning its folder.
struct FileSelection {
    struct CleanupError: LocalizedError {
        let selectedURL: URL
        let reason: String
        let restorationFailures: [String]

        var errorDescription: String? { "Could not finish picking the file" }
        var recoverySuggestion: String? {
            let recovery = restorationFailures.isEmpty
                ? "Any files moved to Trash have been restored."
                : "Some files could not be restored from Trash:\n" + restorationFailures.joined(separator: "\n")
            return "\(reason)\n\n\(recovery)\n\nYour picked file is still at \(selectedURL.path)."
        }
    }

    let selected: LoudnessSeries
    let discardedURLs: [URL]
    private let sourceURLs: Set<URL>

    init(seriesID: UUID, series: [LoudnessSeries], keepOriginal: Bool) throws {
        guard let selected = series.first(where: { $0.id == seriesID }) else {
            throw LouderError.processingFailed("The selected file is no longer in this batch.")
        }
        self.selected = selected
        let source = series.filter { $0.sourceID == selected.sourceID }
        sourceURLs = Set(source.flatMap { [$0.url.standardizedFileURL, Self.canonicalURL($0.url)] })
        let protectedURLs = Set(series.filter {
            $0.id == selected.id || $0.sourceID != selected.sourceID || (keepOriginal && $0.isOriginal)
        }.map { Self.canonicalURL($0.url) })
        var seen = Set<URL>()
        discardedURLs = source.compactMap {
            let url = $0.url.standardizedFileURL
            guard !protectedURLs.contains(Self.canonicalURL(url)), seen.insert(url).inserted else { return nil }
            return url
        }
    }

    func apply(trash: (URL) throws -> URL = FileSelection.moveToTrash) throws {
        try Self.requireRegularFile(selected.url)
        // Preflight every existing candidate before moving anything. An already
        // removed variant needs no cleanup, but a directory must never be trashed.
        let existing = discardedURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        for url in existing {
            try Self.requireRegularFile(url)
        }
        var moved: [(original: URL, trashed: URL)] = []
        do {
            for url in existing {
                moved.append((url, try trash(url)))
            }
        } catch {
            var failures: [String] = []
            for entry in moved.reversed() {
                do {
                    try FileManager.default.moveItem(at: entry.trashed, to: entry.original)
                } catch {
                    failures.append("\(entry.trashed.path): \(error.localizedDescription)")
                }
            }
            throw CleanupError(
                selectedURL: selected.url,
                reason: error.localizedDescription,
                restorationFailures: failures
            )
        }
    }

    func contains(_ operation: UndoOperation) -> Bool {
        let urls: [URL]
        switch operation {
        case .restore(let originalURL, let backupURL):
            urls = [originalURL, backupURL]
        case .delete(let url), .deleteRelocatedCopy(let url):
            urls = [url]
        case .relocate(let movedTo, let originalURL):
            urls = [movedTo, originalURL]
        }
        return urls.contains {
            sourceURLs.contains($0.standardizedFileURL) || sourceURLs.contains(Self.canonicalURL($0))
        }
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func requireRegularFile(_ url: URL) throws {
        let values = try canonicalURL(url).resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw LouderError.processingFailed("Cannot pick files because \(url.path) is not a regular file.")
        }
    }

    nonisolated private static func moveToTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else {
            throw LouderError.processingFailed("Finder did not return the Trash location for \(url.lastPathComponent).")
        }
        return result as URL
    }
}

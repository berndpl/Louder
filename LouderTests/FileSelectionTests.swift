import XCTest
@testable import Louder

final class FileSelectionTests: XCTestCase {
    private var root: URL!
    private var trash: URL!
    private var sourceID: UUID!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LouderSelectionTests-\(UUID().uuidString)", isDirectory: true)
        trash = root.appendingPathComponent("Trash", isDirectory: true)
        sourceID = UUID()
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testKeepsChosenVersionAndOriginal() throws {
        let original = try version("recording.mov")
        let chosen = try version("recording - Studio.mov", preset: .studioBooth)
        let other = try version("recording - Louder.mov", preset: .gentleBoostDenoise)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen, other], keepOriginal: true)

        try selection.apply(trash: moveToTestTrash)

        XCTAssertTrue(exists(chosen.url))
        XCTAssertTrue(exists(original.url))
        XCTAssertFalse(exists(other.url))
        XCTAssertEqual(try contents(chosen.url), chosen.url.lastPathComponent)
        XCTAssertEqual(try contents(trash.appendingPathComponent(other.url.lastPathComponent)),
                       other.url.lastPathComponent)
    }

    func testDiscardsOriginalWhenToggleIsOff() throws {
        let original = try version("recording - original.mov")
        let chosen = try version("recording.mov", preset: .studioBooth)
        let other = try version("recording - Louder.mov", preset: .gentleBoostDenoise)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen, other], keepOriginal: false)

        try selection.apply(trash: moveToTestTrash)

        XCTAssertTrue(exists(chosen.url))
        XCTAssertFalse(exists(original.url))
        XCTAssertFalse(exists(other.url))
    }

    func testPickingOriginalAlwaysKeepsIt() throws {
        let original = try version("recording.mov")
        let other = try version("recording - Studio.mov", preset: .studioBooth)
        let selection = try FileSelection(
            seriesID: original.id, series: [original, other], keepOriginal: false)

        try selection.apply(trash: moveToTestTrash)

        XCTAssertTrue(exists(original.url))
        XCTAssertFalse(exists(other.url))
    }

    func testOtherRecordingsAndUntrackedFilesAreUntouched() throws {
        let original = try version("recording.mov")
        let chosen = try version("recording - Studio.mov", preset: .studioBooth)
        let unrelated = try version("another.mov", sourceID: UUID())
        let untracked = try version("not-in-this-batch.mov")
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen, unrelated], keepOriginal: false)

        try selection.apply(trash: moveToTestTrash)

        XCTAssertFalse(exists(original.url))
        XCTAssertTrue(exists(chosen.url))
        XCTAssertTrue(exists(unrelated.url))
        XCTAssertTrue(exists(untracked.url))
    }

    func testSharedSelectedPathIsNeverDiscarded() throws {
        let original = try version("recording.mov")
        let chosen = copy(of: original, preset: .untouched)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen], keepOriginal: false)

        XCTAssertTrue(selection.discardedURLs.isEmpty)
        try selection.apply(trash: moveToTestTrash)
        XCTAssertTrue(exists(chosen.url))
    }

    func testSymlinkToProtectedVersionIsNeverDiscarded() throws {
        let original = try version("recording.mov")
        let alias = root.appendingPathComponent("alias.mov")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original.url)
        let chosen = copy(of: original, url: alias, preset: .studioBooth)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen], keepOriginal: false)

        XCTAssertTrue(selection.discardedURLs.isEmpty)
        try selection.apply(trash: moveToTestTrash)
        XCTAssertTrue(exists(original.url))
        XCTAssertTrue(exists(chosen.url))
    }

    func testMissingChosenFileRefusesCleanup() throws {
        let original = try version("recording.mov")
        let chosen = try version("chosen.mov", preset: .studioBooth)
        try FileManager.default.removeItem(at: chosen.url)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen], keepOriginal: false)

        XCTAssertThrowsError(try selection.apply(trash: moveToTestTrash))
        XCTAssertTrue(exists(original.url))
    }

    func testDiscardingSymlinkNeverTrashesItsUntrackedTarget() throws {
        let target = try version("untracked.mov", sourceID: UUID())
        let original = try version("alias.mov")
        try FileManager.default.removeItem(at: original.url)
        try FileManager.default.createSymbolicLink(at: original.url, withDestinationURL: target.url)
        let chosen = try version("chosen.mov", preset: .studioBooth)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen], keepOriginal: false)

        try selection.apply(trash: moveToTestTrash)

        XCTAssertFalse(exists(original.url))
        XCTAssertTrue(exists(target.url))
        XCTAssertTrue(exists(chosen.url))
        XCTAssertEqual(try contents(target.url), target.url.lastPathComponent)
        XCTAssertTrue(selection.contains(.delete(url: original.url)))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: trash.appendingPathComponent(original.url.lastPathComponent).path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    func testMissingDiscardedFileNeedsNoCleanup() throws {
        let original = try version("recording.mov")
        let chosen = try version("chosen.mov", preset: .studioBooth)
        try FileManager.default.removeItem(at: original.url)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen], keepOriginal: false)

        try selection.apply(trash: moveToTestTrash)

        XCTAssertTrue(exists(chosen.url))
    }

    func testDirectoryCandidateRefusesAllCleanup() throws {
        let original = try version("recording.mov")
        let chosen = try version("chosen.mov", preset: .studioBooth)
        let other = try version("other.mov", preset: .gentleBoostDenoise)
        try FileManager.default.removeItem(at: other.url)
        try FileManager.default.createDirectory(at: other.url, withIntermediateDirectories: true)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen, other], keepOriginal: false)

        XCTAssertThrowsError(try selection.apply(trash: moveToTestTrash))
        XCTAssertTrue(exists(original.url))
        XCTAssertTrue(exists(chosen.url))
        XCTAssertTrue(exists(other.url))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testTrashFailureRestoresPreviouslyDiscardedFiles() throws {
        let original = try version("recording.mov")
        let chosen = try version("chosen.mov", preset: .studioBooth)
        let other = try version("other.mov", preset: .gentleBoostDenoise)
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen, other], keepOriginal: false)
        var count = 0

        XCTAssertThrowsError(try selection.apply { url in
            count += 1
            if count == 2 { throw CocoaError(.fileWriteNoPermission) }
            return try self.moveToTestTrash(url)
        }) { error in
            let cleanupError = error as? FileSelection.CleanupError
            XCTAssertNotNil(cleanupError)
            XCTAssertEqual(cleanupError?.restorationFailures, [])
        }
        XCTAssertEqual(count, 2)
        XCTAssertTrue(exists(original.url))
        XCTAssertTrue(exists(chosen.url))
        XCTAssertTrue(exists(other.url))
        XCTAssertEqual(try contents(original.url), original.url.lastPathComponent)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testSelectionOnlyMatchesItsOwnUndoOperations() throws {
        let original = try version("recording - original.mov")
        let chosen = try version("recording.mov", preset: .studioBooth)
        let unrelated = try version("another.mov", sourceID: UUID())
        let selection = try FileSelection(
            seriesID: chosen.id, series: [original, chosen, unrelated], keepOriginal: true)

        XCTAssertTrue(selection.contains(.restore(originalURL: chosen.url, backupURL: original.url)))
        XCTAssertTrue(selection.contains(.delete(url: chosen.url)))
        XCTAssertTrue(selection.contains(.relocate(movedTo: chosen.url, originalURL: root.appendingPathComponent("before.mov"))))
        XCTAssertTrue(selection.contains(.deleteRelocatedCopy(url: chosen.url)))
        XCTAssertFalse(selection.contains(.delete(url: unrelated.url)))
    }

    func testUnknownSelectionIsRejected() {
        XCTAssertThrowsError(try FileSelection(seriesID: UUID(), series: [], keepOriginal: false))
    }

    private func version(
        _ name: String,
        preset: ProcessingPreset? = nil,
        sourceID: UUID? = nil
    ) throws -> LoudnessSeries {
        let url = root.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return LoudnessSeries(
            sourceID: sourceID ?? self.sourceID,
            sourceName: "recording.mov",
            url: url,
            preset: preset,
            metrics: AudioMetrics(
                integratedLUFS: -16, estimatedSNR: nil, snrConfidence: .unavailable, points: [])
        )
    }

    private func copy(of series: LoudnessSeries, url: URL? = nil, preset: ProcessingPreset) -> LoudnessSeries {
        LoudnessSeries(
            sourceID: series.sourceID, sourceName: series.sourceName,
            url: url ?? series.url, preset: preset, metrics: series.metrics)
    }

    private func moveToTestTrash(_ url: URL) throws -> URL {
        let destination = trash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

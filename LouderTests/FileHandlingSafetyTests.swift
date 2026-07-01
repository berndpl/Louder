import XCTest
@testable import Louder

/// Data-safety tests for the file-handling workflow: relocating a recording into
/// a target folder, renaming it, and undoing the result. These files are
/// irreplaceable user artifacts, so the invariants under test are strict:
/// - a Copy never modifies or removes the source;
/// - undo restores the pre-run state exactly (Move returns the file to its
///   origin, Copy removes only the copy);
/// - a replaced original is always recoverable from its backup;
/// - preflight refuses to start an undo that would be incomplete.
final class FileHandlingSafetyTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var target: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LouderTests-\(UUID().uuidString)", isDirectory: true)
        source = root.appendingPathComponent("in", isDirectory: true)
        target = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func makeSource(_ name: String, contents: String = "video-bytes") throws -> URL {
        let url = source.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    private func handling(mode: RelocationMode,
                          rename: Bool = true,
                          body: String = "Interview",
                          appendDate: Bool = false) -> FileHandling {
        FileHandling(
            moveToFolder: true,
            targetFolderPath: target.path,
            relocationMode: mode,
            renameFile: rename,
            renameBody: body,
            appendDate: appendDate
        )
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Relocation naming

    func testRenameBodyAndDate() throws {
        let src = try makeSource("clip.mov")
        // Pin a known recording date so the yyMMdd suffix is deterministic.
        try FileManager.default.setAttributes(
            [.creationDate: date(2026, 7, 1)], ofItemAtPath: src.path)
        let moved = try Processor.relocate(src, using: handling(mode: .copy, appendDate: true))
        XCTAssertEqual(moved.lastPathComponent, "Interview 260701.mov")
    }

    func testBlankBodyFallsBackToSourceName() throws {
        let src = try makeSource("MyClip.mov")
        let moved = try Processor.relocate(src, using: handling(mode: .copy, body: "  "))
        XCTAssertEqual(moved.lastPathComponent, "MyClip.mov")
    }

    func testCollisionAppendsSourceNameThenCounter() throws {
        let a = try makeSource("a.mov")
        let b = try makeSource("b.mov")
        let c = try makeSource("c.mov")
        // Force identical bodies with no date so they collide in the target.
        let h = handling(mode: .copy, body: "Talk", appendDate: false)
        let first = try Processor.relocate(a, using: h)
        let second = try Processor.relocate(b, using: h)
        let third = try Processor.relocate(c, using: h)
        XCTAssertEqual(first.lastPathComponent, "Talk.mov")
        XCTAssertEqual(second.lastPathComponent, "Talk b.mov")
        XCTAssertEqual(third.lastPathComponent, "Talk c.mov")
    }

    // MARK: - Copy never touches the source

    func testCopyPreservesSource() throws {
        let src = try makeSource("clip.mov", contents: "ORIGINAL")
        let moved = try Processor.relocate(src, using: handling(mode: .copy))
        XCTAssertTrue(exists(src), "Copy must leave the source in place")
        XCTAssertEqual(try read(src), "ORIGINAL")
        XCTAssertTrue(exists(moved))
        XCTAssertEqual(try read(moved), "ORIGINAL")
    }

    func testMoveRemovesSource() throws {
        let src = try makeSource("clip.mov", contents: "ORIGINAL")
        let moved = try Processor.relocate(src, using: handling(mode: .move))
        XCTAssertFalse(exists(src), "Move must remove the source from its origin")
        XCTAssertEqual(try read(moved), "ORIGINAL")
    }

    // MARK: - Undo returns to the exact pre-run state

    func testUndoMoveReturnsFileToOrigin() throws {
        let src = try makeSource("clip.mov", contents: "ORIGINAL")
        let moved = try Processor.relocate(src, using: handling(mode: .move))
        // renameOriginal OFF path: the moved file is untouched, a generated
        // sibling is produced; undo deletes the sibling then moves the file back.
        let sibling = target.appendingPathComponent("Interview - clean.mov")
        try "OUTPUT".data(using: .utf8)!.write(to: sibling)

        let ops: [UndoOperation] = [
            .delete(url: sibling),
            .relocate(movedTo: moved, originalURL: src),
        ]
        try FileUndo.preflight(ops)
        try FileUndo.apply(ops)

        XCTAssertFalse(exists(sibling), "Generated output should be removed")
        XCTAssertFalse(exists(moved), "Relocated file should be gone from the target")
        XCTAssertTrue(exists(src), "Original should be back at its origin")
        XCTAssertEqual(try read(src), "ORIGINAL")
    }

    func testUndoCopyDeletesCopyButKeepsSource() throws {
        let src = try makeSource("clip.mov", contents: "ORIGINAL")
        let copy = try Processor.relocate(src, using: handling(mode: .copy))

        let ops: [UndoOperation] = [.deleteRelocatedCopy(url: copy)]
        try FileUndo.preflight(ops)
        try FileUndo.apply(ops)

        XCTAssertFalse(exists(copy), "Copy should be removed on undo")
        XCTAssertTrue(exists(src), "Copy-mode undo must never delete the source")
        XCTAssertEqual(try read(src), "ORIGINAL")
    }

    func testUndoReplacementRestoresOriginalFromBackup() throws {
        // renameOriginal ON: the moved file is backed up, then replaced by the
        // processed version. Undo must recover the untouched original.
        let src = try makeSource("clip.mov", contents: "ORIGINAL")
        let moved = try Processor.relocate(src, using: handling(mode: .move))
        let backup = target.appendingPathComponent("Interview - original.mov")
        try FileManager.default.copyItem(at: moved, to: backup)
        try "PROCESSED".data(using: .utf8)!.write(to: moved) // simulate replacement

        let ops: [UndoOperation] = [
            .restore(originalURL: moved, backupURL: backup),
            .relocate(movedTo: moved, originalURL: src),
        ]
        try FileUndo.preflight(ops)
        try FileUndo.apply(ops)

        XCTAssertFalse(exists(backup), "Backup should be consumed by the restore")
        XCTAssertTrue(exists(src), "Original should be recovered at its origin")
        XCTAssertEqual(try read(src), "ORIGINAL", "Recovered file must be the untouched original")
        XCTAssertFalse(exists(moved), "Nothing should remain in the target after full undo")
    }

    func testCopyReplacementUndoLeavesSourceUntouched() throws {
        // renameOriginal ON + Copy: undo restores the copy from backup, then the
        // deleteRelocatedCopy pass removes it — the source is never involved.
        let src = try makeSource("clip.mov", contents: "ORIGINAL")
        let copy = try Processor.relocate(src, using: handling(mode: .copy))
        let backup = target.appendingPathComponent("Interview - original.mov")
        try FileManager.default.copyItem(at: copy, to: backup)
        try "PROCESSED".data(using: .utf8)!.write(to: copy)

        let ops: [UndoOperation] = [
            .restore(originalURL: copy, backupURL: backup),
            .deleteRelocatedCopy(url: copy),
        ]
        try FileUndo.preflight(ops)
        try FileUndo.apply(ops)

        XCTAssertFalse(exists(copy))
        XCTAssertFalse(exists(backup))
        XCTAssertTrue(exists(src), "Source must survive a Copy + undo intact")
        XCTAssertEqual(try read(src), "ORIGINAL")
    }

    // MARK: - Preflight guards partial undo

    func testPreflightThrowsWhenBackupMissing() throws {
        let missingBackup = target.appendingPathComponent("gone - original.mov")
        let present = try makeSource("present.mov")
        XCTAssertThrowsError(
            try FileUndo.preflight([.restore(originalURL: present, backupURL: missingBackup)]),
            "Undo must refuse to start when a backup is missing, rather than half-apply")
    }

    func testIsRelocationClassification() {
        XCTAssertTrue(UndoOperation.relocate(movedTo: source, originalURL: source).isRelocation)
        XCTAssertTrue(UndoOperation.deleteRelocatedCopy(url: source).isRelocation)
        XCTAssertFalse(UndoOperation.delete(url: source).isRelocation)
        XCTAssertFalse(UndoOperation.restore(originalURL: source, backupURL: source).isRelocation)
    }

    // MARK: - Utilities

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}

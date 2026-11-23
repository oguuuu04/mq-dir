import XCTest
@testable import mqdirCore

final class FileWorkTests: XCTestCase {
    func testCopyInPlaceReportsActualRenamedDestination() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        try Data("original".utf8).write(to: source)
        let result = FileOperationService.perform(FileWorkRequest(kind: .copy, sources: [source], destination: root),
            sources: [source], cancellation: .init())
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.destination?.lastPathComponent, "file 2.txt")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.destination)), Data("original".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSkippedAndFailedAreNotReportedAsSuccessful() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        let child = folder.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let skipped = FileOperationService.transferOutcome(folder, into: child, move: true)
        guard case .skipped = skipped.status else { return XCTFail("Expected explicit skipped result") }
        let missing = root.appendingPathComponent("missing")
        let failed = FileOperationService.transferOutcome(missing, into: folder, move: false)
        XCTAssertTrue(failed.needsRetry)
        XCTAssertNotEqual(failed.status, .succeeded)
    }

    func testExplicitMoveKeepsConflictingFileAndCanBeUndone() throws {
        let root = try fixture()
        let manager = FileManager.default
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        let folder = root.appendingPathComponent("destination")
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        let existing = folder.appendingPathComponent("file.txt")
        try Data("source".utf8).write(to: source)
        try Data("existing".utf8).write(to: existing)

        let outcome = FileOperationService.perform(
            .init(kind: .move, sources: [source], destination: folder), sources: [source], cancellation: .init()
        )
        XCTAssertEqual(outcome.status, .succeeded)
        XCTAssertFalse(manager.fileExists(atPath: source.path))
        XCTAssertEqual(outcome.destination?.lastPathComponent, "file 2.txt")
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        let receipt = try XCTUnwrap(outcome.undoReceipt)
        try receipt.apply(cancellation: .init())
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertFalse(manager.fileExists(atPath: receipt.current.path))
    }

    func testExplicitMoveToSameFolderThroughSymlinkSkipsAndMissingSourceFails() throws {
        let root = try fixture()
        let manager = FileManager.default
        defer { try? manager.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        let alias = root.appendingPathComponent("alias")
        try manager.createSymbolicLink(at: alias, withDestinationURL: folder)
        let source = folder.appendingPathComponent("file.txt")
        try Data("source".utf8).write(to: source)
        let request = FileWorkRequest(kind: .move, sources: [source], destination: alias)
        let result = FileOperationService.perform(request, sources: [source], cancellation: .init())
        XCTAssertEqual(result.status, .skipped("Already in this folder"))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: folder.path), ["file.txt"])
        try manager.removeItem(at: source)
        let missing = FileOperationService.perform(request, sources: [source], cancellation: .init())
        XCTAssertTrue(missing.needsRetry)
    }

    func testExplicitMoveToInvalidDestinationLeavesSourceIntact() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: source)
        let invalid = root.appendingPathComponent("missing").appendingPathComponent("destination")
        let outcome = FileOperationService.perform(
            .init(kind: .move, sources: [source], destination: invalid), sources: [source], cancellation: .init()
        )
        XCTAssertTrue(outcome.needsRetry)
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }

    func testExplicitMoveAcrossVolumes() throws {
        guard let path = ProcessInfo.processInfo.environment["MQDIR_TEST_OTHER_VOLUME"] else {
            throw XCTSkip("Set MQDIR_TEST_OTHER_VOLUME to a writable disposable volume")
        }
        let root = try fixture()
        let manager = FileManager.default
        defer { try? manager.removeItem(at: root) }
        let volume = URL(fileURLWithPath: path, isDirectory: true)
        let folder = volume.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: folder) }
        let sourceVolume = try XCTUnwrap(root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? AnyHashable)
        let destinationVolume = try XCTUnwrap(folder.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? AnyHashable)
        XCTAssertNotEqual(sourceVolume, destinationVolume)

        let source = root.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: source)
        let outcome = FileOperationService.perform(
            .init(kind: .move, sources: [source], destination: folder), sources: [source], cancellation: .init()
        )
        XCTAssertEqual(outcome.status, .succeeded)
        XCTAssertFalse(manager.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(outcome.destination)), Data("source".utf8))
    }

    func testChangeScopeExcludesUnrelatedFolders() {
        let root = URL(fileURLWithPath: "/fixture/project")
        XCTAssertFalse(FileChangeScope.affects(root: root, changedFolders: [URL(fileURLWithPath: "/fixture/other")], recursive: true))
        XCTAssertFalse(FileChangeScope.affects(root: root, changedFolders: [URL(fileURLWithPath: "/fixture/project/deep/nested")], recursive: false))
        XCTAssertTrue(FileChangeScope.affects(root: root, changedFolders: [URL(fileURLWithPath: "/fixture/project/deep/nested")], recursive: true))
        XCTAssertTrue(FileChangeScope.affects(root: root, changedFolders: nil, recursive: false))
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

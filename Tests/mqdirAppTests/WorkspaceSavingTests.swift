import XCTest

final class WorkspaceSavingTests: XCTestCase {
    @MainActor
    func testUnresolvedBookmarkAndSelectionStayInSnapshot() {
        let original = TabState(folderBookmark: Data([1, 2, 3]), selectedURLPaths: ["/unavailable/file"])
        let tab = FolderBrowserViewModel(state: original)
        XCTAssertNil(tab.folderURL)
        XCTAssertEqual(tab.tabSnapshot().folderBookmark, original.folderBookmark)
        XCTAssertEqual(tab.tabSnapshot().selectedURLPaths, original.selectedURLPaths)
    }

    @MainActor
    func testWindowSnapshotsSurviveSwitchingAndReloadWithoutOverwritingSharedSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try PersistenceService(stateURL: root.appendingPathComponent("state.json"))
        var first = Project(name: "first")
        first.state.layout = .three
        let second = Project(name: "second")
        let initial = WorkspaceState(favoritesSeeded: true, activeProjectID: first.id, projects: [first, second])
        try service.saveState(initial)
        let original = try Data(contentsOf: service.fileURL)
        let manager = WorkspaceManager(persistence: service)
        let a = manager.attachWindow(UUID())
        let b = manager.attachWindow(UUID())
        XCTAssertEqual(manager.snapshot(windowID: a, projectID: first.id), first.state)
        var aState = first.state
        aState.layout = .one
        var bState = first.state
        bState.layout = .twoH
        manager.saveSnapshot(aState, windowID: a, projectID: first.id)
        manager.setColorScheme(.dark)
        manager.saveSnapshot(bState, windowID: b, projectID: first.id)
        manager.switchTo(projectID: second.id, in: a)
        XCTAssertEqual(manager.session(b)?.projectID, first.id)
        manager.saveSynchronously()

        let restored = WorkspaceManager(persistence: service)
        XCTAssertEqual(restored.initialWindowID, a)
        XCTAssertEqual(restored.takeRestorationIDs(excluding: a), [b])
        XCTAssertEqual(restored.takeRestorationIDs(excluding: a), [])
        XCTAssertEqual(restored.initialWindowID, a)
        XCTAssertEqual(restored.session(a)?.projectID, second.id)
        XCTAssertEqual(restored.session(b)?.projectID, first.id)
        restored.switchTo(projectID: first.id, in: a)
        XCTAssertEqual(restored.snapshot(windowID: a, projectID: first.id), aState)
        XCTAssertEqual(restored.snapshot(windowID: b, projectID: first.id), bState)
        XCTAssertEqual(restored.workspace.settings.colorScheme, .dark)
        XCTAssertEqual(restored.workspace.projects, initial.projects)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("state.before-window-sessions.json")), original)
    }

    @MainActor
    func testDeletingProjectRepairsBothWindowsAndClosingDoesNotResurrectSession() {
        let first = Project(name: "first")
        let second = Project(name: "second")
        let state = WorkspaceState(favoritesSeeded: true, activeProjectID: first.id, projects: [first, second])
        let manager = WorkspaceManager(persistence: nil, initialState: state)
        let a = manager.attachWindow(UUID())
        let b = manager.attachWindow(UUID())
        manager.saveSnapshot(.empty, windowID: b, projectID: first.id)
        manager.delete(first.id)
        XCTAssertEqual(manager.session(a)?.projectID, second.id)
        XCTAssertEqual(manager.session(b)?.projectID, second.id)
        XCTAssertNil(manager.session(b)?.snapshots[first.id.uuidString])
        manager.delete(second.id)
        XCTAssertEqual(manager.workspace.projects, [second])
        manager.closeWindow(a)
        manager.saveSnapshot(.empty, windowID: a, projectID: second.id)
        XCTAssertNil(manager.session(a))
        let restarted = WorkspaceManager(persistence: nil, initialState: manager.workspace)
        XCTAssertEqual(restarted.initialWindowID, b)
        XCTAssertEqual(restarted.takeRestorationIDs(excluding: b), [])
    }

    @MainActor
    func testDuplicateUsesOriginatingWindowsSnapshotAndSharedFavoritesStayCurrent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Project(name: "Research")
        let state = WorkspaceState(favoritesSeeded: true, activeProjectID: original.id, projects: [original])
        let manager = WorkspaceManager(persistence: nil, initialState: state)
        let a = manager.attachWindow(UUID())
        let b = manager.attachWindow(UUID())
        var snapshot = WindowState.empty
        snapshot.layout = .three
        manager.saveSnapshot(snapshot, windowID: a, projectID: original.id)
        manager.duplicateProject(original.id, in: a)
        let copy = try XCTUnwrap(manager.workspace.projects.last)
        XCTAssertEqual(copy.name, "Research Copy")
        XCTAssertEqual(copy.state, snapshot)
        XCTAssertEqual(manager.session(a)?.projectID, copy.id)
        XCTAssertEqual(manager.session(b)?.projectID, original.id)
        manager.sidebar.add(url: root)
        manager.saveSnapshot(.empty, windowID: b, projectID: original.id)
        XCTAssertEqual(manager.workspace.favorites.map(\.fallbackPath), [root.path])
    }
}

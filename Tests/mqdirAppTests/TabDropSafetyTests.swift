import AppKit
import UniformTypeIdentifiers
import XCTest

final class TabDropSafetyTests: XCTestCase {
    @MainActor
    func testTabCannotBecomeFileJobButCanBecomeFavorite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let origin = root.appendingPathComponent("origin", isDirectory: true)
        let target = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try XCTUnwrap(DragDropSupport.tabPasteboardItem(.init(token: UUID(), folderURL: origin)))
        let type = DragDropSupport.tabTypeIdentifier
        XCTAssertEqual(item.types.map(\.rawValue), [type])
        let data = try XCTUnwrap(item.data(forType: .init(type)))
        let tab = NSItemProvider()
        tab.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        XCTAssertFalse(tab.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertFalse(tab.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))

        let ordinary = NSItemProvider(object: origin as NSURL)
        let normalURLs = await DragDropSupport.resolveFileDropURLs(from: [ordinary])
        XCTAssertEqual(normalURLs.map(\.path), [origin.path])
        for providers in [[tab], [tab, ordinary]] {
            let urls = await DragDropSupport.resolveFileDropURLs(from: providers)
            XCTAssertTrue(urls.isEmpty)
            let browser = FolderBrowserViewModel(watchingDirectories: false)
            let before = FileWorkCenter.shared.jobs.count
            browser.acceptDrop(urls, into: target, copy: false)
            XCTAssertEqual(FileWorkCenter.shared.jobs.count, before)
        }
        let favorites = SidebarViewModel(favorites: [])
        for url in await DragDropSupport.resolveFavoriteURLs(from: [tab]) {
            favorites.add(url: url)
        }
        XCTAssertEqual(favorites.favorites.map(\.fallbackPath), [origin.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: origin.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])

        let ordinaryDrop = FileWorkRequest(kind: .drop, sources: normalURLs, destination: target, forceCopy: true)
        let result = FileOperationService.perform(ordinaryDrop, sources: normalURLs, cancellation: .init())
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: origin.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("origin").path))
    }

    @MainActor
    func testTabTokenIsWindowScopedAndSingleUse() async throws {
        let source = PaneTabsViewModel(state: .init(tabs: [TabState(), TabState(), TabState()], activeTabIndex: 1))
        let destination = PaneTabsViewModel(state: .init())
        let otherWindow = PaneTabsViewModel(state: .init())
        let a = TabDragCoordinator()
        let b = TabDragCoordinator()
        a.register(panes: [source, destination])
        b.register(panes: [otherWindow])
        let first = source.tabs[0]
        let active = source.activeTab
        let moved = source.tabs[2]
        let other = otherWindow.activeTab

        let foreign = b.begin(sourcePaneIndex: 0, tabID: ObjectIdentifier(other), folderURL: nil)
        let payload = a.begin(sourcePaneIndex: 0, tabID: ObjectIdentifier(moved), folderURL: nil)
        let foreignRequest = try XCTUnwrap(b.requestDrop())
        XCTAssertFalse(b.completeDrop(payload, expectedToken: foreignRequest, into: 0, at: 1))
        b.end(token: foreign.token, operation: [])
        XCTAssertNil(b.sourceTabID)
        XCTAssertEqual(otherWindow.tabs.count, 1)
        XCTAssertTrue(otherWindow.activeTab === other)
        let reorder = try XCTUnwrap(a.requestDrop())
        XCTAssertTrue(a.completeDrop(payload, expectedToken: reorder, into: 0, at: 0))
        XCTAssertNil(a.sourceTabID)
        XCTAssertTrue(source.tabs[0] === moved)
        XCTAssertTrue(source.tabs[1] === first)
        XCTAssertTrue(source.activeTab === active)

        let move = a.begin(sourcePaneIndex: 0, tabID: ObjectIdentifier(moved), folderURL: nil)
        let request = try XCTUnwrap(a.requestDrop())
        a.end(token: move.token, operation: .move)
        XCTAssertNil(a.sourceTabID)
        XCTAssertTrue(a.completeDrop(move, expectedToken: request, into: 1, at: 1))
        XCTAssertFalse(a.completeDrop(move, expectedToken: request, into: 1, at: 1))
        XCTAssertFalse(source.tabs.contains { $0 === moved })
        XCTAssertEqual(destination.tabs.count, 2)
        XCTAssertTrue(destination.activeTab === moved)
    }

    @MainActor
    func testCancelledOrRejectedDragClearsStateAndCannotMoveTab() throws {
        let pane = PaneTabsViewModel(state: .init())
        let coordinator = TabDragCoordinator()
        coordinator.register(panes: [pane])
        let tab = ObjectIdentifier(pane.activeTab)

        let cancelled = coordinator.begin(sourcePaneIndex: 0, tabID: tab, folderURL: nil)
        coordinator.end(token: cancelled.token, operation: [])
        XCTAssertNil(coordinator.sourceTabID)
        XCTAssertNil(coordinator.requestDrop())

        let rejected = coordinator.begin(sourcePaneIndex: 0, tabID: tab, folderURL: nil)
        let request = try XCTUnwrap(coordinator.requestDrop())
        coordinator.end(token: rejected.token, operation: [])
        XCTAssertNil(coordinator.sourceTabID)
        XCTAssertFalse(coordinator.completeDrop(rejected, expectedToken: request, into: 0, at: 1))
        XCTAssertEqual(pane.tabs.map(ObjectIdentifier.init), [tab])
    }

    @MainActor
    func testEndingOldDragDoesNotClearNewDragOrAllowItsPendingDrop() throws {
        let pane = PaneTabsViewModel(state: .init())
        let coordinator = TabDragCoordinator()
        coordinator.register(panes: [pane])
        let tab = ObjectIdentifier(pane.activeTab)
        let first = coordinator.begin(sourcePaneIndex: 0, tabID: tab, folderURL: nil)
        let oldRequest = try XCTUnwrap(coordinator.requestDrop())
        let second = coordinator.begin(sourcePaneIndex: 0, tabID: tab, folderURL: nil)
        coordinator.end(token: first.token, operation: .move)
        XCTAssertEqual(coordinator.sourceTabID, tab)
        XCTAssertFalse(coordinator.completeDrop(first, expectedToken: oldRequest, into: 0, at: 1))
        XCTAssertEqual(coordinator.requestDrop(), second.token)
        coordinator.end(token: second.token, operation: [])
        XCTAssertNil(coordinator.sourceTabID)
    }
}

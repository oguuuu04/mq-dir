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
        let tab = DragDropSupport.tabProvider(token: UUID(), folderURL: origin)
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

        _ = b.begin(sourcePaneIndex: 0, tabID: ObjectIdentifier(other), folderURL: nil)
        let reorder = a.begin(sourcePaneIndex: 0, tabID: ObjectIdentifier(moved), folderURL: nil)
        let firstPayload = await DragDropSupport.tabPayload(from: reorder)
        let payload = try XCTUnwrap(firstPayload)
        XCTAssertFalse(b.drop(payload, into: 0, at: 1))
        XCTAssertEqual(otherWindow.tabs.count, 1)
        XCTAssertTrue(otherWindow.activeTab === other)
        XCTAssertTrue(a.drop(payload, into: 0, at: 0))
        XCTAssertTrue(source.tabs[0] === moved)
        XCTAssertTrue(source.tabs[1] === first)
        XCTAssertTrue(source.activeTab === active)

        let move = a.begin(sourcePaneIndex: 0, tabID: ObjectIdentifier(moved), folderURL: nil)
        let secondPayload = await DragDropSupport.tabPayload(from: move)
        let movePayload = try XCTUnwrap(secondPayload)
        XCTAssertFalse(a.drop(payload, into: 1, at: 1))
        XCTAssertTrue(a.drop(movePayload, into: 1, at: 1))
        XCTAssertFalse(a.drop(movePayload, into: 1, at: 1))
        XCTAssertFalse(source.tabs.contains { $0 === moved })
        XCTAssertEqual(destination.tabs.count, 2)
        XCTAssertTrue(destination.activeTab === moved)
    }
}

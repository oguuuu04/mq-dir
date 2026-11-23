import AppKit
import Combine
import Foundation

/// Tracks tab reordering between the live panes of one browser window.
@MainActor
final class TabDragCoordinator: ObservableObject {
    private var allPanes: [PaneTabsViewModel] = []
    /// Published so each `BrowserPaneView` can observe the
    /// drag-in-flight state and clear its insertion-marker preview the
    /// instant the drag ends. The `setPreview`-via-Binding path inside
    /// the drop delegate isn't always enough — SwiftUI sometimes
    /// processes a sibling drop zone's dropEntered AFTER performDrop
    /// returns, re-setting the preview. Observing this gives every
    /// pane a single source-of-truth signal.
    private var sourcePaneIndex: Int?
    private var token: UUID?
    @Published private(set) var sourceTabID: ObjectIdentifier?

    func register(panes: [PaneTabsViewModel]) {
        self.allPanes = panes
    }

    func begin(sourcePaneIndex: Int, tabID: ObjectIdentifier, folderURL: URL?) -> NSItemProvider {
        let token = UUID()
        self.token = token
        self.sourcePaneIndex = sourcePaneIndex
        self.sourceTabID = tabID
        return DragDropSupport.tabProvider(token: token, folderURL: folderURL)
    }

    func clear() {
        token = nil
        sourcePaneIndex = nil
        sourceTabID = nil
    }

    /// Authenticate against the active drag, not merely a stale source pane.
    @discardableResult
    func drop(_ payload: DragDropSupport.TabPayload, into targetPaneIndex: Int, at tabIndex: Int) -> Bool {
        guard token == payload.token,
              let source = sourcePaneIndex,
              let tabID = sourceTabID,
              allPanes.indices.contains(source),
              allPanes.indices.contains(targetPaneIndex)
        else { return false }

        defer { clear() }
        let origin = allPanes[source]
        if source == targetPaneIndex {
            guard let from = origin.tabs.firstIndex(where: { ObjectIdentifier($0) == tabID }) else { return false }
            origin.move(from: from, to: tabIndex)
        } else {
            guard let detached = origin.detachTab(id: tabID) else { return false }
            allPanes[targetPaneIndex].attachTab(detached, at: tabIndex)
        }
        return true
    }
}

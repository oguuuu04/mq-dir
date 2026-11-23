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
    @Published private(set) var sourcePaneIndex: Int?
    @Published private(set) var sourceTabID: ObjectIdentifier?

    func register(panes: [PaneTabsViewModel]) {
        self.allPanes = panes
    }

    func begin(sourcePaneIndex: Int, tabID: ObjectIdentifier) {
        self.sourcePaneIndex = sourcePaneIndex
        self.sourceTabID = tabID
    }

    func clear() {
        sourcePaneIndex = nil
        sourceTabID = nil
    }

    /// Detach the dragging tab from its source pane and insert it into
    /// `targetPaneIndex` at `tabIndex`. Returns true on success. Updates
    /// `sourcePaneIndex` to the destination so a subsequent reorder
    /// inside the destination pane works correctly during the same
    /// drag session.
    @discardableResult
    func moveTab(toPaneIndex targetPaneIndex: Int, atTabIndex tabIndex: Int) -> Bool {
        guard let source = sourcePaneIndex,
              let tabID = sourceTabID,
              source != targetPaneIndex,
              allPanes.indices.contains(source),
              allPanes.indices.contains(targetPaneIndex)
        else { return false }

        guard let detached = allPanes[source].detachTab(id: tabID) else { return false }
        allPanes[targetPaneIndex].attachTab(detached, at: tabIndex)
        sourcePaneIndex = targetPaneIndex
        return true
    }
}

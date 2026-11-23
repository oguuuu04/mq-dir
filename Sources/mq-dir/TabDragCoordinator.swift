import AppKit
import Combine

/// Tracks tab reordering between the live panes of one browser window.
@MainActor
final class TabDragCoordinator: ObservableObject {
    private struct Drag {
        let token: UUID
        let paneIndex: Int
        let tabID: ObjectIdentifier
    }

    private var panes: [PaneTabsViewModel] = []
    private var active: Drag?
    private var requestedDrop: UUID?
    // AppKit may end an accepted drag before the drop provider calls back.
    // Keep only that in-flight drop's data, separate from visible drag state.
    private var pendingDrop: Drag?
    @Published private(set) var sourceTabID: ObjectIdentifier?

    func register(panes: [PaneTabsViewModel]) {
        self.panes = panes
    }

    func begin(sourcePaneIndex: Int, tabID: ObjectIdentifier, folderURL: URL?) -> DragDropSupport.TabPayload {
        let token = UUID()
        pendingDrop = nil
        requestedDrop = nil
        active = Drag(token: token, paneIndex: sourcePaneIndex, tabID: tabID)
        sourceTabID = tabID
        return .init(token: token, folderURL: folderURL)
    }

    func requestDrop() -> UUID? {
        guard let active, requestedDrop == nil else { return nil }
        requestedDrop = active.token
        return active.token
    }

    func end(token: UUID, operation: NSDragOperation) {
        guard let drag = active, drag.token == token else { return }
        if !operation.isEmpty, requestedDrop == token { pendingDrop = drag }
        active = nil
        requestedDrop = nil
        sourceTabID = nil
    }

    @discardableResult
    func completeDrop(
        _ payload: DragDropSupport.TabPayload?, expectedToken: UUID,
        into targetPaneIndex: Int, at tabIndex: Int
    ) -> Bool {
        let drag: Drag
        if let active, active.token == expectedToken, requestedDrop == expectedToken {
            drag = active
            end(token: expectedToken, operation: [])
        } else if let pendingDrop, pendingDrop.token == expectedToken {
            drag = pendingDrop
            self.pendingDrop = nil
        } else {
            return false
        }

        guard payload?.token == expectedToken,
              panes.indices.contains(drag.paneIndex), panes.indices.contains(targetPaneIndex)
        else { return false }

        let origin = panes[drag.paneIndex]
        if drag.paneIndex == targetPaneIndex {
            guard let from = origin.tabs.firstIndex(where: { ObjectIdentifier($0) == drag.tabID }) else { return false }
            origin.move(from: from, to: tabIndex)
        } else {
            guard let detached = origin.detachTab(id: drag.tabID) else { return false }
            panes[targetPaneIndex].attachTab(detached, at: tabIndex)
        }
        return true
    }
}

/// Owns the AppKit source callback for the lifetime of each native drag.
@MainActor
final class AppKitTabDragSource: NSObject, NSDraggingSource {
    static let shared = AppKitTabDragSource()
    private var completions: [Int: (NSDragOperation) -> Void] = [:]

    func start(
        on view: NSView, event: NSEvent, item: NSDraggingItem,
        completion: @escaping (NSDragOperation) -> Void
    ) {
        let session = view.beginDraggingSession(with: [item], event: event, source: self)
        completions[session.draggingSequenceNumber] = completion
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        completions.removeValue(forKey: session.draggingSequenceNumber)?(operation)
    }
}

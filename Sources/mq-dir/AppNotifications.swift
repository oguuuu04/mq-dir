import Foundation

import Combine

/// A menu command addressed to a single browser window.
enum AppCommand: Equatable {
    // MARK: File menu / navigation (handled by NavigationNotifications)
    case openFolder
    case openSelected
    case newFolder
    case revealSelected
    case reload
    case parentFolder
    case toggleHiddenFiles
    case goBack
    case goForward
    case focusSearch
    /// Add the focused pane's current folder to the sidebar Favorites list.
    case addCurrentFolderToFavorites
    /// Toggle the right-side preview panel for the focused pane's active tab.
    case togglePreview
    /// View → As List / As Tree.
    case setViewModeList
    case setViewModeTree

    // MARK: Edit menu — pasteboard / selection (EditMenuNotifications)
    case selectAll
    case copy
    case paste
    case movePasteboardItems
    case delete
    /// Edit → Delete Immediately (⌘⌥⌫) — destructive NSAlert, bypasses trash.
    case permanentDelete

    // MARK: Edit menu — file-selection actions (EditFileActionsNotifications)
    case openWithDefaultApp
    case duplicate
    case copyFilePaths
    /// Copies the *current folder* path (not the selection).
    case copyFolderPath
    case copyName
    case rename

    // MARK: Tabs in the focused pane (TabNotifications)
    case newTab
    case closeTab
    case reopenClosedTab
    case nextTab
    case previousTab
    /// Posted by ⌘1…⌘9. Payload is the zero-based tab index; the focused
    /// pane silently ignores out-of-range values.
    case selectTab(index: Int)
    // MARK: Pane focus (PaneFocusNotifications)
    /// Posted by Window → Focus Pane N (⌥⌘1–4). Payload is the zero-based
    /// pane index; receivers ignore values outside the active layout's
    /// pane count.
    case focusPane(index: Int)

}

/// Each browser window owns a separate command stream. The menu obtains the
/// stream from the focused SwiftUI scene; other windows never subscribe to it.
@MainActor
final class BrowserWindowCommands {
    private let subject = PassthroughSubject<AppCommand, Never>()

    var publisher: AnyPublisher<AppCommand, Never> {
        subject.eraseToAnyPublisher()
    }

    func send(_ command: AppCommand) {
        subject.send(command)
    }
}

extension Notification.Name {
    // MARK: - Non-command notifications (deliberately NOT folded into AppCommand)
    //
    // These are broadcast/lifecycle events, not menu→focused-pane commands,
    // so they keep their own dedicated names:
    //
    // • `mqdirFileSystemChanged` — a fan-OUT broadcast: every open tab in
    //   every pane reloads. Posted from AppKit drag/drop bridges and the
    //   VM's own file-operation paths, not from the menu. Not a "focused
    //   pane, do X" command.
    // • `mqdirAppWillTerminate` — app-lifecycle flush posted by `mqdirApp`
    //   from the OS termination hook, not a user action.

    /// FSEvents lands later; until then drag/drop + file ops post this and
    /// every open tab refetches its folder.
    static let mqdirFileSystemChanged = Notification.Name("mqdir.fileSystemChanged")
    /// Posted by `mqdirApp` when the OS notifies us of imminent termination,
    /// so the active window can flush a synchronous save before exit.
    static let mqdirAppWillTerminate = Notification.Name("mqdir.appWillTerminate")
}

/// Scoped change notifications; legacy senders without folders still refresh all.
enum FileSystemChange {
    static func post(folders: [URL]) {
        NotificationCenter.default.post(name: .mqdirFileSystemChanged, object: nil,
            userInfo: ["folders": Array(Set(folders))])
    }

    static func folders(in notification: Notification) -> [URL]? {
        notification.userInfo?["folders"] as? [URL]
    }
}

@MainActor
enum ExternalFolderRequests {
    private static var pending: [URL] = []
    static let changed = Notification.Name("mqdir.externalFolderRequests")
    static func enqueue(_ urls: [URL]) {
        pending.append(contentsOf: urls.filter(\.isFileURL))
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static func consume() -> [URL] {
        defer { pending.removeAll() }
        return pending
    }
}

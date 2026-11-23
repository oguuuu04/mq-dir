import AppKit
import SwiftUI

@main
struct mqdirApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceManager()
    @StateObject private var repoCallout = RepoCalloutController()

    init() {
        // Forward NSApplication's willTerminate to our internal notification
        // so MainWindowView can flush a synchronous save before exit.
        // Doing this in App.init keeps the wiring close to the lifecycle
        // that depends on it, and avoids touching AppDelegate's existing
        // M0-era responsibilities.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .mqdirAppWillTerminate, object: nil)
        }
    }

    var body: some Scene {
        browserScene

        // Standard macOS Preferences window (⌘,). Phase 3 ships the
        // appearance picker; future settings — keyboard customizer,
        // archive handler — will land as additional Form sections.
        Settings {
            SettingsView(workspace: workspace)
                .preferredColorScheme(workspace.workspace.settings.colorScheme.preferred)
        }
    }

    private var browserScene: some Scene {
        WindowGroup("File Manager", id: "browser", for: UUID.self) { $windowID in
            BrowserWindowScene(workspace: workspace, repoCallout: repoCallout, windowID: windowID)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(workspace.workspace.settings.colorScheme.preferred)
        } defaultValue: {
            workspace.initialWindowID
        }
        .windowResizability(.contentMinSize)
        .commands {
            MenuCommands(workspace: workspace)
        }
    }

}

/// This root survives a Workspace switch. Its SwiftUI scene value identifies
/// the window across restarts; the child is keyed only by its selected project.
struct BrowserWindowScene: View {
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var repoCallout: RepoCalloutController
    let windowID: UUID
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let session = workspace.session(windowID) {
                MainWindowView(workspace: workspace, repoCallout: repoCallout,
                               windowID: windowID, projectID: session.projectID)
                    .id(session.projectID)
                    .environmentObject(workspace)
            } else {
                Color.clear
            }
        }
        .background(WindowCloseObserver {
            if !AppDelegate.isQuitting { workspace.closeWindow(windowID) }
        })
        .task(id: windowID) {
            // macOS can replay an old scene value after an upgrade. Do
            // not recreate a session absent from the saved window list.
            guard windowID == workspace.initialWindowID || workspace.session(windowID) != nil else {
                openWindow(id: "browser", value: workspace.initialWindowID)
                dismissWindow(id: "browser", value: windowID)
                return
            }
            workspace.attachWindow(windowID)
            for id in workspace.takeRestorationIDs(excluding: windowID) {
                openWindow(id: "browser", value: id)
            }
        }
    }
}

/// Observe actual NSWindow closes, not SwiftUI view disappearance during a
/// project change or scene update.
private struct WindowCloseObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { view.onClose = onClose }

    final class ObserverView: NSView {
        var onClose: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            if let window {
                window.isRestorable = false
                NotificationCenter.default.addObserver(self, selector: #selector(willClose(_:)),
                                                       name: NSWindow.willCloseNotification, object: window)
            }
        }

        @objc private func willClose(_ notification: Notification) { onClose?() }
    }
}

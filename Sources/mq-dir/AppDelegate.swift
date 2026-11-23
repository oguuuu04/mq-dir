import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var isQuitting = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.isQuitting = true
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up PDF-preview temp dirs orphaned by a crash or
        // force-quit in a previous run (normal teardown removes them
        // in `cleanupPDFTemp`, but nothing else reclaims strays).
        Task.detached(priority: .background) {
            ZipPreviewService.sweepLeftoverTempDirs()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        ExternalFolderRequests.enqueue(urls)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

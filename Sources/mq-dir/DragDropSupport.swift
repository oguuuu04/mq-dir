import AppKit
import Foundation
import UniformTypeIdentifiers

// Drag/drop pasteboard plumbing for mq-dir.
//
// External drags (mq-dir → Finder/Terminal/etc.) carry a single primary URL
// via the standard `public.file-url` type. Internal drags carry an extra
// `com.mqdir.selection.urls` representation containing the *full* selection,
// so that pane-to-pane drops can move every selected item even though
// SwiftUI's `.draggable` only ships one item at a time.

@MainActor
enum DragDropSupport {
    nonisolated static let mqdirSelectionTypeIdentifier = "com.mqdir.selection.urls"

    nonisolated static let tabTypeIdentifier = "com.oguuuu04.filemanager.browser-tab"

    struct TabPayload: Codable, Sendable {
        let token: UUID
        let folderURL: URL?
    }

    static func tabPasteboardItem(_ payload: TabPayload) -> NSPasteboardItem? {
        let item = NSPasteboardItem()
        guard let data = try? JSONEncoder().encode(payload),
              item.setData(data, forType: .init(tabTypeIdentifier)) else { return nil }
        return item
    }

    static func tabPayload(from provider: NSItemProvider) async -> TabPayload? {
        await withCheckedContinuation { continuation in
            loadTabPayload(from: provider) { continuation.resume(returning: $0) }
        }
    }

    static func loadTabPayload(from provider: NSItemProvider, completion: @escaping @Sendable (TabPayload?) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: tabTypeIdentifier) { data, _ in
            completion(data.flatMap { try? JSONDecoder().decode(TabPayload.self, from: $0) })
        }
    }

    static func containsTab(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.registeredTypeIdentifiers.contains(tabTypeIdentifier) }
    }

    /// A mixed provider must never reach the filesystem drop path.
    static func resolveFileDropURLs(from providers: [NSItemProvider]) async -> [URL] {
        guard !containsTab(providers) else { return [] }
        return await resolveURLs(from: providers)
    }

    static func resolveFavoriteURLs(from providers: [NSItemProvider]) async -> [URL] {
        if !containsTab(providers) { return await resolveURLs(from: providers) }
        var urls: [URL] = []
        for provider in providers where containsTab([provider]) {
            if let url = await tabPayload(from: provider)?.folderURL, url.isFileURL {
                urls.append(url)
            }
        }
        return urls
    }

    // Drag-source construction lives in `AppKitFileDrag.swift` — we drive
    // NSDraggingSession directly with an NSPasteboardItem because
    // SwiftUI's `.onDrag` layers a promise on top of any NSItemProvider
    // we hand it, so receivers that read via `loadFileRepresentation`
    // (WebKit / cmux / browsers) end up with a cache copy instead of
    // the original path.

    /// Resolve an array of incoming NSItemProviders to file URLs. Prefers our
    /// private multi-selection type when present; otherwise falls back to the
    /// standard `public.file-url`.
    private static func resolveURLs(from providers: [NSItemProvider]) async -> [URL] {
        var resolved: [URL] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(mqdirSelectionTypeIdentifier),
               let multi = await loadMultiSelection(from: provider) {
                resolved.append(contentsOf: multi)
                continue
            }
            if let url = await loadFileURL(from: provider) {
                resolved.append(url)
            }
        }

        return resolved
    }

    private static func loadMultiSelection(from provider: NSItemProvider) async -> [URL]? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: mqdirSelectionTypeIdentifier) { data, _ in
                guard let data,
                      let strings = try? JSONDecoder().decode([String].self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: strings.compactMap { URL(string: $0) })
            }
        }
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { obj, _ in
                continuation.resume(returning: obj as? URL)
            }
        }
    }

    /// Type identifiers a drop destination should accept.
    nonisolated static let acceptedDropTypes: [String] = [
        mqdirSelectionTypeIdentifier,
        UTType.fileURL.identifier,
    ]
}

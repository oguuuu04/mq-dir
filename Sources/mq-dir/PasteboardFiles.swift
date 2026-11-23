import AppKit

@MainActor
enum PasteboardFiles {
    enum Operation {
        case copy, move
    }

    static func urls(in pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        var seen: Set<URL> = []
        return objects.filter { url in
            url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
                && seen.insert(url.standardizedFileURL).inserted
        }
    }

    static func request(
        from pasteboard: NSPasteboard,
        to destination: URL?,
        operation: Operation,
        normalizeHangul: Bool
    ) -> FileWorkRequest? {
        guard let destination, destination.isFileURL else { return nil }
        let sources = urls(in: pasteboard)
        guard !sources.isEmpty else { return nil }
        return FileWorkRequest(
            kind: operation == .move ? .move : .copy,
            sources: sources,
            destination: destination,
            normalizeHangul: normalizeHangul
        )
    }
}

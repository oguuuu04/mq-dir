import AppKit
import XCTest

final class PasteboardFilesTests: XCTestCase {
    @MainActor
    func testStandardFileURLsProduceExplicitCopyAndMoveRequests() throws {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let source = URL(fileURLWithPath: "/fixture/source.txt")
        let destination = URL(fileURLWithPath: "/fixture/destination", isDirectory: true)
        pasteboard.writeObjects([source as NSURL])
        // A stale private cut marker must not change the meaning of Paste.
        pasteboard.setData(Data(), forType: .init("com.mqdir.cut.urls"))

        let copy = try XCTUnwrap(PasteboardFiles.request(
            from: pasteboard, to: destination, operation: .copy, normalizeHangul: false
        ))
        let move = try XCTUnwrap(PasteboardFiles.request(
            from: pasteboard, to: destination, operation: .move, normalizeHangul: false
        ))
        XCTAssertEqual(copy.kind, .copy)
        XCTAssertEqual(move.kind, .move)
        XCTAssertEqual(move.sources, [source])
        XCTAssertEqual(move.destination, destination)
        XCTAssertNil(PasteboardFiles.request(
            from: pasteboard, to: nil, operation: .move, normalizeHangul: false
        ))
    }

    @MainActor
    func testTextAndWebURLsAreNotFileTransfers() {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let destination = URL(fileURLWithPath: "/fixture/destination")
        pasteboard.setString("/fixture/source.txt", forType: .string)
        XCTAssertTrue(PasteboardFiles.urls(in: pasteboard).isEmpty)
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(string: "https://example.com/item")! as NSURL])
        XCTAssertNil(PasteboardFiles.request(
            from: pasteboard, to: destination, operation: .move, normalizeHangul: false
        ))
    }
}

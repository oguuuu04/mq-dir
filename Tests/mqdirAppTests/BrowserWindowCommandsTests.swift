import Combine
import XCTest

final class BrowserWindowCommandsTests: XCTestCase {
    @MainActor
    func testCommandsReachOnlyTheirAddressedWindow() {
        let left = BrowserWindowCommands()
        let right = BrowserWindowCommands()
        var leftReceived: [AppCommand] = []
        var rightReceived: [AppCommand] = []
        let leftObserver = left.publisher.sink { leftReceived.append($0) }
        let rightObserver = right.publisher.sink { rightReceived.append($0) }

        let commands: [AppCommand] = [.paste, .movePasteboardItems, .newFolder, .delete, .rename, .openSelected]
        for command in commands { left.send(command) }
        right.send(.selectTab(index: 1))

        XCTAssertEqual(leftReceived, commands)
        XCTAssertEqual(rightReceived, [.selectTab(index: 1)])
        withExtendedLifetime((leftObserver, rightObserver)) {}
    }
}

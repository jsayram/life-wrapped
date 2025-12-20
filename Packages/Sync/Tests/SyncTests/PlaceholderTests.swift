import XCTest
@testable import Sync

final class SyncTests: XCTestCase {
    func testPlaceholderExists() {
        XCTAssertNotNil(SyncPlaceholder.self)
    }
}

import Testing
@testable import Tack

@Test func accessibilityIDBoardFormatsName() {
    #expect(AccessibilityID.board("X") == "board-X")
}

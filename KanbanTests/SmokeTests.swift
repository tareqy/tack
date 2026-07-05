import Testing
@testable import Kanban

@Test func accessibilityIDBoardFormatsName() {
    #expect(AccessibilityID.board("X") == "board-X")
}

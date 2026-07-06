import Testing
@testable import Kanban

/// M10 (D-03): the pure status→urgency-role mapping `DueDateBadge` colors off. Kept in its own
/// suite, SwiftUI-free (like `DueDateStatusTests`), so the mapping is verified without spinning up
/// any view — `Views/Components/DueDateBadgeStyle+Color.swift` is what turns a `BadgeRole` into an
/// actual `Color` pair, and is exercised only by inspection/e2e, not unit tests (no SwiftUI `Color`
/// equality worth asserting against).
@Suite("DueDateBadgeStyle")
struct DueDateBadgeStyleTests {
    @Test("no due date maps to hidden — DueDateBadge is never shown at all in this case (PRD D-02)")
    func noneMapsToHidden() {
        #expect(DueDateBadgeStyle.role(for: .none) == .hidden)
    }

    @Test("overdue maps to alert (red)")
    func overdueMapsToAlert() {
        #expect(DueDateBadgeStyle.role(for: .overdue) == .alert)
    }

    @Test("due today maps to warn (orange)")
    func todayMapsToWarn() {
        #expect(DueDateBadgeStyle.role(for: .today) == .warn)
    }

    @Test("due tomorrow maps to notice (amber) — distinct role from today's warn")
    func tomorrowMapsToNotice() {
        #expect(DueDateBadgeStyle.role(for: .tomorrow) == .notice)
    }

    @Test("due later than tomorrow maps to neutral (gray, never green)")
    func upcomingMapsToNeutral() {
        #expect(DueDateBadgeStyle.role(for: .upcoming) == .neutral)
    }

    @Test("every DueDateStatus case maps to a distinct BadgeRole")
    func allCasesMapDistinctly() {
        let statuses: [DueDateStatus] = [.none, .overdue, .today, .tomorrow, .upcoming]
        let roles = statuses.map(DueDateBadgeStyle.role(for:))
        #expect(Set(roles).count == roles.count)
    }
}

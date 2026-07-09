import Testing
import Foundation
import SwiftData
@testable import Tack

@MainActor
@Suite("Labels")
struct LabelTests {
    @Test("ensureLabelsSeeded twice yields exactly 8 rows")
    func seedingIsIdempotent() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        env.store.ensureLabelsSeeded()
        let labels = try! env.context.fetch(FetchDescriptor<CardLabel>())
        #expect(labels.count == 8)
        #expect(Set(labels.map(\.colorName)) == Set(LabelColor.allCases.map(\.rawValue)))
    }

    @Test("toggleLabel adds then removes")
    func toggleAddsThenRemoves() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Card")

        env.store.toggleLabel(.red, on: card)
        #expect(card.labels.map(\.colorName) == ["red"])

        env.store.toggleLabel(.red, on: card)
        #expect(card.labels.isEmpty)
    }

    @Test("two cards can share the same label")
    func twoCardsShareLabel() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let cardA = env.store.addCard(to: list, title: "A")
        let cardB = env.store.addCard(to: list, title: "B")

        env.store.toggleLabel(.blue, on: cardA)
        env.store.toggleLabel(.blue, on: cardB)

        #expect(cardA.labels.map(\.colorName) == ["blue"])
        #expect(cardB.labels.map(\.colorName) == ["blue"])

        let blueLabel = try! env.context.fetch(FetchDescriptor<CardLabel>()).first { $0.colorName == "blue" }
        #expect(blueLabel?.cards.count == 2)
    }

    @Test("setDueDate normalizes to start of day")
    func setDueDateNormalizesToStartOfDay() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Card")

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 17
        components.minute = 45
        let dueDateWithTime = Calendar.current.date(from: components)!

        env.store.setDueDate(dueDateWithTime, on: card)

        let expectedStartOfDay = Calendar.current.startOfDay(for: dueDateWithTime)
        #expect(card.dueDate == expectedStartOfDay)
        #expect(card.includesTime == false)
    }

    @Test("setDueDate with nil clears the due date")
    func setDueDateNilClears() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Card")
        env.store.setDueDate(.now, on: card)
        env.store.setDueDate(nil, on: card)
        #expect(card.dueDate == nil)
    }

    @Test("setDueDate with includesTime keeps the raw time and stores the duration")
    func setDueDateTimedKeepsRawTimeAndDuration() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 14
        components.minute = 0
        let slotStart = Calendar.current.date(from: components)!

        env.store.setDueDate(slotStart, on: card, includesTime: true, durationMinutes: 60)

        #expect(card.dueDate == slotStart, "timed dates are NOT startOfDay-normalized")
        #expect(card.includesTime == true)
        #expect(card.durationMinutes == 60)
    }

    @Test("setDueDate normalizes non-positive durations to nil")
    func setDueDateNonPositiveDurationNil() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        env.store.setDueDate(.now, on: card, includesTime: true, durationMinutes: 0)
        #expect(card.durationMinutes == nil)
        env.store.setDueDate(.now, on: card, includesTime: true, durationMinutes: -30)
        #expect(card.durationMinutes == nil)
        #expect(card.includesTime == true, "the flag itself survives — only the duration is clamped")
    }

    @Test("date-only and nil setDueDate calls both clear a previous time slot")
    func setDueDateDateOnlyAndNilClearTimeState() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 14
        let slotStart = Calendar.current.date(from: components)!
        env.store.setDueDate(slotStart, on: card, includesTime: true, durationMinutes: 60)

        // Date-only call (the defaults) downgrades: startOfDay, flag off, duration gone.
        env.store.setDueDate(slotStart, on: card)
        #expect(card.dueDate == Calendar.current.startOfDay(for: slotStart))
        #expect(card.includesTime == false)
        #expect(card.durationMinutes == nil)

        // Re-time it, then clear with nil — even with stray time args, everything resets.
        env.store.setDueDate(slotStart, on: card, includesTime: true, durationMinutes: 60)
        env.store.setDueDate(nil, on: card, includesTime: true, durationMinutes: 60)
        #expect(card.dueDate == nil)
        #expect(card.includesTime == false)
        #expect(card.durationMinutes == nil)
    }

    // MARK: - M-D: setDueDate same-value guard

    @Test("setDueDate with an identical resulting trio registers no undo step and keeps updatedAt")
    func setDueDateSameValueIsNoOp() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        let day = Calendar.current.startOfDay(for: .now)
        env.store.setDueDate(day, on: card)
        env.undoManager?.removeAllActions()
        let stamp = card.updatedAt

        env.store.setDueDate(day, on: card) // same resulting (dueDate, includesTime, duration) trio

        #expect(env.undoManager?.canUndo == false,
                "dropping a card on its own day must not register a junk undo step")
        #expect(card.updatedAt == stamp, "a no-change call must not bump updatedAt either")
    }

    @Test("the guard compares the NORMALIZED trio: same-day date-only re-set at a different clock time is a no-op")
    func setDueDateSameDayDifferentClockTimeIsNoOp() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        let day = Calendar.current.startOfDay(for: .now)
        env.store.setDueDate(day, on: card)
        env.undoManager?.removeAllActions()

        // 15:30 on the same day normalizes to the same start-of-day — identical trio.
        env.store.setDueDate(day.addingTimeInterval(15.5 * 3600), on: card)

        #expect(env.undoManager?.canUndo == false)
        #expect(card.dueDate == day)
    }

    @Test("timed same trio is a no-op; changing only the duration still registers")
    func setDueDateTimedGuardAndDurationChange() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        let slot = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now)!
        env.store.setDueDate(slot, on: card, includesTime: true, durationMinutes: 60)
        env.undoManager?.removeAllActions()

        env.store.setDueDate(slot, on: card, includesTime: true, durationMinutes: 60)
        #expect(env.undoManager?.canUndo == false, "identical timed trio → no undo step")

        env.store.setDueDate(slot, on: card, includesTime: true, durationMinutes: 30)
        #expect(env.undoManager?.canUndo == true, "a real duration change still registers")
        #expect(card.durationMinutes == 30)
    }

    @Test("nil-to-nil is a no-op")
    func setDueDateNilToNilIsNoOp() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card") // dueDate starts nil
        env.undoManager?.removeAllActions()

        env.store.setDueDate(nil, on: card)

        #expect(env.undoManager?.canUndo == false)
    }
}

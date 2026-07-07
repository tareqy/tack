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
}

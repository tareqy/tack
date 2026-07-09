import Testing
import Foundation
import SwiftData
@testable import Tack

@MainActor
@Suite("Cascade Delete")
struct CascadeDeleteTests {
    @Test("deleting a board cascades to its lists and cards")
    func deleteBoardCascades() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        _ = env.store.addCard(to: list, title: "Card")

        env.store.deleteBoard(board)

        let lists = try! env.context.fetch(FetchDescriptor<BoardList>())
        let cards = try! env.context.fetch(FetchDescriptor<Card>())
        #expect(lists.isEmpty)
        #expect(cards.isEmpty)
    }

    @Test("deleting a list removes its cards but leaves the board's other lists intact")
    func deleteListCascadesToCardsOnly() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let toDelete = board.sortedLists[0]
        let untouched = board.sortedLists[1]
        let cardInDeleted = env.store.addCard(to: toDelete, title: "Doomed")
        _ = env.store.addCard(to: untouched, title: "Safe")

        env.store.deleteList(toDelete)

        let cards = try! env.context.fetch(FetchDescriptor<Card>())
        #expect(!cards.contains { $0.id == cardInDeleted.id })
        #expect(cards.count == 1)

        let remainingLists = try! env.context.fetch(FetchDescriptor<BoardList>())
        #expect(remainingLists.contains { $0.id == untouched.id })
        #expect(remainingLists.count == 2) // Done + In Progress survive
    }

    @Test("deleting a card with labels leaves all 8 labels intact")
    func deleteCardWithLabelsLeavesLabelsIntact() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Card")
        env.store.toggleLabel(.red, on: card)
        env.store.toggleLabel(.green, on: card)

        env.store.deleteCard(card)

        let labels = try! env.context.fetch(FetchDescriptor<CardLabel>())
        #expect(labels.count == 8)
    }

    @Test("deleteCard cascades to its checklist items (M-E)")
    func deleteCardCascadesToChecklistItems() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [ChecklistDraft(id: nil, text: "One", isDone: false),
                                             ChecklistDraft(id: nil, text: "Two", isDone: true)])

        env.store.deleteCard(card)

        let items = (try? env.context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        #expect(items.isEmpty, "no orphaned checklist rows after a card delete")
    }

    @Test("deleteList cascades through cards to checklist items (M-E)")
    func deleteListCascadesThroughCardsToChecklistItems() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [ChecklistDraft(id: nil, text: "One", isDone: false)])

        env.store.deleteList(list)

        let items = (try? env.context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        #expect(items.isEmpty, "no orphaned checklist rows after a list delete")
    }
}

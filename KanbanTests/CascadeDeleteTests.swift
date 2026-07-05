import Testing
import Foundation
import SwiftData
@testable import Kanban

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
}

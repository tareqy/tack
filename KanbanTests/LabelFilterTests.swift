import Testing
import Foundation
@testable import Kanban

/// M11 (LB-03): the pure OR-semantics filter behind the label filter bar. Cards are built through
/// `BoardStore` (matching `LabelTests`'s pattern) so `card.labels` is populated exactly as
/// production code populates it, but `LabelFilter.visibleCards` itself takes plain `[Card]` +
/// `Set<LabelColor>` — no store/context involvement in the assertions themselves.
@MainActor
@Suite("LabelFilter")
struct LabelFilterTests {
    @Test("empty active set shows every card, labeled or not")
    func emptySetShowsAll() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let labeled = env.store.addCard(to: list, title: "Labeled")
        env.store.toggleLabel(.red, on: labeled)
        let unlabeled = env.store.addCard(to: list, title: "Unlabeled")

        let visible = LabelFilter.visibleCards([labeled, unlabeled], active: [])
        #expect(visible.map(\.id) == [labeled.id, unlabeled.id])
    }

    @Test("a single active label shows only cards carrying it")
    func singleLabel() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let red = env.store.addCard(to: list, title: "Red")
        env.store.toggleLabel(.red, on: red)
        let green = env.store.addCard(to: list, title: "Green")
        env.store.toggleLabel(.green, on: green)

        let visible = LabelFilter.visibleCards([red, green], active: [.red])
        #expect(visible.map(\.id) == [red.id])
    }

    @Test("OR across two active labels shows cards matching either")
    func orAcrossTwoLabels() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let red = env.store.addCard(to: list, title: "Red")
        env.store.toggleLabel(.red, on: red)
        let green = env.store.addCard(to: list, title: "Green")
        env.store.toggleLabel(.green, on: green)
        let blue = env.store.addCard(to: list, title: "Blue")
        env.store.toggleLabel(.blue, on: blue)

        let visible = LabelFilter.visibleCards([red, green, blue], active: [.red, .green])
        #expect(Set(visible.map(\.id)) == Set([red.id, green.id]))
    }

    @Test("a card with no labels is hidden under any active (non-empty) filter")
    func unlabeledCardHidden() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let unlabeled = env.store.addCard(to: list, title: "Unlabeled")

        let visible = LabelFilter.visibleCards([unlabeled], active: [.red])
        #expect(visible.isEmpty)
    }

    @Test("all 8 colors active still hides unlabeled cards — NOT the same as the empty-set case")
    func allEightColorsActive() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        let labeled = env.store.addCard(to: list, title: "Labeled")
        env.store.toggleLabel(.pink, on: labeled)
        let unlabeled = env.store.addCard(to: list, title: "Unlabeled")

        let visible = LabelFilter.visibleCards([labeled, unlabeled], active: Set(LabelColor.allCases))
        #expect(visible.map(\.id) == [labeled.id])
    }
}

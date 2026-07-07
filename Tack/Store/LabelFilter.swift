import Foundation

/// Pure OR-semantics filtering for the label filter bar (LB-03, M11). This is PURE VIEW STATE —
/// nothing here touches `BoardStore`, persists anything, or is reachable outside rendering.
/// `ListColumnView` renders through this; every drop-index computation (`appendCard`, `dropOnRow`,
/// `handleDrop`) deliberately keeps reasoning about the FULL `list.sortedCards`/`board.sortedLists`
/// — see those call sites' doc comments — so the frozen M4→M5 drop architecture is untouched by
/// this milestone.
enum LabelFilter {
    /// - `active` empty → every card is visible (no filter): returns `cards` unchanged.
    /// - `active` non-empty → OR semantics: a card is visible iff it owns AT LEAST ONE label whose
    ///   color is in `active`. A card with no labels at all is therefore hidden by ANY non-empty
    ///   filter — including the "all 8 colors active" case, which is deliberately NOT equivalent to
    ///   the empty-set "show everything" case (see `LabelFilterTests.allEightColorsActive`).
    static func visibleCards(_ cards: [Card], active: Set<LabelColor>) -> [Card] {
        guard !active.isEmpty else { return cards }
        return cards.filter { card in
            let owned = Set(card.labels.compactMap(\.color))
            return !owned.isDisjoint(with: active)
        }
    }
}

import Foundation
import Observation
import SwiftData

/// Common shape shared by Board's and BoardList's ordered children so position
/// bookkeeping (renumbering/reordering) can be written once and reused for both.
private protocol PositionedEntity: AnyObject {
    var id: UUID { get }
    var position: Int { get set }
}

extension BoardList: PositionedEntity {}
extension Card: PositionedEntity {}

/// The ONLY mutation surface for the Kanban model graph. Every method performs its
/// writes, saves the context, and wraps itself in a single undo group so it is exactly
/// one user-facing undo step (see `withUndoGroup`).
@MainActor
@Observable
final class BoardStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        // We manage grouping boundaries explicitly per operation below; disable the
        // run-loop/event based auto-grouping so headless (non-NSApplication) contexts,
        // like unit tests, don't leave every registration in one never-closed group.
        context.undoManager?.groupsByEvent = false
    }

    // MARK: - Labels

    /// Idempotent: exactly 8 CardLabel rows exist after any number of calls.
    func ensureLabelsSeeded() {
        withUndoGroup("Seed Labels") {
            let existingColorNames = Set(fetchLabels().map(\.colorName))
            for color in LabelColor.allCases where !existingColorNames.contains(color.rawValue) {
                context.insert(CardLabel(colorName: color.rawValue))
            }
            save()
        }
    }

    // MARK: - Boards

    @discardableResult
    func createBoard(name: String, emoji: String?) -> Board {
        var createdBoard: Board!
        withUndoGroup("Create Board") {
            let nextPosition = (fetchBoards().map(\.position).max() ?? -1) + 1
            let board = Board(name: name, emoji: emoji, position: nextPosition)
            context.insert(board)
            for (index, listName) in ["To Do", "In Progress", "Done"].enumerated() {
                let list = BoardList(name: listName, position: index, board: board)
                context.insert(list)
            }
            save()
            createdBoard = board
        }
        return createdBoard
    }

    func renameBoard(_ board: Board, to name: String) {
        withUndoGroup("Rename Board") {
            board.name = name
            save()
        }
    }

    /// Deletes the board. The two-level cascade (board → lists → cards) runs with the undo
    /// manager DETACHED and the undo stack is cleared afterwards, so board deletion is NOT
    /// undoable — deliberately, and only for this operation:
    ///
    /// SwiftData's automatic undo snapshotting of a two-level cascade delete crashes with a fatal
    /// assertion whenever an undo manager is attached to an ON-DISK context (EXC_BREAKPOINT inside
    /// SwiftData's cascade processing; reproduced three times under --uitest with identical stacks
    /// through `deleteBoard → withUndoGroup` — crash reports Kanban-2026-07-06-092132/100952/
    /// 101206.ips). `groupsByEvent` true vs false makes no difference (the crash is in snapshot
    /// creation, not grouping), and in-memory unit stores never hit it — which is why the M1 suite
    /// stayed green while every real-app board delete died. Single-level shapes are unaffected:
    /// `deleteList` (list → cards) and `deleteCard` run green with the manager attached, so they
    /// keep their original undo-grouped form.
    ///
    /// The stack clear is required for safety, not convenience: earlier registered groups (board
    /// renames, card ops on this board) hold references to the now-deleted objects, and undoing
    /// them after the delete would mutate deleted rows. Losing undo history on a board delete is
    /// acceptable UX — the operation is already confirmation-gated in SidebarView, and the PRD's
    /// undo story centres on card operations, which remain fully undoable.
    func deleteBoard(_ board: Board) {
        let undoManager = context.undoManager
        context.undoManager = nil
        context.delete(board)
        save()
        context.undoManager = undoManager
        undoManager?.removeAllActions()
    }

    /// Pure — case-insensitive substring match on name; empty query returns all boards.
    static func filterBoards(_ boards: [Board], query: String) -> [Board] {
        guard !query.isEmpty else { return boards }
        return boards.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Lists

    @discardableResult
    func addList(to board: Board, name: String) -> BoardList {
        var createdList: BoardList!
        withUndoGroup("Add List") {
            let position = board.lists.count
            let list = BoardList(name: name, position: position, board: board)
            context.insert(list)
            save()
            createdList = list
        }
        return createdList
    }

    func renameList(_ list: BoardList, to name: String) {
        withUndoGroup("Rename List") {
            list.name = name
            save()
        }
    }

    /// Renumbers survivors to 0..<n.
    func deleteList(_ list: BoardList) {
        withUndoGroup("Delete List") {
            // Compute survivors BEFORE deleting: `board.lists` does not drop the
            // deleted object until the context is saved, so reading it afterwards
            // would renumber against a stale (still-includes-the-deleted-list) array.
            let survivors = list.board?.sortedLists.filter { $0.id != list.id } ?? []
            context.delete(list)
            renumber(survivors)
            save()
        }
    }

    /// Reorders `list` within its board so it ends up at `index`; renumbers all
    /// siblings to a contiguous 0..<n.
    func moveList(_ list: BoardList, to index: Int) {
        guard let board = list.board else { return }
        withUndoGroup("Move List") {
            let siblings = board.sortedLists
            let ids = siblings.map(\.id)
            guard let fromIndex = ids.firstIndex(of: list.id) else { return }
            let newOrder = Reordering.movedWithin(ids, from: fromIndex, to: index)
            applyPositions(newOrder, to: siblings)
            save()
        }
    }

    // MARK: - Cards

    @discardableResult
    func addCard(to list: BoardList, title: String) -> Card {
        var createdCard: Card!
        withUndoGroup("Add Card") {
            let position = list.cards.count
            let card = Card(title: title, position: position, list: list)
            context.insert(card)
            save()
            createdCard = card
        }
        return createdCard
    }

    func updateTitle(_ card: Card, _ title: String) {
        withUndoGroup("Rename Card") {
            card.title = title
            card.updatedAt = .now
            save()
        }
    }

    func updateDetails(_ card: Card, _ details: String?) {
        withUndoGroup("Edit Card Details") {
            card.details = details
            card.updatedAt = .now
            save()
        }
    }

    /// Renumbers survivors to 0..<n.
    func deleteCard(_ card: Card) {
        withUndoGroup("Delete Card") {
            // Compute survivors BEFORE deleting: `list.cards` does not drop the
            // deleted object until the context is saved, so reading it afterwards
            // would renumber against a stale (still-includes-the-deleted-card) array.
            let survivors = card.list?.sortedCards.filter { $0.id != card.id } ?? []
            context.delete(card)
            renumber(survivors)
            save()
        }
    }

    /// Works for same-list reorder AND cross-list move; renumbers all affected
    /// positions contiguously. Purely positional — does NOT bump `updatedAt`.
    func moveCard(_ card: Card, to destination: BoardList, at index: Int) {
        guard let source = card.list else { return }

        if source.id == destination.id {
            withUndoGroup("Move Card") {
                let siblings = source.sortedCards
                let ids = siblings.map(\.id)
                guard let fromIndex = ids.firstIndex(of: card.id) else { return }
                let newOrder = Reordering.movedWithin(ids, from: fromIndex, to: index)
                applyPositions(newOrder, to: siblings)
                save()
            }
            return
        }

        // Cross-list move: reassigns Card.list AND rewrites positions in TWO
        // relationship collections at once. SwiftData's automatic undo registration
        // was empirically found to correctly UNDO this shape of change but to break
        // REDO (both lists end up empty) — see report for repro. Fall back to an
        // explicit, manually-registered inverse for this operation, with automatic
        // registration disabled for the span of the manual mutations so the two
        // mechanisms don't double-register the same change.
        let beforeSourceIDs = source.sortedCards.map(\.id) // includes card.id

        context.undoManager?.disableUndoRegistration()
        applyCrossListCardMove(card: card, from: source, to: destination, at: index)
        context.undoManager?.enableUndoRegistration()

        registerUndoable(name: "Move Card", undo: { [weak self] in
            guard let self else { return }
            self.context.undoManager?.disableUndoRegistration()
            let remainingDest = destination.sortedCards.filter { $0.id != card.id }
            card.list = source
            self.renumber(remainingDest)
            let restoredSource = source.sortedCards.filter { $0.id != card.id } + [card]
            self.applyPositions(beforeSourceIDs, to: restoredSource)
            self.save()
            self.context.undoManager?.enableUndoRegistration()
        }, redo: { [weak self] in
            guard let self else { return }
            self.context.undoManager?.disableUndoRegistration()
            self.applyCrossListCardMove(card: card, from: source, to: destination, at: index)
            self.context.undoManager?.enableUndoRegistration()
        })
    }

    private func applyCrossListCardMove(card: Card, from source: BoardList, to destination: BoardList, at index: Int) {
        let remainingSource = source.sortedCards.filter { $0.id != card.id }
        let destSiblings = destination.sortedCards.filter { $0.id != card.id }
        let destIDs = destSiblings.map(\.id)
        let newDestOrder = Reordering.inserted(card.id, into: destIDs, at: index)

        card.list = destination
        renumber(remainingSource)
        applyPositions(newDestOrder, to: destSiblings + [card])
        save()
    }

    // MARK: - Labels on cards

    func toggleLabel(_ color: LabelColor, on card: Card) {
        withUndoGroup("Toggle Label") {
            guard let label = fetchLabels().first(where: { $0.colorName == color.rawValue }) else { return }
            if let index = card.labels.firstIndex(where: { $0.colorName == color.rawValue }) {
                card.labels.remove(at: index)
            } else {
                card.labels.append(label)
            }
            card.updatedAt = .now
            save()
        }
    }

    /// Normalizes to local start-of-day (includesTime stays false in the MVP).
    func setDueDate(_ date: Date?, on card: Card) {
        withUndoGroup("Set Due Date") {
            if let date {
                card.dueDate = Calendar.current.startOfDay(for: date)
            } else {
                card.dueDate = nil
            }
            card.includesTime = false
            card.updatedAt = .now
            save()
        }
    }

    /// Commits every staged field of the M6 card-detail sheet as ONE undo group ("Edit Card"), so a
    /// single ⌘Z reverses title/details/labels/dueDate together. Applies only the fields that
    /// actually changed (labels are diffed against the card's current set; untouched labels aren't
    /// re-written) and bumps `updatedAt` only if something changed — a call where every argument
    /// already matches the card's current state registers no undo step at all. `title` is trimmed;
    /// an empty/whitespace-only result is a no-op for the title specifically (the existing title is
    /// kept) rather than clearing it — other changed fields in the same call still apply and still
    /// bump `updatedAt`. `dueDate` is normalized exactly like `setDueDate` (local start-of-day;
    /// `includesTime` stays false).
    func applyCardEdits(_ card: Card, title: String, details: String?, labels: Set<LabelColor>, dueDate: Date?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = trimmedTitle.isEmpty ? card.title : trimmedTitle
        let normalizedDueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        let currentLabelColors = Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) })
        let labelsToAdd = labels.subtracting(currentLabelColors)
        let labelsToRemove = currentLabelColors.subtracting(labels)

        let titleChanged = newTitle != card.title
        let detailsChanged = details != card.details
        let dueDateChanged = normalizedDueDate != card.dueDate
        let labelsChanged = !labelsToAdd.isEmpty || !labelsToRemove.isEmpty

        guard titleChanged || detailsChanged || dueDateChanged || labelsChanged else { return }

        withUndoGroup("Edit Card") {
            if titleChanged { card.title = newTitle }
            if detailsChanged { card.details = details }
            if dueDateChanged {
                card.dueDate = normalizedDueDate
                card.includesTime = false
            }
            if labelsChanged {
                let labelsByColorName = Dictionary(uniqueKeysWithValues: fetchLabels().map { ($0.colorName, $0) })
                for color in labelsToAdd {
                    if let label = labelsByColorName[color.rawValue] {
                        card.labels.append(label)
                    }
                }
                for color in labelsToRemove {
                    if let index = card.labels.firstIndex(where: { $0.colorName == color.rawValue }) {
                        card.labels.remove(at: index)
                    }
                }
            }
            card.updatedAt = .now
            save()
        }
    }

    // MARK: - Position bookkeeping

    private func renumber<T: PositionedEntity>(_ items: [T]) {
        for (index, item) in items.enumerated() {
            item.position = index
        }
    }

    private func applyPositions<T: PositionedEntity>(_ orderedIDs: [UUID], to items: [T]) {
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for (position, id) in orderedIDs.enumerated() {
            itemsByID[id]?.position = position
        }
    }

    // MARK: - Undo grouping

    /// Wraps `body` in a single undo group so, however many individual model edits it
    /// makes, the whole operation is exactly one user-facing undo/redo step.
    private func withUndoGroup(_ name: String, _ body: () -> Void) {
        guard let undoManager = context.undoManager else {
            body()
            return
        }
        undoManager.beginUndoGrouping()
        body()
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }

    /// Explicit registerUndo fallback (see moveCard) for operations where SwiftData's
    /// automatic registration doesn't correctly support redo. `undo` and `redo` must each
    /// be total, idempotent-from-captured-state closures (not relying on relationship
    /// array timing) — see `applyCrossListCardMove` for the pattern.
    ///
    /// Uses the standard recursive-registration idiom: invoking `undo` inside the
    /// registered handler, then immediately re-registering with the roles swapped, is
    /// what makes `redo` (and subsequent undo/redo cycles, indefinitely) work — UndoManager
    /// automatically routes registrations made while it is undoing onto the redo stack.
    private func registerUndoable(name: String, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        guard let undoManager = context.undoManager else { return }
        // NSUndoManager requires an open group when registering ("must begin a group
        // before registering undo" is thrown otherwise). Event-based auto-grouping
        // (groupsByEvent) never fires in a headless test host, so open one explicitly.
        // EXCEPT while the manager is undoing/redoing: it provides its own implicit
        // group there and re-registration without one is the documented redo mechanism.
        let needsExplicitGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if needsExplicitGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { target in
            undo()
            target.registerUndoable(name: name, undo: redo, redo: undo)
        }
        undoManager.setActionName(name)
        if needsExplicitGroup { undoManager.endUndoGrouping() }
    }

    // MARK: - Fetch helpers

    private func fetchBoards() -> [Board] {
        (try? context.fetch(FetchDescriptor<Board>())) ?? []
    }

    private func fetchLabels() -> [CardLabel] {
        (try? context.fetch(FetchDescriptor<CardLabel>())) ?? []
    }

    private func save() {
        try? context.save()
    }
}

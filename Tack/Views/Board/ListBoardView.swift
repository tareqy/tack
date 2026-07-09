import SwiftUI

/// M-C: the List View — the selected board's cards flattened into due-date buckets (Overdue /
/// Today / This Week / Later / No Date), a SIBLING of `BoardView` behind `RootView.detailContent`'s
/// per-board mode switch. Read-mostly in v1: rows select (click), open the shared `CardDetailView`
/// sheet (double-click / context menu / ⌘O), and delete (context menu / ⌘⌫); creation, ⌘-arrow
/// moves, and the label filter are HONESTLY disabled through the published `BoardActions` (see
/// `boardActions` below) — a computed bucket has no "insert here" semantics.
///
/// Buckets recompute per render against the live clock (one pass over the board's cards — cheap
/// at this app's scale; the NFR fixture is board-canvas-scoped). Flatten IGNORES `isCollapsed`:
/// collapse is board-canvas layout state, and a due-date digest that silently dropped a collapsed
/// list's cards would lie (see `ListBucketSnapshot`).
struct ListBoardView: View {
    let board: Board
    let store: BoardStore

    /// List-mode single-card selection. Same @State-leak caveat as `BoardView`'s filter state:
    /// `detailContent` swaps only the `board:` argument across a board switch (the view is NOT
    /// recreated), so this is explicitly reset via `.onChange(of: board.id)` below.
    @State private var selectedCardID: UUID?
    /// The card currently showing its detail sheet (same `.sheet(item:)` shape as BoardView).
    @State private var selectedDetailCard: Card?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(sections, id: \.bucket) { section in
                    bucketSection(section.bucket, cards: section.cards)
                }
                if sections.isEmpty {
                    // Same native empty-state dressing as RootView's no-board branches.
                    ContentUnavailableView(
                        "No Cards",
                        systemImage: "list.bullet",
                        description: Text("Cards you add to this board appear here, grouped by due date.")
                    )
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // HIG: the window title reflects the shown content — same as BoardView.
        .navigationTitle(board.name)
        // M8 theme wash, verbatim from BoardView: attached after frame so it covers the whole
        // detail area edge-to-edge; rows keep their own cardSurface backing on top.
        .background(themeBackground)
        .sheet(item: $selectedDetailCard) { card in
            CardDetailView(card: card, store: store, onDelete: {
                // Order matters — see CardDetailView.onDelete: close the sheet (nil the item)
                // BEFORE deleting, so no re-render evaluates the sheet against a deleted card.
                selectedDetailCard = nil
                store.deleteCard(card)
            })
        }
        // Exported command surface — the same keys BoardView publishes, including the M7 rule:
        // boardActions goes NIL while the detail sheet is up (menu key equivalents match before
        // the sheet's responder chain; an enabled ⌘⌫ would delete the card behind its own sheet).
        .focusedSceneValue(\.focusedBoard, board)
        .focusedSceneValue(\.selectedCard, selectedCard)
        .focusedSceneValue(\.focusedList, selectedCard?.list)
        .focusedSceneValue(\.boardActions, selectedDetailCard == nil ? boardActions : nil)
        .onChange(of: board.id) { _, _ in clearSelectionIfInvisible() }
    }

    // MARK: - Sections

    /// The rendered (bucket, cards) pairs — see `ListBucketSnapshot.sections`.
    private var sections: [(bucket: ListBucket, cards: [Card])] {
        ListBucketSnapshot.sections(board: board, now: .now, calendar: .current)
    }

    /// Header + rows as SIBLINGS (the section id lives on the header, never on a container
    /// wrapping the rows — ancestor ids shadow children).
    @ViewBuilder
    private func bucketSection(_ bucket: ListBucket, cards: [Card]) -> some View {
        HStack(spacing: 8) {
            Text(bucket.title)
                .font(.headline)
            // The countLabel idiom (ListColumnView): plain quiet text, no capsule.
            Text("\(cards.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.listSection(bucket.sectionSlug))

        ForEach(cards) { card in
            CardListRow(
                card: card,
                isSelected: selectedCardID == card.id,
                onSelect: { selectedCardID = card.id },
                onOpen: { selectedDetailCard = card },
                onDelete: { deleteCard(card) }
            )
        }
    }

    // MARK: - M8: theme (verbatim from BoardView)

    private var themeBackground: Color {
        switch ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex) {
        case .preset(let theme): theme.backgroundColor
        // Custom hex is a WASH like every preset — see BoardView.themeBackground.
        case .custom(let color): color.opacity(0.15)
        }
    }

    // MARK: - Selection + command surface

    /// The bucket snapshot the keyboard commands reason about (buckets ARE ListSnapshots, so
    /// `SelectionNavigation.next` works unchanged across section boundaries).
    private var snapshot: BoardSnapshot { ListBucketSnapshot.build(board: board, now: .now, calendar: .current) }

    private var visibleCardIDs: Set<UUID> { Set(snapshot.lists.flatMap(\.cardIDs)) }

    /// The list-mode `clearSelectionIfInvisible` (BoardView's visibility seam, adapted). In list
    /// mode EVERY card of the board is always visible — flatten ignores collapse and there is no
    /// filter — so the only invisibility triggers are deletion (both delete paths below nil the
    /// selection before the store call) and a board switch, which is the one trigger wired to
    /// this (`.onChange(of: board.id)` — a card id can never belong to the new board, so this is
    /// an unconditional clear in practice). Deliberately NOT keyed on the derived card-id set:
    /// that churns on card add/remove and transient SwiftData re-renders (the documented
    /// BoardView trap) and would clear a valid selection mid-navigation.
    private func clearSelectionIfInvisible() {
        guard let id = selectedCardID, !visibleCardIDs.contains(id) else { return }
        selectedCardID = nil
    }

    /// The live `Card` for the current selection (nil when none / stale — a stale id degrades
    /// to "no selection" everywhere, including SelectionNavigation's entry-point behavior).
    private var selectedCard: Card? {
        guard let selectedCardID else { return nil }
        return board.sortedLists.flatMap { $0.sortedCards }.first { $0.id == selectedCardID }
    }

    /// List-mode command surface. REAL: selection (`selectedCard`), ⌘O open, ⌘⌫ delete, and
    /// bare-arrow navigation over the bucket snapshot. HONESTLY DISABLED: `canCreateCard: false`
    /// (which list would a computed bucket create into?), `canMoveSelectedCard` false (⌘-arrow
    /// moves have no meaning between derived buckets), and `canFilter: false` (the M-C flag —
    /// View ▸ Filter by Label grays out instead of firing a silent no-op). KNOWN wart, accepted
    /// for v1: "New List" (⌥⌘N) enablement keys off boardActions' mere presence in AppCommands,
    /// so it stays enabled here and no-ops — creation lives in board mode.
    private var boardActions: BoardActions {
        BoardActions(
            selectedCard: selectedCard,
            newCard: {},
            canCreateCard: false,
            newList: {},
            deleteSelectedCard: deleteSelectedCard,
            openSelectedCard: openSelectedCard,
            moveSelectedCard: { _ in },
            moveSelection: moveSelection,
            canMoveSelectedCard: { _ in false },
            toggleLabelFilterBar: {},
            canFilter: false
        )
    }

    private func deleteSelectedCard() {
        guard let card = selectedCard else { return }
        selectedCardID = nil
        store.deleteCard(card)
    }

    private func openSelectedCard() {
        guard let card = selectedCard else { return }
        selectedDetailCard = card
    }

    private func moveSelection(_ direction: MoveDirection) {
        if let newID = SelectionNavigation.next(selectedCardID: selectedCardID, direction: direction, board: snapshot) {
            selectedCardID = newID
        }
    }

    /// Row context-menu delete: nil the selection FIRST if it's the deleted card (the CardView
    /// discipline), then one undoable store call.
    private func deleteCard(_ card: Card) {
        if selectedCardID == card.id { selectedCardID = nil }
        store.deleteCard(card)
    }
}

/// One List View row: title, label dots, the parent list's name, the due badge — selection ring
/// and click semantics copied from `CardView` (first click selects immediately, double-click
/// opens; `.simultaneously`, not `.exclusively`, for the same no-selection-lag reason). The title
/// is a PLAIN `Text` (no `InlineEditableText` in v1): no rename-vs-open gesture split, no text
/// input, no `reportsTextInputFocus` site — renames go through the sheet or board mode.
private struct CardListRow: View {
    let card: Card
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    /// Ordered by `LabelColor.allCases`, not insertion order — same as CardView.
    private var sortedLabelColors: [LabelColor] {
        let owned = Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) })
        return LabelColor.allCases.filter { owned.contains($0) }
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.8) : .surfaceHairline
    }

    private var selectionWashColor: Color {
        if isSelected { return Color.accentColor.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.045) }
        return .clear
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(card.title)
                .lineLimit(1)
                .truncationMode(.tail)
            labelDots
            Spacer(minLength: 8)
            // Where the card lives on the canvas — the list-mode substitute for column context.
            if let listName = card.list?.name {
                Text(listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let dueDate = card.dueDate {
                DueDateBadge(card: card, dueDate: dueDate)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The CardView surface treatment, verbatim: raised card + hairline + whisper of shadow.
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.cardSurface)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .fill(selectionWashColor)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(
            TapGesture(count: 2).onEnded { onOpen() }
                .simultaneously(with: TapGesture(count: 1).onEnded { onSelect() })
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.listRow(card.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // v1 rows: Open + Delete only. No Move to List (bucket ≠ list; moving lives on the
        // canvas), no Rename (no inline editor here).
        .contextMenu {
            Button("Open Card") { onOpen() }
            Button("Delete Card", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var labelDots: some View {
        if !sortedLabelColors.isEmpty {
            HStack(spacing: 4) {
                ForEach(sortedLabelColors, id: \.self) { color in
                    Circle()
                        .fill(color.swatchColor)
                        // Hairline ring so low-contrast fills stay legible — see CardView.
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                        .frame(width: 8, height: 8)
                }
            }
            // Representation Text, NOT .accessibilityValue — the latter is empty under XCUITest
            // on macOS (the M6 finding CardView.labelDots documents).
            .accessibilityRepresentation {
                Text(sortedLabelColors.map(\.rawValue).joined(separator: ","))
                    .accessibilityIdentifier(AccessibilityID.listRowLabels(card.title))
            }
        }
    }
}

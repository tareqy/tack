import SwiftUI

/// One card row: selectable (single click), renamable (double-click title OR context-menu "Rename
/// Card"), openable (double-click BODY OR context-menu "Open Card" — M6), draggable, and a per-row
/// drop target for reordering/cross-list moves. Productionizes the M2 spike's `cardRow`
/// (`Views/Spike/SpikeBoardView.swift`) — the draggable/dropDestination/insertion-indicator/
/// index-passing structure is copied from there unchanged; this view adds the selection ring,
/// inline rename, card-detail opening, and context menu on top.
///
/// Accessibility mirrors the spike's proven shape with ONE deliberate difference: the row is a
/// `.contain` container (not `.combine`), so the title's `InlineEditableText` keeps its own
/// individually-queryable identifier underneath for the rename flow. The container still carries
/// `card(title)`; the title carries the non-`card-`-prefixed `cardTitle(title)` so the order
/// assertion (`identifier BEGINSWITH "card-"`) never double-counts a row.
///
/// M6 grows the row to fit an optional second line (label dots + due-date badge) below the fixed
/// 44pt title line. The drop midline math must track the row's TRUE rendered height (not the base
/// 44pt) once it grows, or before/after targeting would be computed against the wrong extent — a
/// `GeometryReader` background measures it into `measuredRowHeight`, which `DropMath` uses instead
/// of the constant.
struct CardView: View {
    let board: Board
    let list: BoardList
    let card: Card
    let store: BoardStore
    @Binding var selectedCardID: UUID?
    @Binding var selectedDetailCard: Card?

    /// Same fixed row height as the M2 spike, so its DropMath midline reasoning carries over for
    /// the common case (no labels/due date). Also the initial value of `measuredRowHeight` before
    /// the first real layout pass reports back.
    private let rowHeight: CGFloat = 44

    @State private var isDropTargeted = false
    @State private var beginRename = false
    @State private var measuredRowHeight: CGFloat = 44

    private var isSelected: Bool { selectedCardID == card.id }

    /// This card's labels, ordered by `LabelColor.allCases` (not insertion order) — see
    /// `AccessibilityID.cardLabels`.
    private var sortedLabelColors: [LabelColor] {
        let owned = Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) })
        return LabelColor.allCases.filter { owned.contains($0) }
    }

    private var hasMetaLine: Bool { !sortedLabelColors.isEmpty || card.dueDate != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            InlineEditableText(
                card.title,
                beginEditOn: .doubleClick,
                accessibilityID: AccessibilityID.cardTitle(card.title),
                beginEditSignal: $beginRename
            ) { newTitle in
                store.updateTitle(card, newTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .padding(.horizontal, 10)

            if hasMetaLine {
                metaLine
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .overlay(alignment: .top) {
            InsertionIndicator()
                .opacity(isDropTargeted ? 1 : 0)
        }
        .background(rowHeightMeasurer)
        .contentShape(Rectangle())
        // Single click selects; double-click on the BODY opens the detail sheet. Double-click on
        // the TITLE still lands on its own `.doubleClick` gesture (a descendant, which SwiftUI
        // prioritizes over this ancestor one) and renames instead — see `InlineEditableText`. The
        // two counts are combined via `.exclusively(before:)` (not two stacked `.onTapGesture`
        // modifiers, whose same-view interaction is otherwise unspecified) so a real double-click
        // NEVER also fires the single-tap select.
        .gesture(
            TapGesture(count: 2).onEnded { selectedDetailCard = card }
                .exclusively(before: TapGesture(count: 1).onEnded { selectedCardID = card.id })
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.card(card.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .draggable(CardTransfer(cardID: card.id))
        .dropDestination(for: CardTransfer.self) { items, location in
            guard let transfer = items.first else { return false }
            let edge = DropMath.insertionEdge(locationY: location.y, rowHeight: measuredRowHeight)
            return dropOnRow(transfer: transfer, edge: edge)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu { contextMenu }
    }

    // MARK: - Meta line (M6: label dots + due-date badge)

    private var metaLine: some View {
        HStack(spacing: 6) {
            labelDots
            Spacer(minLength: 0)
            if let dueDate = card.dueDate {
                DueDateBadge(card: card, dueDate: dueDate)
            }
        }
    }

    @ViewBuilder
    private var labelDots: some View {
        if !sortedLabelColors.isEmpty {
            HStack(spacing: 4) {
                ForEach(sortedLabelColors, id: \.self) { color in
                    Circle()
                        .fill(color.swatchColor)
                        .frame(width: 8, height: 8)
                }
            }
            // NOT `.accessibilityElement(children:.ignore)` + `.accessibilityValue`: that shape
            // was verified EMPTY under XCUITest on macOS (an `Other` element with no label and no
            // value — see the M6 report's diagnostic dump). A representation Text makes this a
            // StaticText whose text IS the payload, which XCUITest reliably surfaces.
            .accessibilityRepresentation {
                Text(sortedLabelColors.map(\.rawValue).joined(separator: ","))
                    .accessibilityIdentifier(AccessibilityID.cardLabels(card.title))
            }
        }
    }

    /// Measures the row's true rendered height into `measuredRowHeight` so `DropMath` reasons about
    /// the ACTUAL extent (44pt base, or taller once a meta line is present) rather than the fixed
    /// `rowHeight` constant, which would otherwise misplace the before/after midline once a card
    /// grows a second line.
    private var rowHeightMeasurer: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { measuredRowHeight = proxy.size.height }
                .onChange(of: proxy.size) { _, newSize in measuredRowHeight = newSize.height }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open Card") { selectedDetailCard = card }
        Button("Rename Card") { beginRename = true }

        let others = board.sortedLists.filter { $0.id != list.id }
        if !others.isEmpty {
            Menu("Move to List") {
                ForEach(others) { other in
                    Button(other.name) {
                        // Cross-list append: destination array excludes the card, so "end" is count.
                        store.moveCard(card, to: other, at: other.cards.count)
                    }
                }
            }
        }

        // No confirmation (PRD v1.1 C-05: undoable via the store, Finder ⌘⌫ pattern).
        Button("Delete Card", role: .destructive) {
            if isSelected { selectedCardID = nil }
            store.deleteCard(card)
        }
    }

    // MARK: - Drop routing (copied from the spike's `dropOnRow`)

    private func dropOnRow(transfer: CardTransfer, edge: DropMath.InsertionEdge) -> Bool {
        isDropTargeted = false
        guard let movingCard = findCard(transfer.cardID) else { return false }
        let destinationCards = list.sortedCards
        guard let rowIndex = destinationCards.firstIndex(where: { $0.id == card.id }) else { return false }

        let sameList = movingCard.list?.id == list.id
        let fromIndex: Int? = sameList ? destinationCards.firstIndex(where: { $0.id == movingCard.id }) : nil
        let index = DropMath.destinationIndex(rowIndex: rowIndex, edge: edge, movingFromIndexInSameList: fromIndex)
        store.moveCard(movingCard, to: list, at: index)
        return true
    }

    private func findCard(_ id: UUID) -> Card? {
        board.sortedLists.flatMap { $0.sortedCards }.first { $0.id == id }
    }
}

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
    @State private var isHovering = false

    private var isSelected: Bool { selectedCardID == card.id }

    /// Selected cards trade the hairline for a calm accent border; unselected cards keep the
    /// separator hairline that lifts them off the column.
    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.8) : .surfaceHairline
    }

    /// One wash layer serves both states: a soft accent tint marks selection (native content
    /// selection is a tint, not a heavy outline), a fainter primary wash acknowledges hover.
    private var selectionWashColor: Color {
        if isSelected { return Color.accentColor.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.045) }
        return .clear
    }

    /// This card's labels, ordered by `LabelColor.allCases` (not insertion order) — see
    /// `AccessibilityID.cardLabels`.
    private var sortedLabelColors: [LabelColor] {
        let owned = Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) })
        return LabelColor.allCases.filter { owned.contains($0) }
    }

    private var hasMetaLine: Bool {
        !sortedLabelColors.isEmpty || card.dueDate != nil || !card.checklistItems.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .padding(.bottom, 12)
            }
        }
        // Raised card surface: adaptive fill + hairline + a whisper of shadow so cards read as
        // content sitting ON the column, not wells cut into it (the old `secondary.opacity(0.18)`
        // rendered DARKER than the column in light mode — inverted figure/ground).
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.cardSurface)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        }
        // Hover + selection tint share one quiet wash layer; hover is the standard macOS cue that
        // this flat rectangle is clickable/draggable.
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .fill(selectionWashColor)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            InsertionIndicator()
                .opacity(isDropTargeted ? 1 : 0)
        }
        .background(rowHeightMeasurer)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // Finder model: the FIRST click selects immediately (no double-click-interval lag), the
        // second click opens the detail sheet — opening implying selection is correct, so the two
        // gestures compose `.simultaneously` rather than the old `.exclusively` (which made every
        // selection wait out the double-click interval before showing its ring). Double-click on
        // the TITLE still lands on its own `.doubleClick` gesture (a descendant, which SwiftUI
        // prioritizes over this ancestor one) and renames instead — see `InlineEditableText`.
        .gesture(
            TapGesture(count: 2).onEnded { selectedDetailCard = card }
                .simultaneously(with: TapGesture(count: 1).onEnded { selectedCardID = card.id })
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
            checklistFraction
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
                        // Hairline ring so low-contrast fills (yellow measured 1.36:1 on white in
                        // the M10 audit) stay legible on the opaque light-mode card surface.
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
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

    /// M-E: the Action Items "done/total" fraction — present only when the card HAS items.
    /// Quiet secondary styling (it's a progress note, not an urgency signal like the badge).
    @ViewBuilder
    private var checklistFraction: some View {
        let total = card.checklistItems.count
        if total > 0 {
            let done = card.checklistItems.filter(\.isDone).count
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: 9))
                Text("\(done)/\(total)")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            // The labelDots/DueDateBadge pattern: a representation Text whose TEXT is the machine
            // payload — plain .accessibilityValue on SwiftUI shapes reads EMPTY under XCUITest on
            // macOS (the M6 finding). measuredRowHeight/DropMath need no change: the fraction
            // shares the existing meta line, so row height is untouched.
            .accessibilityRepresentation {
                Text("\(done)/\(total)")
                    .accessibilityIdentifier(AccessibilityID.cardChecklist(card.title))
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

        // No confirmation (PRD C-05, amended M-E: NOT undoable since M-E — see
        // BoardStore.deleteCard — Finder ⌘⌫ pattern).
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

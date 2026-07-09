import SwiftUI

/// M-D: the Calendar View — the selected board's dated cards on a month grid (7-column
/// LazyVGrid, weeks as rows), undated cards in a trailing "No Date" rail, a SIBLING of
/// `BoardView`/`ListBoardView` behind `RootView.detailContent`'s per-board mode switch.
/// Chips select (click), open the shared `CardDetailView` sheet (double-click / context menu /
/// ⌘O), delete (context menu / ⌘⌫), and DRAG onto day cells to reschedule
/// (`CalendarReschedule.retargetedDueDate` → the guarded `store.setDueDate` — a same-day drop
/// is a store-level no-op). Creation, ⌘-arrow moves, the label filter, AND bare-arrow selection
/// navigation are HONESTLY disabled through the published `BoardActions` (see `boardActions`
/// below — `canNavigateSelection: false` is new in M-D: a month grid has no card-list arrow
/// walk, and v1 ships none rather than a fake one).
///
/// CLOCK: anchors on real `Date()` by design (no injected clock — an injected 'now' would
/// desynchronize the grid from the fixture's launch-relative real-now due dates; see the M-D
/// plan's Architecture note). The month anchor is ALWAYS a month start
/// (`CalendarMonthGrid.monthStart`), so prev/next `byAdding: .month` can never clamp-drift.
///
/// OVERFLOW (v1): a cell shows at most 3 chips + a non-clickable "+N" — the full day list is
/// reachable by switching to List mode. Adjacent-month filler days render dimmed and
/// NON-interactive: no id, no chips, no drop destination — a card due outside the displayed
/// month appears only when its month is displayed.
struct CalendarBoardView: View {
    let board: Board
    let store: BoardStore

    /// Calendar-mode single-card selection. Same @State-leak caveat as ListBoardView's:
    /// `detailContent` swaps only the `board:` argument across a board switch (the view is NOT
    /// recreated), so this — and the month anchor — reset via `.onChange(of: board.id)` below.
    @State private var selectedCardID: UUID?
    /// The card currently showing its detail sheet (same `.sheet(item:)` shape as its siblings).
    @State private var selectedDetailCard: Card?
    /// First instant of the displayed month (see the clock note above).
    @State private var monthAnchor = CalendarMonthGrid.monthStart(containing: Date(), calendar: .current)
    /// The day currently highlighted as a drop target (nil when no drag hovers a cell).
    @State private var targetedDay: Date?

    private var calendar: Calendar { .current }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        HStack(spacing: 0) {
            calendarColumn
            if !undatedCards.isEmpty {
                Divider()
                noDateRail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // HIG: the window title reflects the shown content — same as BoardView/ListBoardView.
        .navigationTitle(board.name)
        // M8 theme wash, verbatim from BoardView: cells/chips keep their own surfaces on top.
        .background(themeBackground)
        .sheet(item: $selectedDetailCard) { card in
            CardDetailView(card: card, store: store, onDelete: {
                // Order matters — see CardDetailView.onDelete: close the sheet (nil the item)
                // BEFORE deleting, so no re-render evaluates the sheet against a deleted card.
                selectedDetailCard = nil
                store.deleteCard(card)
            })
        }
        // Exported command surface — the same keys the siblings publish, including the M7 rule:
        // boardActions goes NIL while the detail sheet is up (menu key equivalents match before
        // the sheet's responder chain; an enabled ⌘⌫ would delete the card behind its own sheet).
        .focusedSceneValue(\.focusedBoard, board)
        .focusedSceneValue(\.selectedCard, selectedCard)
        .focusedSceneValue(\.focusedList, selectedCard?.list)
        .focusedSceneValue(\.boardActions, selectedDetailCard == nil ? boardActions : nil)
        .onChange(of: board.id) { _, _ in
            // A board switch is a context switch: drop the old board's selection and snap the
            // grid back to the current month.
            selectedCardID = nil
            monthAnchor = CalendarMonthGrid.monthStart(containing: Date(), calendar: calendar)
        }
    }

    // MARK: - Month header + grid

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            monthHeader
            weekdayHeaderRow
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(days) { day in
                        dayCell(day)
                    }
                }
            }
        }
        .padding(16)
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
                // Visible "July 2026", machine value POSIX "yyyy-MM" — the DueDateBadge
                // visible/wire split, so tests never parse localized month names.
                .accessibilityRepresentation {
                    Text(Self.wireMonthFormatter.string(from: monthAnchor))
                        .accessibilityIdentifier(AccessibilityID.calendarMonthTitle)
                }
            Spacer()
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Previous month")
            .accessibilityLabel("Previous Month")
            .accessibilityIdentifier(AccessibilityID.calendarPrevButton)

            Button("Today") {
                monthAnchor = CalendarMonthGrid.monthStart(containing: Date(), calendar: calendar)
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Go to the current month")
            .accessibilityIdentifier(AccessibilityID.calendarTodayButton)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Next month")
            .accessibilityLabel("Next Month")
            .accessibilityIdentifier(AccessibilityID.calendarNextButton)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = CalendarMonthGrid.monthStart(containing: shifted, calendar: calendar)
        }
    }

    private var days: [CalendarMonthGrid.Day] {
        CalendarMonthGrid.days(anchoredAt: monthAnchor, calendar: calendar)
    }

    private var weekdayHeaderRow: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            // enumerated + offset id: very-short weekday symbols REPEAT ("S", "S", "T", "T"), so
            // `id: \.self` would collapse duplicate columns.
            ForEach(Array(CalendarMonthGrid.weekdayHeaders(calendar: calendar).enumerated()),
                    id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day cells

    /// One in-month cell = ONE `.dropDestination(for: CardTransfer.self)` — the CLAUDE.md
    /// shadowing invariant: destinations swallow every drag landing on them and stacked
    /// different-typed destinations shadow each other, so cells accept exactly one payload type
    /// and dimmed filler cells get no destination at all.
    @ViewBuilder
    private func dayCell(_ day: CalendarMonthGrid.Day) -> some View {
        if day.isInDisplayedMonth {
            let dayCards = cardsByDay[day.date] ?? []
            let isToday = calendar.isDateInToday(day.date)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                ForEach(dayCards.prefix(3)) { card in
                    chipView(card)
                }
                if dayCards.count > 3 {
                    // v1: NOT clickable — the full day list is reachable via List mode.
                    Text("+\(dayCards.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            // The CardView surface treatment: raised cell + hairline; today gets the accent ring.
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.cardSurface)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isToday ? Color.accentColor : Color.surfaceHairline,
                                  lineWidth: isToday ? 2 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .fill(targetedDay == day.date ? Color.accentColor.opacity(0.10) : .clear)
                    .allowsHitTesting(false)
            }
            // `.contain` + id is the proven card(_:) container shape — chip ids inside stay
            // queryable (CalendarViewUITests' membership queries depend on it).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.calendarDay(Self.isoDayFormatter.string(from: day.date)))
            .dropDestination(for: CardTransfer.self) { items, _ in
                drop(items, onto: day.date)
            } isTargeted: { targeting in
                if targeting {
                    targetedDay = day.date
                } else if targetedDay == day.date {
                    targetedDay = nil
                }
            }
        } else {
            // Adjacent-month filler: dimmed day number only — NO id, NO chips, NO drop
            // destination (see the type doc + AccessibilityID.calendarDay).
            Text("\(calendar.component(.day, from: day.date))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.quaternary)
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.insetSurface)
                }
        }
    }

    private func drop(_ items: [CardTransfer], onto day: Date) -> Bool {
        guard let transfer = items.first,
              let card = allCards.first(where: { $0.id == transfer.cardID }) else { return false }
        // Timed cards keep their wall-clock time on the new day; the guarded setDueDate makes a
        // same-day drop a store-level no-op (no junk undo step).
        store.setDueDate(
            CalendarReschedule.retargetedDueDate(original: card.dueDate,
                                                 includesTime: card.includesTime,
                                                 onto: day, calendar: calendar),
            on: card, includesTime: card.includesTime, durationMinutes: card.durationMinutes)
        return true
    }

    // MARK: - Chips

    private func chipView(_ card: Card) -> some View {
        HStack(spacing: 4) {
            if card.includesTime, let dueDate = card.dueDate {
                // Visible time is locale-appropriate ("2:00 PM"/"14:00"); the WIRE time in the
                // representation below is POSIX HH:mm — the DueDateBadge visible/wire split.
                Text(Self.chipTimeFormatter.string(from: dueDate))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(card.title)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(selectedCardID == card.id ? Color.accentColor.opacity(0.10) : Color.insetSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(selectedCardID == card.id ? Color.accentColor.opacity(0.8) : Color.surfaceHairline,
                              lineWidth: selectedCardID == card.id ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        // The CardView/CardListRow click grammar: first click selects immediately, double-click
        // opens (`.simultaneously`, not `.exclusively` — no selection lag).
        .gesture(
            TapGesture(count: 2).onEnded { selectedDetailCard = card }
                .simultaneously(with: TapGesture(count: 1).onEnded { selectedCardID = card.id })
        )
        // Representation Text (NOT .accessibilityValue — empty under XCUITest on macOS, the M6
        // finding): value "<HH:mm>|<title>" for timed cards, "<title>" otherwise. AX-only — the
        // real view underneath keeps its gestures and drag source (XCUITest drives both by
        // frame coordinates). If a live run ever shows the representation eating clicks/drags,
        // fall back to `.accessibilityElement(children: .combine)` + a POSIX-visible time — but
        // try the badge-proven representation first.
        .accessibilityRepresentation {
            Text(chipWireValue(card))
                .accessibilityIdentifier(AccessibilityID.calendarChip(card.title))
        }
        .draggable(CardTransfer(cardID: card.id))
        // The CardListRow v1 menu: Open + Delete only (moving between LISTS lives on the canvas;
        // moving between DAYS is the drag).
        .contextMenu {
            Button("Open Card") { selectedDetailCard = card }
            Button("Delete Card", role: .destructive) { deleteCard(card) }
        }
    }

    private func chipWireValue(_ card: Card) -> String {
        guard card.includesTime, let dueDate = card.dueDate else { return card.title }
        return "\(Self.wireTimeFormatter.string(from: dueDate))|\(card.title)"
    }

    // MARK: - No Date rail

    /// The undated cards, always visible beside the grid (per the M-D scope decision: a calendar
    /// that silently hides undated cards would lie about the board). Omitted entirely only when
    /// EMPTY — the M-C empty-buckets-omitted posture.
    private var noDateRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("No Date")
                    .font(.headline)
                Text("\(undatedCards.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // Header is a SIBLING of the rows (the listSection discipline).
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.calendarNoDateHeader)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(undatedCards) { card in
                        CalendarNoDateRow(
                            card: card,
                            isSelected: selectedCardID == card.id,
                            onSelect: { selectedCardID = card.id },
                            onOpen: { selectedDetailCard = card },
                            onDelete: { deleteCard(card) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    // MARK: - M8: theme (verbatim from BoardView)

    private var themeBackground: Color {
        switch ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex) {
        case .preset(let theme): theme.backgroundColor
        // Custom hex is a WASH like every preset — see BoardView.themeBackground.
        case .custom(let color): color.opacity(0.15)
        }
    }

    // MARK: - Card partitions

    /// Flatten order (list-position-then-card-position), the M-C rule: collapse is board-canvas
    /// layout state, never a data filter, and there is no label filter here (`canFilter: false`).
    private var allCards: [Card] {
        board.sortedLists.flatMap { $0.sortedCards }
    }

    /// Dated cards keyed by their LOCAL start-of-day (chip order within a day = flatten order).
    private var cardsByDay: [Date: [Card]] {
        var map: [Date: [Card]] = [:]
        for card in allCards {
            guard let dueDate = card.dueDate else { continue }
            map[calendar.startOfDay(for: dueDate), default: []].append(card)
        }
        return map
    }

    private var undatedCards: [Card] {
        allCards.filter { $0.dueDate == nil }
    }

    // MARK: - Selection + command surface

    /// The live `Card` for the current selection (nil when none / stale — a stale id degrades to
    /// "no selection" everywhere).
    private var selectedCard: Card? {
        guard let selectedCardID else { return nil }
        return allCards.first { $0.id == selectedCardID }
    }

    /// Calendar-mode command surface. REAL: selection (`selectedCard`), ⌘O open, ⌘⌫ delete.
    /// HONESTLY DISABLED, all via published `false` flags rather than enabled-but-inert items:
    /// `canCreateCard`/`canCreateList` (no canvas to open an inline editor on), Card ▸ Move
    /// Left/Right/Up/Down (`canMoveSelectedCard` false everywhere + `canMoveCards: false` — day
    /// membership is the drag's job, not ⌘-arrows'), `canFilter: false` (no label filter here),
    /// and — new in M-D — `canNavigateSelection: false`: `moveSelection` is a NO-OP closure
    /// because calendar v1 has no arrow-key selection model (a month grid wants 2D day-cell
    /// navigation, not the card-list walk), and the four View-menu arrow items disable honestly
    /// instead of firing that no-op. ⌘N / File ▸ New Tack Window keeps the deliberate M-C
    /// fall-through exception (see ListBoardView.boardActions).
    private var boardActions: BoardActions {
        BoardActions(
            selectedCard: selectedCard,
            newCard: {},
            canCreateCard: false,
            newList: {},
            deleteSelectedCard: deleteSelectedCard,
            openSelectedCard: openSelectedCard,
            moveSelectedCard: { _ in },
            moveSelection: { _ in }, // v1 no-op by design — gated by canNavigateSelection below
            canMoveSelectedCard: { _ in false },
            toggleLabelFilterBar: {},
            canFilter: false,
            canMoveCards: false,
            canCreateList: false,
            canNavigateSelection: false
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

    /// Chip/rail context-menu delete: nil the selection FIRST if it's the deleted card (the
    /// CardView discipline), then one store call — NOT undoable since M-E (see BoardStore.deleteCard).
    private func deleteCard(_ card: Card) {
        if selectedCardID == card.id { selectedCardID = nil }
        store.deleteCard(card)
    }

    // MARK: - Formatters

    /// POSIX + LOCAL time zone for cell ids — byte-matching CalendarViewUITests' formatter and
    /// the DueDateBadge.isoDateFormatter rationale (dueDate is stored as LOCAL start-of-day).
    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static let wireMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = .current
        return formatter
    }()

    /// Locale-appropriate short time for the VISIBLE chip prefix (DueDateBadge.shortTimeFormatter).
    private static let chipTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Machine-readable 24-hour "HH:mm" for the chip wire value — POSIX-pinned for the same
    /// reason as DueDateBadge.wireTimeFormatter (the 12/24-hour system preference rewrites even
    /// explicit dateFormats).
    private static let wireTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter
    }()
}

/// One No-Date rail row: title + label dots — CardListRow's surface/selection/click grammar
/// minus the list name and due badge (an undated card has no badge by definition), plus a drag
/// source: dragging a rail row onto a day cell gives the card that date (nil-original
/// `CalendarReschedule` path). Plain `Text` title — no text inputs in this milestone.
private struct CalendarNoDateRow: View {
    let card: Card
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    /// Ordered by `LabelColor.allCases`, not insertion order — same as CardView/CardListRow.
    private var sortedLabelColors: [LabelColor] {
        let owned = Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) })
        return LabelColor.allCases.filter { owned.contains($0) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(card.title)
                .lineLimit(1)
                .truncationMode(.tail)
            if !sortedLabelColors.isEmpty {
                HStack(spacing: 4) {
                    ForEach(sortedLabelColors, id: \.self) { color in
                        Circle()
                            .fill(color.swatchColor)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.cardSurface)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color.surfaceHairline,
                              lineWidth: isSelected ? 1.5 : 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.10)
                      : isHovering ? Color.primary.opacity(0.045) : .clear)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(
            TapGesture(count: 2).onEnded { onOpen() }
                .simultaneously(with: TapGesture(count: 1).onEnded { onSelect() })
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.calendarNoDateRow(card.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .draggable(CardTransfer(cardID: card.id))
        .contextMenu {
            Button("Open Card") { onOpen() }
            Button("Delete Card", role: .destructive) { onDelete() }
        }
    }
}

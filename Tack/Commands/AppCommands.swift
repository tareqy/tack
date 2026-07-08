import SwiftUI
import AppKit

/// The menu-bar command layer — the single source of truth for every P0 keyboard shortcut, each
/// with a visible, discoverable menu item (PRD v1.1). Attached to the `WindowGroup` scene (NOT
/// nested in any view: the M3 trap is that toolbars/commands contributed from a split-view column
/// vanish into overflow / never register).
///
/// Commands read the exported focus state (`boardActions` from BoardView, `boardSelectionActions`
/// from RootView) and call store methods through those closures. They NEVER touch undo
/// registration directly — undo/redo is the system Edit-menu pair, wired via `modelContext.undoManager`.
struct AppCommands: Commands {
    @FocusedValue(\.boardActions) private var boardActions
    @FocusedValue(\.boardSelectionActions) private var boardSelection
    @FocusedValue(\.textInputFocused) private var textInputFocused

    var body: some Commands {
        // MARK: File — placed BEFORE the system "New … Window" item so ⌘N resolves to New Card
        // when a board is on screen (first enabled key-equivalent match wins), while a disabled
        // New Card (no board) falls through to the still-present New Window item, keeping the
        // test harness's window-opening path intact.
        CommandGroup(before: .newItem) {
            Button("New Card") { boardActions?.newCard() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(boardActions == nil || boardActions?.canCreateCard == false)

            Button("New List") { boardActions?.newList() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(boardActions == nil)

            Button("New Board") { guardedMutation { boardSelection?.newBoard() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(boardSelection == nil)

            Divider()

            // E-01 (⇧⌘E): export every board to JSON via the save panel (hosted by RootView).
            // Enabled whenever at least one board exists; routed through `guardedMutation` so the
            // panel is never presented from a typing context or beneath an open card-detail sheet.
            Button("Export All Boards…") { guardedMutation { boardSelection?.exportAllBoards() } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(boardSelection?.boardNames.isEmpty != false)

            // E-02 (⇧⌘I): import a JSON backup via the open panel (hosted by RootView, same
            // constraint as the exporter). Enabled whenever RootView publishes the surface —
            // including with zero boards (restore-into-empty is the headline case).
            Button("Import Boards…") { guardedMutation { boardSelection?.importBoards() } }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(boardSelection == nil)

            Divider()
        }

        // MARK: Edit — Delete Card (no dialog, undoable). System Undo/Redo are left untouched.
        CommandGroup(after: .pasteboard) {
            Button("Delete Card") { guardedMutation { boardActions?.deleteSelectedCard() } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)
        }

        // MARK: Card — open the detail sheet + move the selected card with ⌘-arrows.
        CommandMenu("Card") {
            // ⌘O opens the selected card's detail sheet. Gated EXACTLY like Delete Card (a card
            // must be selected, and not while typing / beneath a sheet) so it can never open the
            // sheet for a card the user can't currently see acting on.
            Button("Open Card") { guardedMutation { boardActions?.openSelectedCard() } }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)

            Divider()

            Button("Move Card Up") { guardedMutation { boardActions?.moveSelectedCard(.up) } }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)

            Button("Move Card Down") { guardedMutation { boardActions?.moveSelectedCard(.down) } }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)

            Divider()

            Button("Move Card Left") { guardedMutation { boardActions?.moveSelectedCard(.left) } }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!(boardActions?.canMoveSelectedCard(.left) ?? false) || isTextInputActive)

            Button("Move Card Right") { guardedMutation { boardActions?.moveSelectedCard(.right) } }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!(boardActions?.canMoveSelectedCard(.right) ?? false) || isTextInputActive)
        }

        // MARK: View — sidebar toggle + selection navigation (bare arrows) + board switching
        // (⌘1–⌘9). NavigationSplitView does NOT auto-add a View-menu sidebar item here (only a
        // toolbar button — confirmed via an accessibility dump), so we contribute a discoverable
        // "Toggle Sidebar" that drives the underlying NSSplitViewController's standard action.
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Divider()

            // M11 (LB-03): the label filter bar. Gated like New Card/List (no board ⇒ nothing to
            // filter) PLUS the text-input guard, per the established pattern — toggling the bar
            // while an inline editor is focused would rearrange the board behind the caret. Esc
            // (hide + clear) is deliberately NOT a Commands item here — empirically, a bare
            // (no-modifier) `.keyboardShortcut(.escape, modifiers: [])` Button never fires (⌘F
            // above works; a live UI run proved plain Escape does not — see the LabelFilterUITests
            // debugging note). `BoardView` instead uses `.onExitCommand`, the SAME mechanism every
            // OTHER Esc-cancel in this app already uses (inline rename/add-card/add-list fields,
            // the card-detail sheet) — none of which have a menu item either, so this isn't a
            // departure from convention, it's following it. That mechanism is responder-chain
            // based, which is exactly what gives it "Esc in an editor keeps its cancel semantics"
            // for free: a focused field's OWN `.onExitCommand` sits closer to the first responder
            // and wins before BoardView's ever sees the key.
            Button("Filter by Label") { guardedMutation { boardActions?.toggleLabelFilterBar() } }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(boardActions == nil || isTextInputActive)

            Divider()

            // Bare arrows are gated on the text-input guard too (same hole family as ⌘⌫): while an
            // inline editor is focused, an enabled item would swallow ↑/↓ typed in the field, and
            // disabling it instead lets the key fall through to the text caret. Enablement keys off
            // `boardActions != nil` (a board is shown), NOT `selectedCard != nil`: with no
            // selection, ↓/↑ is the keyboard ENTRY point — `SelectionNavigation.next` maps a nil
            // selection to the first card of the first non-empty list (an unreachable branch while
            // this was gated on an existing selection).
            Button("Select Previous Card") { guardedMutation { boardActions?.moveSelection(.up) } }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive)

            Button("Select Next Card") { guardedMutation { boardActions?.moveSelection(.down) } }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive)

            // PRD C-10 promises selection navigation in all four directions; left/right complete
            // the pair started by up/down above (same gating, same `moveSelection` entry point —
            // `SelectionNavigation.next` already implements `.left`/`.right`, same-row-index into
            // the neighbouring non-empty list, clamped, skipping collapsed/empty lists).
            Button("Select Card Left") { guardedMutation { boardActions?.moveSelection(.left) } }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive)

            Button("Select Card Right") { guardedMutation { boardActions?.moveSelection(.right) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive)

            Divider()

            ForEach(1...9, id: \.self) { position in
                Button(boardTitle(position)) { guardedMutation { boardSelection?.selectBoard(position) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(position)")), modifiers: .command)
                    .disabled(position > (boardSelection?.boardNames.count ?? 0))
            }
        }
    }

    private func boardTitle(_ position: Int) -> String {
        let names = boardSelection?.boardNames ?? []
        if position <= names.count { return "\(position)  \(names[position - 1])" }
        return "Board \(position)"
    }

    // MARK: - Text-input guard

    /// True while any tagged text-input view holds keyboard focus (see
    /// `FocusedValues.textInputFocused` / `reportsTextInputFocus()` — applied to every
    /// TextField/TextEditor in the app: inline add-card/add-list/rename editors, the board sheets'
    /// fields, the sidebar filter, the card-detail fields). Gating the mutating card commands on
    /// this means ⌘⌫ / ⌘-arrows can never mutate the card behind an open editor while the user is
    /// typing — macOS matches menu key-equivalents BEFORE the key window's responder chain, so
    /// without it an enabled ⌘⌫ deletes the selected card behind the field's back.
    ///
    /// Chosen over the classic responder-chain check (`firstResponder is NSTextView`) on EVIDENCE:
    /// on this macOS/SwiftUI version the first responder is a private `SwiftUI.KeyViewProxy` — not
    /// an `NSTextView`, not an `NSTextInputClient`, with a nil `inputContext` — and it is the first
    /// responder EVEN WHEN NO EDITOR IS OPEN, so no responder-chain predicate can discriminate a
    /// typing context (verified via responder dumps from inside the running app under --uitest).
    /// A focused value is also the change signal SwiftUI Commands reliably re-evaluate enablement
    /// on, which raw responder changes are not.
    private var isTextInputActive: Bool {
        textInputFocused == true
    }

    /// Belt-and-suspenders with the `.disabled(... || isTextInputActive)` gate: menu enablement is
    /// only as fresh as the last Commands re-evaluation, so the flag could in principle be stale at
    /// the instant a key-equivalent is matched. Re-checking inside the action guarantees the
    /// mutation can never fire from a typing context. The additional `keyWindow.isSheet` check
    /// covers a sheet that is open WITHOUT any of its fields focused (e.g. CreateBoardSheet just
    /// presented): key equivalents still match app menus while a sheet is key, and a card mutation
    /// behind a modal sheet is never right. It lives here (not in `.disabled`) deliberately —
    /// AppKit window state is not a signal SwiftUI re-evaluates Commands on, and a stale DISABLED
    /// item after sheet dismissal would be a worse failure mode than a no-op action.
    private func guardedMutation(_ mutation: () -> Void) {
        guard !isTextInputActive, NSApp.keyWindow?.isSheet != true else { return }
        mutation()
    }
}

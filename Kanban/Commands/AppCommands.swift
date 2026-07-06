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
                .disabled(boardActions == nil)

            Button("New List") { boardActions?.newList() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(boardActions == nil)

            Button("New Board") { boardSelection?.newBoard() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(boardSelection == nil)

            Divider()
        }

        // MARK: Edit — Delete Card (no dialog, undoable). System Undo/Redo are left untouched.
        CommandGroup(after: .pasteboard) {
            Button("Delete Card") { guardedMutation { boardActions?.deleteSelectedCard() } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)
        }

        // MARK: Card — move the selected card with ⌘-arrows.
        CommandMenu("Card") {
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

            // Bare arrows are gated on the text-input guard too (same hole family as ⌘⌫): while an
            // inline editor is focused, an enabled item would swallow ↑/↓ typed in the field, and
            // disabling it instead lets the key fall through to the text caret.
            Button("Select Previous Card") { guardedMutation { boardActions?.moveSelection(.up) } }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)

            Button("Select Next Card") { guardedMutation { boardActions?.moveSelection(.down) } }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)

            Divider()

            ForEach(1...9, id: \.self) { position in
                Button(boardTitle(position)) { boardSelection?.selectBoard(position) }
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

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
            Button("Delete Card") { boardActions?.deleteSelectedCard() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil)
        }

        // MARK: Card — move the selected card with ⌘-arrows.
        CommandMenu("Card") {
            Button("Move Card Up") { boardActions?.moveSelectedCard(.up) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil)

            Button("Move Card Down") { boardActions?.moveSelectedCard(.down) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil)

            Divider()

            Button("Move Card Left") { boardActions?.moveSelectedCard(.left) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!(boardActions?.canMoveSelectedCard(.left) ?? false))

            Button("Move Card Right") { boardActions?.moveSelectedCard(.right) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!(boardActions?.canMoveSelectedCard(.right) ?? false))
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

            Button("Select Previous Card") { boardActions?.moveSelection(.up) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(boardActions?.selectedCard == nil)

            Button("Select Next Card") { boardActions?.moveSelection(.down) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(boardActions?.selectedCard == nil)

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
}

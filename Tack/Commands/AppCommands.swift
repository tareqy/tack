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
        // MARK: App menu — replace the stock "About Tack" so the standard AppKit About panel
        // carries a credits line. The panel still shows the app name/icon and the version
        // (derived from CFBundleShortVersionString / CFBundleVersion — project.yml's
        // MARKETING_VERSION / CURRENT_PROJECT_VERSION) natively; we only supply `.credits`.
        CommandGroup(replacing: .appInfo) {
            Button("About Tack") { Self.showAboutPanel() }
        }

        // MARK: File — placed BEFORE the system "New … Window" item so ⌘N resolves to New Card
        // when a board is on screen (first enabled key-equivalent match wins), while a disabled
        // New Card (no board) falls through to the still-present New Window item, keeping the
        // test harness's window-opening path intact.
        CommandGroup(before: .newItem) {
            Button("New Card") { guardedMutation { boardActions?.newCard() } }
                .keyboardShortcut("n", modifiers: .command)
                // Deliberately remain enabled while an inspector text field is focused: the
                // guarded action consumes ⌘N as a no-op. Disabling this first key-equivalent
                // would let ⌘N fall through to the system New Tack Window item below it. The
                // focus exception also covers List/Calendar and all-collapsed Board states where
                // card creation is normally unavailable.
                .disabled(boardActions == nil
                          || (boardActions?.canCreateCard == false && !isTextInputActive))

            Button("New List") { guardedMutation { boardActions?.newList() } }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(boardActions == nil || boardActions?.canCreateList == false || isTextInputActive)

            // Ellipsis: opens the naming sheet — further input before anything is created (HIG).
            Button("New Board…") { guardedMutation { boardSelection?.newBoard() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(boardSelection == nil)

            Divider()

            // E-01 (⇧⌘E): export every board to JSON via the save panel (hosted by RootView).
            // Enabled whenever at least one board exists; routed through `guardedMutation` so the
            // panel is never presented from a typing context or beneath an open card-detail sheet.
            // Both items also gray out while a text editor has focus — `guardedMutation` already
            // swallowed the action in that state, but an enabled-looking item whose click silently
            // no-ops is a trap for the mouse path (found in E-02's manual gate via the sidebar filter).
            Button("Export All Boards…") { guardedMutation { boardSelection?.exportAllBoards() } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(boardSelection?.boardNames.isEmpty != false || isTextInputActive)

            // E-02 (⇧⌘I): import a JSON backup via the open panel (hosted by RootView, same
            // constraint as the exporter). Enabled whenever RootView publishes the surface —
            // including with zero boards (restore-into-empty is the headline case).
            Button("Import Boards…") { guardedMutation { boardSelection?.importBoards() } }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(boardSelection == nil || isTextInputActive)

            Divider()
        }

        // MARK: Edit — Delete Card (no dialog; NOT undoable since M-E — see
        // BoardStore.deleteCard). System Undo/Redo are left untouched.
        CommandGroup(after: .pasteboard) {
            Button("Delete Card") { guardedMutation { boardActions?.deleteSelectedCard() } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)
        }

        // MARK: Card — open the configured detail presentation + move with ⌘-arrows.
        CommandMenu("Card") {
            // ⌘O opens the selected card's configured detail presentation. Gated EXACTLY like
            // Delete Card (a card must be selected, and not while typing / beneath a modal sheet)
            // so it can never open a card the user can't currently see acting on.
            Button("Open Card") { guardedMutation { boardActions?.openSelectedCard() } }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive)

            Divider()

            Button("Move Card Up") { guardedMutation { boardActions?.moveSelectedCard(.up) } }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive
                          || boardActions?.canMoveCards == false)

            Button("Move Card Down") { guardedMutation { boardActions?.moveSelectedCard(.down) } }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(boardActions?.selectedCard == nil || isTextInputActive
                          || boardActions?.canMoveCards == false)

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
            // "Show/Hide" (state-revealing vocabulary) rather than the programmer-y "Toggle";
            // static because the split view's visibility isn't observable from a Commands value.
            Button("Show/Hide Sidebar") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Divider()

            // M-C/M-D: per-board view mode. Sentence-style titles under the View menu ("View as
            // Board"). ⌥⌘B / ⌥⌘L / ⌥⌘C — all free in the shortcut table (⌘1–9, ⌘N-family,
            // ⇧⌘E/I, ⌃⌘S, ⌘F, ⌘O, ⌘-arrows and bare arrows are all taken; these three are not).
            // ⌥⌘C specifically: the only system claimant is Format ▸ "Copy Style", and Tack has
            // no Format menu (no TextFormattingCommands installed) — verified by grepping every
            // `keyboardShortcut` in the app (only sheet default/cancel actions outside this
            // file) and by walking the running app's menus; the human checklist re-confirms no
            // duplicate-shortcut beep. Enabled whenever boards exist; `setViewMode` itself
            // no-ops without a selected board (the `guardedMutation` belt-and-suspenders
            // posture New Board already uses).
            Button("as Board") { guardedMutation { boardSelection?.setViewMode(.board) } }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(boardSelection == nil || boardSelection?.boardNames.isEmpty == true)

            Button("as List") { guardedMutation { boardSelection?.setViewMode(.list) } }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(boardSelection == nil || boardSelection?.boardNames.isEmpty == true)

            Button("as Calendar") { guardedMutation { boardSelection?.setViewMode(.calendar) } }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(boardSelection == nil || boardSelection?.boardNames.isEmpty == true)

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
                .disabled(boardActions == nil || boardActions?.canFilter == false || isTextInputActive)

            Divider()

            // Bare arrows are gated on the text-input guard too (same hole family as ⌘⌫): while an
            // inline editor is focused, an enabled item would swallow ↑/↓ typed in the field, and
            // disabling it instead lets the key fall through to the text caret. Enablement keys off
            // `boardActions != nil` (a board is shown), NOT `selectedCard != nil`: with no
            // selection, ↓/↑ is the keyboard ENTRY point — `SelectionNavigation.next` maps a nil
            // selection to the first card of the first non-empty list (an unreachable branch while
            // this was gated on an existing selection).
            // M-D: canNavigateSelection honestly disables all four in calendar mode, which has no
            // arrow-key selection model in v1.
            Button("Select Previous Card") { guardedMutation { boardActions?.moveSelection(.up) } }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive
                          || boardActions?.canNavigateSelection == false)

            Button("Select Next Card") { guardedMutation { boardActions?.moveSelection(.down) } }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive
                          || boardActions?.canNavigateSelection == false)

            // PRD C-10 promises selection navigation in all four directions; left/right complete
            // the pair started by up/down above (same gating, same `moveSelection` entry point —
            // `SelectionNavigation.next` already implements `.left`/`.right`, same-row-index into
            // the neighbouring non-empty list, clamped, skipping collapsed/empty lists).
            Button("Select Card Left") { guardedMutation { boardActions?.moveSelection(.left) } }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive
                          || boardActions?.canNavigateSelection == false)

            Button("Select Card Right") { guardedMutation { boardActions?.moveSelection(.right) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(boardActions == nil || isTextInputActive
                          || boardActions?.canNavigateSelection == false)

            Divider()

            ForEach(1...9, id: \.self) { position in
                Button(boardTitle(position)) { guardedMutation { boardSelection?.selectBoard(position) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(position)")), modifiers: .command)
                    .disabled(position > (boardSelection?.boardNames.count ?? 0))
            }
        }
    }

    // MARK: - About panel

    /// Presents the standard AppKit About panel with a custom credits line. The panel renders the
    /// app name, icon, and version (`Version <short> (<build>)`) from the bundle itself; the only
    /// thing we override is the credits block below the version.
    private static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Developed by Tareq Yaghmour and Claude",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
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

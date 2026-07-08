import SwiftUI

/// The "Theme" toolbar button (M8): a popover with the 6 `BoardTheme` preset swatches and a
/// custom-hex escape hatch. Hosted in `RootView`'s split-view-level toolbar, NOT contributed from
/// `BoardView`'s own body — same M3 finding as the "New Board" item (toolbars contributed from a
/// column body land in the overflow menu; see `RootView`'s toolbar comment). `RootView`
/// parameterizes this view with whichever board is currently shown in the detail pane.
///
/// All mutations go through `BoardStore.setTheme` — this view only stages the hex draft locally
/// (`hexDraft`, seeded from the board's current custom hex when the popover opens) until Enter
/// commits it. Invalid hex shows a subtle inline error and does NOT commit (`showsHexError`), per
/// the brief's "no crash, no commit" requirement. Picking a preset swatch commits immediately and
/// leaves the popover open (transient popover: outside click or Esc closes it).
///
/// M-A added the native ColorPicker well. The hex field remains the XCUITest-drivable path
/// (NSColorPanel cannot be driven synthetically); the well's commits are verified through the
/// board-theme-value marker + unit-tested ColorHexBridge.
struct ThemeButton: View {
    /// The board shown in the detail pane, or nil when none is selected — the toolbar item stays
    /// PRESENT either way (HIG: stable toolbar geometry) and merely disables on nil.
    let board: Board?
    let store: BoardStore

    @State private var isPresented = false
    @State private var hexDraft = ""
    @State private var showsHexError = false
    @State private var pickerColor: Color = .white
    /// The hex `pickerColor` was just seeded to, or nil once a genuine user pick has been seen this
    /// popover session. NSColorWell re-publishes its seeded value through `onChange` a moment after
    /// attaching (an AppKit-bridging echo, not a user pick — confirmed via NSLog: it fires ~seconds
    /// after seeding, sometimes mid-keystroke in the hex field) — without this guard that echo
    /// stomps `hexDraft` out from under a concurrent hex-field edit, corrupting it (observed
    /// "3A5F8F" typed into a seeded "C7C7C7" draft becoming "C7C7C73A5F8F", which then fails to
    /// parse and silently blocks the commit). Cleared on first real divergence so a later drag back
    /// to the original seed color still commits.
    @State private var pickerSeedHex: String?
    @State private var pendingPickerCommit: Task<Void, Never>?

    var body: some View {
        Button {
            guard let board else { return }
            hexDraft = board.customThemeHex ?? ""
            showsHexError = false
            let resolvedColor: Color
            switch ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex) {
            case .custom(let color):
                resolvedColor = color
            case .preset(let theme):
                resolvedColor = theme.swatchColor
            }
            pickerColor = resolvedColor
            pickerSeedHex = ColorHexBridge.hexString(from: resolvedColor)
            isPresented = true
        } label: {
            Label("Theme", systemImage: "paintpalette")
        }
        .disabled(board == nil)
        .help("Change board theme")
        .accessibilityIdentifier(AccessibilityID.themeButton)
        .popover(isPresented: $isPresented) {
            if let board {
                popoverContent(for: board)
            }
        }
    }

    private func popoverContent(for board: Board) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.headline)

            swatchGrid(for: board)

            Divider()

            customHexSection(for: board)
        }
        .padding(16)
        .frame(width: 260)
    }

    // MARK: - Presets

    private func swatchGrid(for board: Board) -> some View {
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(BoardTheme.allCases, id: \.self) { theme in
                swatch(for: theme, board: board)
            }
        }
    }

    private func swatch(for theme: BoardTheme, board: Board) -> some View {
        let selected = isSelected(theme, board: board)
        return Button {
            store.setTheme(board, themeName: theme.rawValue, customHex: nil)
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(theme.swatchColor)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
                    .overlay {
                        if selected {
                            // M10 dark-mode audit: was `.white`, measured (via screenshot pixel
                            // sampling) at contrast ratios as low as 1.84:1 against several swatch
                            // fills — see `BoardTheme.swatchColor`'s doc comment for the full
                            // measurement. `.black` passes WCAG's 3:1 graphical-object minimum
                            // against all 6 swatches in both appearances (every swatch is now a
                            // fully opaque, appearance-independent color).
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.black)
                        }
                    }
                Text(theme.displayName)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.themeSwatch(theme.rawValue))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A swatch shows selected only when it is the board's EFFECTIVE preset — i.e. no custom hex
    /// is currently overriding it (per `ThemeResolution`'s precedence).
    private func isSelected(_ theme: BoardTheme, board: Board) -> Bool {
        guard board.customThemeHex == nil else { return false }
        return (BoardTheme(rawValue: board.themeName) ?? .default) == theme
    }

    // MARK: - Custom hex

    private func customHexSection(for board: Board) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom")
                .font(.caption)
                .foregroundStyle(.secondary)

            ColorPicker("Custom color", selection: $pickerColor, supportsOpacity: false)
                .accessibilityIdentifier(AccessibilityID.themeColorWell)
                .onChange(of: pickerColor) { _, newColor in
                    guard let hex = ColorHexBridge.hexString(from: newColor) else { return }
                    if let seedHex = pickerSeedHex, hex == seedHex {
                        // The seed echo described above — not a user pick. Swallow it.
                        return
                    }
                    pickerSeedHex = nil
                    guard hex != board.customThemeHex else { return }
                    hexDraft = hex
                    showsHexError = false
                    // NSColorPanel has no "done" event and its wheel fires continuously;
                    // debounce so a drag settles into ONE setTheme = one undo step.
                    pendingPickerCommit?.cancel()
                    pendingPickerCommit = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        store.setTheme(board, themeName: board.themeName, customHex: hex)
                    }
                }

            TextField("#RRGGBB", text: $hexDraft)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .onSubmit { commitHex(for: board) }
                .accessibilityIdentifier(AccessibilityID.themeHexField)

            if showsHexError {
                Text("Not a valid hex color")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Invalid hex shows the inline error and returns WITHOUT calling the store — no commit, no
    /// crash. `themeName` is passed back unchanged (the board's current value): committing a
    /// custom hex must not silently reassign which preset a later "choose a swatch" action starts
    /// from.
    private func commitHex(for board: Board) {
        guard HexColor.parse(hexDraft) != nil else {
            showsHexError = true
            return
        }
        showsHexError = false
        store.setTheme(board, themeName: board.themeName, customHex: hexDraft)
    }
}

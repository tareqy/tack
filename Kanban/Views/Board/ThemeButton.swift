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
/// The brief's optional `ColorPicker` is deliberately skipped: the hex field is the testable path,
/// and per the brief's own escape hatch the picker is a nice-to-have only.
struct ThemeButton: View {
    let board: Board
    let store: BoardStore

    @State private var isPresented = false
    @State private var hexDraft = ""
    @State private var showsHexError = false

    var body: some View {
        Button {
            hexDraft = board.customThemeHex ?? ""
            showsHexError = false
            isPresented = true
        } label: {
            Label("Theme", systemImage: "paintpalette")
        }
        .accessibilityIdentifier(AccessibilityID.themeButton)
        .popover(isPresented: $isPresented) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.headline)

            swatchGrid

            Divider()

            customHexSection
        }
        .padding(16)
        .frame(width: 260)
    }

    // MARK: - Presets

    private var swatchGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(BoardTheme.allCases, id: \.self) { theme in
                swatch(for: theme)
            }
        }
    }

    private func swatch(for theme: BoardTheme) -> some View {
        let selected = isSelected(theme)
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
    private func isSelected(_ theme: BoardTheme) -> Bool {
        guard board.customThemeHex == nil else { return false }
        return (BoardTheme(rawValue: board.themeName) ?? .default) == theme
    }

    // MARK: - Custom hex

    private var customHexSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("#RRGGBB", text: $hexDraft)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .onSubmit(commitHex)
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
    private func commitHex() {
        guard HexColor.parse(hexDraft) != nil else {
            showsHexError = true
            return
        }
        showsHexError = false
        store.setTheme(board, themeName: board.themeName, customHex: hexDraft)
    }
}

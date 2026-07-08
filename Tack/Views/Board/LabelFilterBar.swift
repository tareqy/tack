import SwiftUI

/// The label filter bar (LB-03, M11): all 8 `LabelColor` chips + a "Clear" button, shown above the
/// board columns when toggled via ⌘F / View ▸ "Filter by Label" (see `BoardView`/`AppCommands`).
/// PURE VIEW STATE — mutates only the caller's `active` binding, exactly like `LabelPicker` mutates
/// its own staged selection; no `BoardStore` write ever happens here, and nothing here is
/// persisted. OR semantics (a card is visible if it has ANY active color) live in `LabelFilter`,
/// not this view — this is purely the toggle UI.
struct LabelFilterBar: View {
    @Binding var active: Set<LabelColor>

    var body: some View {
        // The surface hugs its chips (the old full-width slab read as a long, mostly-empty bar)
        // and shares the columns' inset/radius tokens instead of introducing a third panel style.
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(LabelColor.allCases, id: \.self) { color in
                    chip(for: color)
                }
                if !active.isEmpty {
                    Button("Clear") { active = [] }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier(AccessibilityID.filterClear)
                }
            }
            .padding(8)
            .background(Color.columnSurface, in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 0)
        }
    }

    /// The shared `LabelChipLabel` look (one definition with `LabelPicker`, so the capsule
    /// geometry and the M10-audited black-on-fill contrast can never drift between the two).
    private func chip(for color: LabelColor) -> some View {
        let isSelected = active.contains(color)
        return Button {
            toggle(color)
        } label: {
            LabelChipLabel(color: color, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.filterChip(color.rawValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("Filter by \(color.rawValue.capitalized)")
    }

    private func toggle(_ color: LabelColor) {
        if active.contains(color) {
            active.remove(color)
        } else {
            active.insert(color)
        }
    }
}

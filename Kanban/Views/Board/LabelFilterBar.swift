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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Same chip shape as `LabelPicker`'s (capsule + checkmark, `.black` foreground when filled) —
    /// including its M10 dark-mode contrast fix, which was measured against all 8 colors in both
    /// appearances and applies unchanged here.
    private func chip(for color: LabelColor) -> some View {
        let isSelected = active.contains(color)
        return Button {
            toggle(color)
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                }
                Text(color.rawValue.capitalized)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? color.swatchColor.opacity(0.85) : Color.clear))
            .overlay(Capsule().strokeBorder(color.swatchColor, lineWidth: isSelected ? 0 : 1.5))
            .foregroundStyle(isSelected ? Color.black : Color.primary)
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

import SwiftUI

/// The card-detail label toggles: one filled color circle per `LabelColor`, selection shown as
/// a checkmark + primary ring. Deliberately diverged (M-0 polish) from the shared
/// `LabelChipLabel` capsule that `LabelFilterBar` still uses — color-name text is dropped here,
/// so the color name MUST be re-attached as `.accessibilityLabel` (the visible `Text` used to
/// BE the accessible name) and is echoed as a `.help` tooltip for sighted hover.
struct LabelPicker: View {
    @Binding var selected: Set<LabelColor>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Labels")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(LabelColor.allCases, id: \.self) { color in
                    chip(for: color)
                }
            }
        }
    }

    private func chip(for color: LabelColor) -> some View {
        let isSelected = selected.contains(color)
        let name = color.rawValue.capitalized
        return Button {
            toggle(color)
        } label: {
            ZStack {
                Circle()
                    .fill(color.swatchColor)
                    .frame(width: 26, height: 26)
                if isSelected {
                    // Black checkmark on the filled swatch — matches LabelChipLabel's
                    // audited selected-state treatment (black on all 8 swatch colors).
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.black)
                }
            }
            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityIdentifier(AccessibilityID.labelChip(color.rawValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ color: LabelColor) {
        if selected.contains(color) {
            selected.remove(color)
        } else {
            selected.insert(color)
        }
    }
}

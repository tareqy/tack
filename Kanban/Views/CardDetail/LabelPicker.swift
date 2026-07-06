import SwiftUI

/// All 8 `LabelColor`s as toggle chips, in `LabelColor.allCases` order. Selected state is visible
/// (filled swatch + checkmark) vs unselected (outline only). Mutates ONLY the caller's staged
/// `Set<LabelColor>` binding — no store writes happen here (see `CardDetailView`, which commits the
/// whole staged edit through `BoardStore.applyCardEdits` on Save).
struct LabelPicker: View {
    @Binding var selected: Set<LabelColor>

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Labels")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(LabelColor.allCases, id: \.self) { color in
                    chip(for: color)
                }
            }
        }
    }

    private func chip(for color: LabelColor) -> some View {
        let isSelected = selected.contains(color)
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(isSelected ? color.swatchColor.opacity(0.85) : Color.clear))
            .overlay(Capsule().strokeBorder(color.swatchColor, lineWidth: isSelected ? 0 : 1.5))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
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

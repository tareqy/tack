import SwiftUI
import AppKit

/// The app's small shared design vocabulary: semantic surface colors, the hover button style, and
/// the label-chip look. Spacing follows a 4/8/12/16/20 rhythm applied inline at call sites.
///
/// Surfaces deliberately come from AppKit's semantic fill palette (not hand-tuned
/// `secondary.opacity(...)` washes): the system tunes these per appearance, so the raised-card /
/// recessed-column relationship holds in BOTH light and dark mode by construction. The one color
/// the system doesn't provide — a card surface that reads as raised paper over a tinted board in
/// light mode AND as a lifted panel in dark mode — is expressed with the same no-asset-catalog
/// `NSColor(name:dynamicProvider:)` pattern as `Color.dueDateAmber`.
extension Color {
    /// The raised card surface: opaque control-background white in light mode (a card over the
    /// tinted board, Trello-style), a translucent lift above the column fill in dark mode.
    static let cardSurface = Color(nsColor: NSColor(name: NSColor.Name("CardSurface")) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor.controlBackgroundColor
    })

    /// Recessed panel fill for columns, collapsed pills, and the filter bar.
    static let columnSurface = Color(nsColor: .quinarySystemFill)

    /// Slightly stronger inset fill for field wells (sidebar filter, description well).
    static let insetSurface = Color(nsColor: .quaternarySystemFill)

    /// Hairline border that separates a card from whatever it sits on, in both appearances.
    static let surfaceHairline = Color.primary.opacity(0.08)
}

/// Quiet hover/pressed feedback for the plain-button affordances (Add Card, Add List, collapse
/// chevrons): invisible at rest, a soft primary wash under the pointer, slightly deeper while
/// pressed, with the label stepping from secondary to primary. No animation — hover feedback on
/// macOS is instant (Finder, Notes).
struct HoverHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlightBody(configuration: configuration)
    }

    private struct HoverHighlightBody: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.07 : 0)))
                )
                .onHover { isHovered = $0 }
        }
    }
}

/// The label-chip look for the board's `LabelFilterBar` (text capsule + checkmark). The
/// card-detail `LabelPicker` deliberately diverged in the M-0 polish to color-circle-only
/// swatches — if a third chip consumer ever appears, pick which of the two looks it shares
/// instead of minting a fourth.
struct LabelChipLabel: View {
    let color: LabelColor
    let isSelected: Bool
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 4) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
            }
            Text(color.rawValue.capitalized)
                .font(.caption)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(isSelected ? color.swatchColor : Color.clear))
        .overlay(Capsule().strokeBorder(color.swatchColor, lineWidth: isSelected ? 0 : 1.5))
        .foregroundStyle(isSelected ? Color.black : Color.primary)
    }
}

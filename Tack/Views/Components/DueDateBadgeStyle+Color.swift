import SwiftUI
import AppKit

/// Maps the pure `BadgeRole` (see `Store/DueDateBadgeStyle.swift`) onto concrete SwiftUI colors for
/// `DueDateBadge` — the same "pure model, SwiftUI-flavored `Color` extension in Views/" split
/// `LabelColor`/`LabelColor+Swatch` already establishes.
///
/// Every badge uses ONE role color at two strengths: a low-opacity tint for the capsule background
/// (echoing the tint-over-surface treatment `BoardTheme.backgroundColor` already uses) and the same
/// color at full strength for the text, which reliably keeps text readable against its own tint in
/// both appearances without a bespoke per-role dark-mode branch.
///
/// `.red`/`.orange`/`.gray` are macOS's own context-dependent system colors (backed by
/// `NSColor.systemRed`/`systemOrange`/`systemGray`), which already retune their exact hue/lightness
/// between light and dark for contrast — the identical reasoning `BoardTheme`'s preset washes rely
/// on, verified again here via the M10 screenshot inspection (see task-12 report). `.notice` (due
/// tomorrow) has no system "amber" counterpart, so it is the one role that needs an EXPLICIT
/// per-appearance value — see `Color.dueDateAmber` below — chosen to stay visually distinct from
/// both `.warn`'s orange and plain yellow in both appearances.
extension BadgeRole {
    var backgroundColor: Color {
        color.opacity(0.22)
    }

    var foregroundColor: Color {
        switch self {
        // `.gray` text on a gray tint composited over the card surface measured well under the
        // 4.5:1 small-text minimum — the one role the M10 pass missed. `secondaryLabelColor` is
        // the appearance-tuned label color for exactly this "present but not urgent" register;
        // the capsule keeps the gray tint so neutral still reads as less urgent than the rest.
        case .neutral: Color(nsColor: .secondaryLabelColor)
        default: color
        }
    }

    private var color: Color {
        switch self {
        case .alert: .red
        case .warn: .orange
        case .notice: .dueDateAmber
        case .neutral: .gray
        // Never actually rendered: `DueDateBadge` only exists for a non-nil due date, so `.hidden`
        // is unreachable in practice (see `BadgeRole.hidden`'s doc comment). `.secondary` is a
        // harmless, already-legible fallback should that ever change.
        case .hidden: .secondary
        }
    }
}

extension Color {
    /// A dedicated amber for the "due tomorrow" badge role — deliberately NOT `.yellow` (too close
    /// to the `.notice` role's own historical shade and to warning-light "caution" yellow, and low
    /// contrast against light backgrounds) and distinguishable at a glance from `.warn`'s orange.
    ///
    /// The project has no `Assets.xcassets` catalog (every resource is code, per `project.yml`), so
    /// this is expressed as a dynamic `NSColor(name:dynamicProvider:)` rather than an asset-catalog
    /// color set — the documented no-asset-catalog way to get an `NSAppearance`-aware color. A FIXED
    /// single RGB triplet was rejected: picked light enough to read on a light capsule tint, it
    /// under-contrasts on a dark one, and vice versa, so the two appearances need genuinely
    /// different values (mirroring why system colors like `.systemOrange` ship two tuned values of
    /// their own).
    static let dueDateAmber = Color(nsColor: NSColor(name: NSColor.Name("DueDateAmber")) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            // Bright, warm gold — reads clearly against a dark capsule tint without glare.
            ? NSColor(srgbRed: 1.00, green: 0.80, blue: 0.32, alpha: 1.0)
            // Deep goldenrod — dark enough to hold contrast on a near-white tint.
            : NSColor(srgbRed: 0.72, green: 0.48, blue: 0.02, alpha: 1.0)
    })
}

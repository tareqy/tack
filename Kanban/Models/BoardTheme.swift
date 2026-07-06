import Foundation
import SwiftUI

/// The 6 preset board themes (PRD Phase B / B-04) plus the escape hatch to a custom hex color
/// (see `ThemeResolution`). `Board.themeName` stores the raw value of one of these cases — or an
/// unrecognized string, which `ThemeResolution.resolve` treats as `.default` — and
/// `Board.customThemeHex`, when present and parseable, always wins over the preset.
///
/// Every `backgroundColor` is a low-opacity tint OVER the system's own dynamic window background
/// rather than a fixed asset-catalog color pair: blending at low alpha with whatever's underneath
/// keeps every preset legible in both light and dark for free, without a dedicated dark-mode pass
/// (M10 does the full audit; these are deliberately conservative in the meantime).
enum BoardTheme: String, CaseIterable, Codable {
    case `default`
    case ocean
    case forest
    case sunset
    case lavender
    case graphite

    /// The translucent wash applied to the board surface. `.default` is `.clear` — i.e. no tint,
    /// preserving the exact pre-M8 look — so existing/legacy boards (schema default `"default"`)
    /// are visually unchanged.
    var backgroundColor: Color {
        switch self {
        case .default: .clear
        case .ocean: Color.blue.opacity(0.12)
        case .forest: Color.green.opacity(0.12)
        case .sunset: Color.orange.opacity(0.14)
        case .lavender: Color.purple.opacity(0.12)
        case .graphite: Color.gray.opacity(0.16)
        }
    }

    /// A fully-opaque, more saturated stand-in used ONLY for the theme popover's swatch preview
    /// dots. `backgroundColor` is deliberately near-transparent (so it can wash over the board
    /// surface without fighting legibility), which would make a swatch preview read as blank; this
    /// gives each preset a legible, clickable dot instead. `.default` renders as a neutral gray dot
    /// rather than fully invisible.
    ///
    /// M10 dark-mode audit: `.default` was `Color.gray.opacity(0.3)` — a TRANSLUCENT wash, unlike
    /// every other case here, contradicting this property's own "fully-opaque" contract above. Being
    /// translucent meant it visually blended with whatever sat behind it (the popover's own
    /// light/dark-adaptive background), so its APPARENT color flipped from pale gray in light mode
    /// to near-black in dark mode — measured (via a real screenshot pixel sample) at contrast ratios
    /// of only 1.84:1 (light) / 2.87:1 (dark) against `ThemeButton`'s white "selected" checkmark,
    /// both well under WCAG's 3:1 minimum for graphical UI components. `Color(white: 0.78)` is a
    /// literal (non-dynamic) grayscale value — genuinely opaque and appearance-INDEPENDENT like the
    /// other five presets — which is what makes the checkmark fix below (switching to a single fixed
    /// black, rather than needing a per-appearance branch) correct for every swatch uniformly.
    var swatchColor: Color {
        switch self {
        case .default: Color(white: 0.78)
        case .ocean: .blue
        case .forest: .green
        case .sunset: .orange
        case .lavender: .purple
        case .graphite: .gray
        }
    }

    /// Display label for the theme popover.
    var displayName: String { rawValue.capitalized }
}

/// Resolves a board's stored theme fields to the background actually shown, with a custom hex
/// color taking precedence over the named preset whenever it parses. PURE: a total function of
/// its two inputs only — no SwiftData/environment reads, no other hidden state.
enum ThemeResolution {
    enum Background: Equatable {
        case preset(BoardTheme)
        case custom(Color)
    }

    /// `customHex` wins whenever it parses (regardless of `themeName`); otherwise falls back to
    /// the named preset, or `.default` when `themeName` doesn't match any known case (e.g. data
    /// from a future schema version, or simply the "default" placeholder every board is created
    /// with before Phase B).
    static func resolve(themeName: String, customHex: String?) -> Background {
        if let customHex, let components = HexColor.parse(customHex) {
            return .custom(Color(red: components.r, green: components.g, blue: components.b))
        }
        return .preset(BoardTheme(rawValue: themeName) ?? .default)
    }
}

/// Foundation-only hex color parsing/formatting — deliberately no SwiftUI import — so it
/// unit-tests without a platform-flavored `Color` in the mix. Accepts "#RRGGBB" or "RRGGBB",
/// case-insensitively; rejects anything else (wrong length — including the 3-digit CSS shorthand
/// — non-hex characters, and empty strings). `format` is the canonical inverse: always uppercase,
/// no leading '#', so a round trip through `parse` → `format` is stable regardless of the input's
/// original case or '#' presence.
enum HexColor {
    static func parse(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("#") { stripped.removeFirst() }
        guard stripped.count == 6, let value = UInt32(stripped, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    /// Renders canonical "RRGGBB" — uppercase, no leading '#' — from 0...1 components.
    static func format(r: Double, g: Double, b: Double) -> String {
        let ri = UInt8(clamping: Int((r * 255).rounded()))
        let gi = UInt8(clamping: Int((g * 255).rounded()))
        let bi = UInt8(clamping: Int((b * 255).rounded()))
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}

import SwiftUI
import AppKit

/// SwiftUI `Color` → canonical "RRGGBB" (sRGB, alpha dropped). Deliberately separate from
/// `HexColor` (Foundation-only for unit-testability): this side owns the AppKit conversion.
/// Returns nil when the color has no sRGB representation (some catalog/dynamic colors).
/// Out-of-gamut components clamp into 0...1 — a P3 pick lands on the nearest sRGB value,
/// so reopening the picker can show a slightly different color than was picked.
enum ColorHexBridge {
    static func hexString(from color: Color) -> String? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = min(max(srgb.redComponent, 0), 1)
        let g = min(max(srgb.greenComponent, 0), 1)
        let b = min(max(srgb.blueComponent, 0), 1)
        return HexColor.format(r: r, g: g, b: b)
    }
}

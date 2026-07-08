import Testing
import SwiftUI
@testable import Tack

/// The Color→sRGB→RRGGBB bridge feeding the ThemeButton ColorPicker well (M-A).
/// HexColor itself stays Foundation-only; this bridge owns the AppKit conversion.
struct ColorHexBridgeTests {
    @Test func convertsSRGBPrimaries() {
        #expect(ColorHexBridge.hexString(from: Color(red: 1, green: 0, blue: 0)) == "FF0000")
        #expect(ColorHexBridge.hexString(from: Color(red: 0, green: 1, blue: 0)) == "00FF00")
        #expect(ColorHexBridge.hexString(from: Color(red: 0, green: 0, blue: 1)) == "0000FF")
        #expect(ColorHexBridge.hexString(from: Color(red: 0, green: 0, blue: 0)) == "000000")
        #expect(ColorHexBridge.hexString(from: Color(red: 1, green: 1, blue: 1)) == "FFFFFF")
    }

    @Test func roundTripsThroughHexColor() {
        let hex = "3A5F8F"
        let parsed = HexColor.parse(hex)!
        let color = Color(red: parsed.r, green: parsed.g, blue: parsed.b)
        #expect(ColorHexBridge.hexString(from: color) == hex)
    }

    @Test func alphaIsIgnored() {
        // supportsOpacity(false) is belt; this is suspenders — alpha never reaches storage.
        let color = Color(red: 1, green: 0, blue: 0, opacity: 0.4)
        #expect(ColorHexBridge.hexString(from: color) == "FF0000")
    }

    @Test func wideGamutClampsIntoSRGB() {
        // A P3 red outside sRGB must clamp to a valid RRGGBB, not fail.
        let p3 = Color(.displayP3, red: 1, green: 0, blue: 0, opacity: 1)
        let hex = ColorHexBridge.hexString(from: p3)
        #expect(hex != nil)
        #expect(HexColor.parse(hex!) != nil)
    }
}

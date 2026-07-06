import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kanban

@Suite("HexColor")
struct HexColorTests {
    @Test("parses uppercase hex with a leading #")
    func parsesUppercaseWithHash() {
        let result = HexColor.parse("#3A5F8F")
        #expect(result != nil)
        #expect(result!.r == 58.0 / 255.0)
        #expect(result!.g == 95.0 / 255.0)
        #expect(result!.b == 143.0 / 255.0)
    }

    @Test("parses lowercase hex without a leading #")
    func parsesLowercaseWithoutHash() {
        let result = HexColor.parse("3a5f8f")
        #expect(result != nil)
        #expect(result!.r == 58.0 / 255.0)
        #expect(result!.g == 95.0 / 255.0)
        #expect(result!.b == 143.0 / 255.0)
    }

    @Test("rejects the 3-digit CSS shorthand and other short strings")
    func rejectsShortForm() {
        #expect(HexColor.parse("#3A5") == nil)
        #expect(HexColor.parse("ABC") == nil)
        #expect(HexColor.parse("1") == nil)
    }

    @Test("rejects non-hex characters")
    func rejectsNonHexCharacters() {
        #expect(HexColor.parse("zzz") == nil)
        #expect(HexColor.parse("GGGGGG") == nil)
        #expect(HexColor.parse("#3A5F8Z") == nil)
    }

    @Test("rejects empty and bare-# strings")
    func rejectsEmptyStrings() {
        #expect(HexColor.parse("") == nil)
        #expect(HexColor.parse("#") == nil)
    }

    @Test("rejects a too-long string")
    func rejectsTooLong() {
        #expect(HexColor.parse("#3A5F8F00") == nil)
    }

    @Test("format renders canonical uppercase with no leading #")
    func formatIsCanonical() {
        #expect(HexColor.format(r: 58.0 / 255.0, g: 95.0 / 255.0, b: 143.0 / 255.0) == "3A5F8F")
    }

    @Test("round trip is stable regardless of the input's case or # presence")
    func roundTripStable() {
        for input in ["#3A5F8F", "3a5f8f", "3A5F8F", "#3a5f8f"] {
            let parsed = HexColor.parse(input)!
            #expect(HexColor.format(r: parsed.r, g: parsed.g, b: parsed.b) == "3A5F8F")
        }
    }

    @Test("round trip holds at the black and white extremes")
    func roundTripExtremes() {
        #expect(HexColor.format(r: 0, g: 0, b: 0) == "000000")
        #expect(HexColor.format(r: 1, g: 1, b: 1) == "FFFFFF")
        #expect(HexColor.parse(HexColor.format(r: 0, g: 0, b: 0))! == (r: 0, g: 0, b: 0))
    }
}

@Suite("ThemeResolution")
struct ThemeResolutionTests {
    @Test("unknown theme name resolves to the default preset")
    func unknownNameResolvesToDefault() {
        let result = ThemeResolution.resolve(themeName: "not-a-real-theme", customHex: nil)
        #expect(result == .preset(.default))
    }

    @Test("a known preset name resolves to that preset when no custom hex is set")
    func knownPresetResolves() {
        let result = ThemeResolution.resolve(themeName: "ocean", customHex: nil)
        #expect(result == .preset(.ocean))
    }

    @Test("a valid custom hex wins over the preset name")
    func validHexWinsOverPreset() {
        let result = ThemeResolution.resolve(themeName: "ocean", customHex: "#3A5F8F")
        let components = HexColor.parse("3A5F8F")!
        let expected = Color(red: components.r, green: components.g, blue: components.b)
        #expect(result == .custom(expected))
    }

    @Test("an invalid custom hex falls back to the named preset")
    func invalidHexFallsBackToPreset() {
        let result = ThemeResolution.resolve(themeName: "ocean", customHex: "zzz")
        #expect(result == .preset(.ocean))
    }

    @Test("an invalid custom hex plus an unknown preset name falls back to default")
    func invalidHexAndUnknownPresetFallsBackToDefault() {
        let result = ThemeResolution.resolve(themeName: "bogus", customHex: "nope")
        #expect(result == .preset(.default))
    }

    @Test("a nil custom hex falls back to the named preset")
    func nilHexFallsBackToPreset() {
        let result = ThemeResolution.resolve(themeName: "forest", customHex: nil)
        #expect(result == .preset(.forest))
    }
}

@MainActor
@Suite("BoardStore — setTheme")
struct BoardStoreThemeTests {
    @Test("setTheme with a preset (nil hex) sets themeName and clears any stored customThemeHex")
    func setThemePresetClearsHex() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        env.store.setTheme(board, themeName: board.themeName, customHex: "3A5F8F")
        #expect(board.customThemeHex == "3A5F8F")

        env.store.setTheme(board, themeName: "ocean", customHex: nil)

        #expect(board.themeName == "ocean")
        #expect(board.customThemeHex == nil)
    }

    @Test("setTheme with a valid custom hex normalizes it to canonical uppercase, no #")
    func setThemeNormalizesHex() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        env.store.setTheme(board, themeName: board.themeName, customHex: "#3a5f8f")

        #expect(board.customThemeHex == "3A5F8F")
        #expect(board.themeName == "default")
    }

    @Test("setTheme with an invalid custom hex stores no custom hex")
    func setThemeInvalidHexStoresNothing() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        env.store.setTheme(board, themeName: "ocean", customHex: "zzz")

        #expect(board.customThemeHex == nil)
        #expect(board.themeName == "ocean")
    }

    @Test("setTheme is exactly one undo step")
    func setThemeIsOneUndoStep() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Board", emoji: nil)
        #expect(board.themeName == "default")

        env.store.setTheme(board, themeName: "ocean", customHex: nil)
        #expect(board.themeName == "ocean")

        env.undoManager?.undo()
        #expect(board.themeName == "default")
        #expect(board.customThemeHex == nil)
    }

    @Test("undo of a custom-hex setTheme restores the previously stored hex")
    func undoRestoresPreviousHex() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Board", emoji: nil)
        env.store.setTheme(board, themeName: board.themeName, customHex: "3A5F8F")
        #expect(board.customThemeHex == "3A5F8F")

        env.store.setTheme(board, themeName: "forest", customHex: nil)
        #expect(board.themeName == "forest")
        #expect(board.customThemeHex == nil)

        env.undoManager?.undo()

        #expect(board.themeName == "default")
        #expect(board.customThemeHex == "3A5F8F")
    }

    @Test("redo re-applies a setTheme after undo")
    func redoReappliesSetTheme() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Board", emoji: nil)
        env.store.setTheme(board, themeName: "sunset", customHex: nil)

        env.undoManager?.undo()
        #expect(board.themeName == "default")
        env.undoManager?.redo()
        #expect(board.themeName == "sunset")
    }
}

import Foundation
import Testing
@testable import Tack

/// M10 adds `--appearance light|dark` (test-only dark-mode override plumbing); this pins its
/// parsing alongside the existing flags/value-arguments, following the same `init(arguments:)`
/// direct-construction pattern the rest of `AppLaunchConfig` already supports for unit testing.
@Suite("AppLaunchConfig")
struct AppLaunchConfigTests {
    // MARK: - Card detail presentation preference

    @Test("card detail presentation has stable wire values and user-facing names")
    func cardDetailPresentationWireValues() {
        #expect(CardDetailPresentation.sheet.rawValue == "sheet")
        #expect(CardDetailPresentation.sheet.displayName == "Sheet")
        #expect(CardDetailPresentation.sidePanel.rawValue == "side-panel")
        #expect(CardDetailPresentation.sidePanel.displayName == "Side Panel")
    }

    @Test("card detail presentation falls back to sheet for missing or unknown values")
    func cardDetailPresentationFallback() {
        #expect(CardDetailPresentation(storedValue: nil) == .sheet)
        #expect(CardDetailPresentation(storedValue: "") == .sheet)
        #expect(CardDetailPresentation(storedValue: "future-presentation") == .sheet)
        #expect(CardDetailPresentation(storedValue: "side-panel") == .sidePanel)
    }

    @Test("card detail presentation override parses stable values and falls back safely")
    func cardDetailPresentationOverrideParsing() {
        #expect(AppLaunchConfig(arguments: [
            "--uitest", "--card-detail-presentation", "side-panel",
        ]).cardDetailPresentationOverride == .sidePanel)
        #expect(AppLaunchConfig(arguments: [
            "--uitest", "--card-detail-presentation", "unknown",
        ]).cardDetailPresentationOverride == .sheet)
        #expect(AppLaunchConfig(arguments: [
            "--uitest", "--card-detail-presentation",
        ]).cardDetailPresentationOverride == nil)
        #expect(AppLaunchConfig(arguments: ["--uitest"]).cardDetailPresentationOverride == nil)
    }

    @Test("card detail presentation defaults key is namespaced per UI-test store")
    func cardDetailPresentationDefaultsKeyNamespacing() {
        #expect(AppLaunchConfig(arguments: []).cardDetailPresentationDefaultsKey == "cardDetailPresentation")
        #expect(AppLaunchConfig(arguments: [
            "--uitest",
        ]).cardDetailPresentationDefaultsKey == "cardDetailPresentation.default")
        #expect(AppLaunchConfig(arguments: [
            "--uitest", "--store-name", "s1",
        ]).cardDetailPresentationDefaultsKey == "cardDetailPresentation.s1")
    }

    @Test("UI-test reset clears the presentation before applying an override")
    func cardDetailPresentationResetAndOverride() {
        let suiteName = "AppLaunchConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "cardDetailPresentation.s1"
        defaults.set(CardDetailPresentation.sidePanel.rawValue, forKey: key)

        AppLaunchConfig(arguments: [
            "--uitest", "--store-name", "s1", "--reset",
        ]).configureCardDetailPresentationDefaults(in: defaults)
        #expect(defaults.object(forKey: key) == nil)

        AppLaunchConfig(arguments: [
            "--uitest", "--store-name", "s1", "--reset",
            "--card-detail-presentation", "side-panel",
        ]).configureCardDetailPresentationDefaults(in: defaults)
        #expect(defaults.string(forKey: key) == CardDetailPresentation.sidePanel.rawValue)
    }

    @Test("production launches never mutate presentation defaults from launch flags")
    func cardDetailPresentationProductionLaunchIsInert() {
        let suiteName = "AppLaunchConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(CardDetailPresentation.sidePanel.rawValue, forKey: "cardDetailPresentation")
        AppLaunchConfig(arguments: [
            "--reset", "--card-detail-presentation", "sheet",
        ]).configureCardDetailPresentationDefaults(in: defaults)

        #expect(defaults.string(forKey: "cardDetailPresentation") == CardDetailPresentation.sidePanel.rawValue)
    }

    @Test("appearance is nil when the flag is absent")
    func appearanceAbsentIsNil() {
        let config = AppLaunchConfig(arguments: ["--uitest", "--fixture", "standard"])
        #expect(config.appearance == nil)
    }

    @Test("appearance reads the value following --appearance")
    func appearanceReadsValue() {
        let config = AppLaunchConfig(arguments: ["--uitest", "--appearance", "dark"])
        #expect(config.appearance == "dark")
    }

    @Test("appearance is nil when the flag is the trailing argument with no value")
    func appearanceTrailingFlagIsNil() {
        let config = AppLaunchConfig(arguments: ["--uitest", "--appearance"])
        #expect(config.appearance == nil)
    }

    @Test("appearance coexists with the other value-flags unaffected")
    func appearanceCoexistsWithOtherFlags() {
        let config = AppLaunchConfig(arguments: [
            "--uitest", "--fixture", "standard", "--store-name", "s1", "--reset", "--appearance", "light",
        ])
        #expect(config.appearance == "light")
        #expect(config.fixture == "standard")
        #expect(config.storeName == "s1")
        #expect(config.reset == true)
    }

    // MARK: - E-02: --import-from / --import-mode

    @Test("importFrom reads the value following --import-from; nil when absent or trailing")
    func importFromParsing() {
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-from", "backup.json"]).importFrom == "backup.json")
        #expect(AppLaunchConfig(arguments: ["--uitest"]).importFrom == nil)
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-from"]).importFrom == nil)
    }

    @Test("importMode reads the value following --import-mode; nil when absent or trailing")
    func importModeParsing() {
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-mode", "replace"]).importMode == "replace")
        #expect(AppLaunchConfig(arguments: ["--uitest"]).importMode == nil)
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-mode"]).importMode == nil)
    }

    // MARK: - M-C: viewModeDefaultsKey

    @Test("viewModeDefaultsKey is namespaced per store under --uitest")
    func viewModeDefaultsKeyNamespacedUnderUITest() {
        let config = AppLaunchConfig(arguments: ["--uitest", "--store-name", "s1"])
        #expect(config.viewModeDefaultsKey == "boardViewModes.s1")
    }

    @Test("viewModeDefaultsKey is bare in production and tracks the default store name under --uitest")
    func viewModeDefaultsKeyProductionAndDefaultStore() {
        #expect(AppLaunchConfig(arguments: []).viewModeDefaultsKey == "boardViewModes")
        #expect(AppLaunchConfig(arguments: ["--uitest"]).viewModeDefaultsKey == "boardViewModes.default")
    }
}

import Testing
@testable import Tack

/// M10 adds `--appearance light|dark` (test-only dark-mode override plumbing); this pins its
/// parsing alongside the existing flags/value-arguments, following the same `init(arguments:)`
/// direct-construction pattern the rest of `AppLaunchConfig` already supports for unit testing.
@Suite("AppLaunchConfig")
struct AppLaunchConfigTests {
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

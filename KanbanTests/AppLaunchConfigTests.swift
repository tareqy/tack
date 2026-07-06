import Testing
@testable import Kanban

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
}

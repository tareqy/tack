import Foundation

/// Parses UI-test launch arguments. Minimal surface needed for the M2 drag spike; M3 extends
/// the fixture vocabulary. Instances are parsed from an explicit argument array (unit-testable);
/// `current` reflects the running process, and the static passthroughs let call sites read
/// `AppLaunchConfig.isUITest` directly.
struct AppLaunchConfig {
    let isUITest: Bool
    let reset: Bool
    let fixture: String?
    let storeName: String

    /// Configuration for the running process.
    static let current = AppLaunchConfig()

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITest = arguments.contains("--uitest")
        reset = arguments.contains("--reset")
        fixture = AppLaunchConfig.value(after: "--fixture", in: arguments)
        storeName = AppLaunchConfig.value(after: "--store-name", in: arguments) ?? "default"
    }

    /// Returns the argument immediately following `flag`, or nil if absent / trailing.
    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag),
              arguments.index(after: flagIndex) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: flagIndex)]
    }
}

extension AppLaunchConfig {
    static var isUITest: Bool { current.isUITest }
    static var reset: Bool { current.reset }
    static var fixture: String? { current.fixture }
    static var storeName: String { current.storeName }
}

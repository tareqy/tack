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
    /// M10, test-only: forces the whole app's appearance via `--appearance light|dark`, read by
    /// `TackApp.init` (`NSApp.appearance =`). `defaults write -app` doesn't reach a sandboxed
    /// UI-test process, so this is the one plumbing path the dark-mode e2e smoke test and the
    /// screenshot-inspection helpers have to force a specific appearance deterministically. `nil`
    /// (any normal production launch, and any test that omits the flag) defers to the system/user
    /// appearance, unchanged.
    let appearance: String?
    /// Card-detail presentation override, test-only: `--card-detail-presentation sheet|side-panel`
    /// seeds the namespaced preference before `RootView` is created. Invalid values deliberately
    /// resolve to `.sheet`, matching corrupt/future persisted-value fallback behavior.
    let cardDetailPresentationOverride: CardDetailPresentation?
    /// E-01 export e2e hook, test-only: `--export-to <filename>` makes a `--uitest` launch write a
    /// JSON export of every seeded board to `UITest/<filename>` inside the sandbox container, right
    /// after seeding, then continue launching normally. It exists because the production Export path
    /// runs through a sandboxed, remote-hosted `NSSavePanel` that XCUITest cannot reliably drive
    /// (same class of limitation as `--appearance` vs `defaults write`); the export e2e triggers
    /// this and decodes the resulting file. `nil` for every normal launch and every non-export test.
    let exportTo: String?

    /// E-02 import e2e hook, test-only (mirrors `exportTo`): `--import-from <filename>` makes a
    /// `--uitest` launch read `UITest/<filename>` from the sandbox container and run it through
    /// the production decode + store path, publishing the outcome via the `import-self-check`
    /// marker. Exists because the production import runs through a sandboxed, remote-hosted
    /// NSOpenPanel that XCUITest cannot drive, and the sandboxed runner cannot place files in the
    /// app container (the canonical e2e has the app export its own input first via `--export-to`).
    let importFrom: String?
    /// E-02, test-only: `--import-mode add|replace|ask` (default add). `add`/`replace` import
    /// directly (deterministic content tests); `ask` presents the REAL mode dialog so a test can
    /// drive its buttons — the only automatable path onto the dialog.
    let importMode: String?

    /// Configuration for the running process.
    static let current = AppLaunchConfig()

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITest = arguments.contains("--uitest")
        reset = arguments.contains("--reset")
        fixture = AppLaunchConfig.value(after: "--fixture", in: arguments)
        storeName = AppLaunchConfig.value(after: "--store-name", in: arguments) ?? "default"
        appearance = AppLaunchConfig.value(after: "--appearance", in: arguments)
        if let presentation = AppLaunchConfig.value(after: "--card-detail-presentation", in: arguments) {
            cardDetailPresentationOverride = CardDetailPresentation(storedValue: presentation)
        } else {
            cardDetailPresentationOverride = nil
        }
        exportTo = AppLaunchConfig.value(after: "--export-to", in: arguments)
        importFrom = AppLaunchConfig.value(after: "--import-from", in: arguments)
        importMode = AppLaunchConfig.value(after: "--import-mode", in: arguments)
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
    static var appearance: String? { current.appearance }

    /// UserDefaults key backing `RootView`'s persisted `selectedBoardID`. Namespaced by
    /// `storeName` under `--uitest` so distinct on-disk stores (each UI test launches its own,
    /// per `TackUITestCase.launch`) never observe each other's persisted selection; production
    /// always uses the bare key. See `TackApp.init` for the accompanying `--reset` clear, which
    /// keeps this key from accumulating stale entries in UserDefaults across repeated test runs.
    var selectedBoardDefaultsKey: String {
        isUITest ? "selectedBoardID.\(storeName)" : "selectedBoardID"
    }

    /// M-C: UserDefaults key backing `RootView`'s persisted per-board view-mode map (one encoded
    /// string — see `BoardViewMode.encode`). Namespaced by `storeName` under `--uitest` for the
    /// exact same isolation story as `selectedBoardDefaultsKey` above; production uses the bare
    /// key. `TackApp.init`'s `--reset` block clears it alongside the selection key.
    var viewModeDefaultsKey: String {
        isUITest ? "boardViewModes.\(storeName)" : "boardViewModes"
    }

    /// UserDefaults key backing the app-wide card-detail presentation preference. Each UI-test
    /// store gets its own key so relaunch tests can preserve the choice without leaking it into
    /// another test or into the production preference.
    var cardDetailPresentationDefaultsKey: String {
        isUITest ? "cardDetailPresentation.\(storeName)" : "cardDetailPresentation"
    }

    /// Applies UI-test lifecycle semantics to the presentation preference. A fresh `--reset`
    /// launch clears the store-specific value; an optional launch override is then written so it
    /// wins deterministically. Normal launches are inert even if they contain similarly named
    /// arguments, keeping production ownership with the Settings scene.
    func configureCardDetailPresentationDefaults(in defaults: UserDefaults = .standard) {
        guard isUITest else { return }
        if reset {
            defaults.removeObject(forKey: cardDetailPresentationDefaultsKey)
        }
        if let cardDetailPresentationOverride {
            defaults.set(cardDetailPresentationOverride.rawValue, forKey: cardDetailPresentationDefaultsKey)
        }
    }
}

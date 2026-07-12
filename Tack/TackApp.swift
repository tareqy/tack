import SwiftUI
import SwiftData
import AppKit

@main
struct TackApp: App {
    private let config: AppLaunchConfig
    /// nil ONLY when the production container fails to open (see `launchErrorMessage`); every
    /// `--uitest` path and a healthy production launch have one.
    private let container: ModelContainer?
    /// nil for the `--uitest --fixture spike` path (which owns its own `BoardStore` inside
    /// `SpikeRootView`, see M2) and for a failed production launch. Every other path builds one
    /// here and injects it via `.environment(_:)`.
    private let store: BoardStore?
    /// Set when the on-disk production store can't be opened — the app shows a minimal error
    /// window instead of crashing (M7). Never set under `--uitest`.
    private let launchErrorMessage: String?

    init() {
        let config = AppLaunchConfig.current
        self.config = config

        if config.isUITest {
            // Appearance override is a test-only affordance — applied ONLY under --uitest so a
            // normal launch never touches NSApp.appearance (keeps README's "inert for normal
            // launch" claim true).
            Self.applyAppearanceOverride(config.appearance)
            config.configureCardDetailPresentationDefaults()

            // Test-store failures are a test-harness bug, not a user-facing condition — keep the
            // hard failure so it surfaces loudly in CI rather than silently degrading.
            let uiContainer = try! ModelContainerFactory.uiTest(storeName: config.storeName, reset: config.reset)
            FixtureSeeder.seed(config.fixture ?? "standard", context: uiContainer.mainContext)
            container = uiContainer

            // UserDefaults must not leak selection state between UI tests: `--reset` (the default
            // for a fresh `launch(fixture:)`) clears the namespaced key alongside the on-disk
            // store wipe above, so every test starts with no persisted selection. A relaunch via
            // `relaunchPreservingStore()` omits `--reset` and so intentionally keeps it.
            if config.reset {
                UserDefaults.standard.removeObject(forKey: config.selectedBoardDefaultsKey)
                // M-C: the per-board view-mode map has the same per-store namespacing and the
                // same lifecycle — clear it too, so a fresh test launch never inherits modes.
                UserDefaults.standard.removeObject(forKey: config.viewModeDefaultsKey)
            }

            store = config.fixture == "spike" ? nil : BoardStore(context: uiContainer.mainContext)
            launchErrorMessage = nil
        } else {
            // Graceful production-container failure (M7): a corrupt/unreadable store shows an error
            // window rather than a `try!` crash. No recovery logic beyond surfacing the message.
            do {
                let productionContainer = try ModelContainerFactory.production()
                let productionStore = BoardStore(context: productionContainer.mainContext)
                productionStore.ensureLabelsSeeded()
                container = productionContainer
                store = productionStore
                launchErrorMessage = nil
            } catch {
                container = nil
                store = nil
                launchErrorMessage = "Tack couldn't open its database: \(error.localizedDescription) Quit and retry, or contact support."
            }
        }
    }

    var body: some Scene {
        WindowGroup("Tack") {
            content
                // Determinism for UI tests: strip implicit animations so XCUITest never races a
                // mid-flight transition. Production launches keep their animations.
                .transaction { transaction in
                    if AppLaunchConfig.isUITest {
                        transaction.animation = nil
                    }
                }
                // UI-test-only: pin the window to the PRIMARY (menu-bar/origin-zero) display. On a
                // multi-display machine the window server can open a fresh --uitest window on a
                // secondary display positioned above the primary; XCUITest addresses everything
                // relative to the primary's top-left, so such a window reports negative-y frames and
                // its controls fail hittability. Same spirit as `ensureWindow`'s ⌘N nudge. Inert in
                // production (guarded on `isUITest`).
                .background(UITestWindowPlacer())
        }
        // The system default (~900x450) is too narrow for the sidebar toolbar ("Hide Sidebar" +
        // "New Board") to fit without overflowing into the "more toolbar items" popover, where
        // XCUITest can't reach it by identifier. A roomier default avoids that.
        //
        // 1440x850 also ensures the sidebar plus a fresh board's three fixed-280pt columns plus
        // the "Add List" ghost column all fit without horizontal scrolling, while still fitting
        // within a 14" MacBook's 1512pt-wide logical display.
        .defaultSize(width: 1440, height: 850)
        // The menu-bar command layer (M7). Attached at the WindowGroup scene level — the M3 trap is
        // that commands/toolbars contributed from inside the split view never register.
        .commands { AppCommands() }

        Settings {
            CardDetailSettingsView(defaultsKey: config.cardDetailPresentationDefaultsKey)
        }
    }

    /// M10 test-only hook: forces the app's whole appearance from `AppLaunchConfig.appearance`
    /// (`--appearance light|dark`) via `NSApplication.shared.appearance`, which — unlike a
    /// `.preferredColorScheme` view modifier — affects window chrome and every view in the
    /// hierarchy uniformly, matching what a real user's System Settings appearance toggle does.
    /// `defaults write -app` cannot reach a sandboxed `--uitest` process, so this is the
    /// deterministic substitute the dark-mode e2e smoke test and the screenshot-inspection helpers
    /// rely on. Unrecognized/absent values (every normal production launch) leave the system/user
    /// appearance untouched.
    ///
    /// Deliberately `NSApplication.shared`, NOT the bare `NSApp` global: this runs from
    /// `TackApp.init()`, which — under SwiftUI's `App` lifecycle on macOS — executes BEFORE
    /// `NSApplicationMain`-equivalent bootstrapping has populated `NSApp` (an implicitly-unwrapped
    /// global that is still nil at this point). Force-unwrapping it here crashed on every launch
    /// (`EXC_BREAKPOINT` in `applyAppearanceOverride`, reproduced via the screenshot-inspection e2e
    /// helper — see the task-12 report). `NSApplication.shared` is the lazily-initializing
    /// accessor ("creating it if it doesn't exist yet", per Apple's docs) and is safe at this
    /// point.
    private static func applyAppearanceOverride(_ raw: String?) {
        switch raw {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    @ViewBuilder
    private var content: some View {
        if let launchErrorMessage {
            DatabaseErrorView(message: launchErrorMessage)
        } else if config.isUITest, config.fixture == "spike", let container {
            // Drag e2e regression path (M2): unchanged.
            SpikeRootView()
                .modelContainer(container)
        } else if let store, let container {
            RootView(config: config)
                .modelContainer(container)
                .environment(store)
        }
    }
}

/// UI-test-only: moves the hosting window onto the PRIMARY display (the menu-bar screen, AppKit
/// origin `(0,0)`), centered, whenever it isn't already there. XCUITest maps all coordinates
/// relative to the primary display's top-left, so a window the server placed on a secondary display
/// (common on multi-monitor / CI arrangements) reports off-screen frames and fails hittability.
/// Inert in production and for any non-`--uitest` launch.
private struct UITestWindowPlacer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        guard AppLaunchConfig.isUITest else { return view }
        DispatchQueue.main.async { Self.placeOnPrimary(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard AppLaunchConfig.isUITest else { return }
        DispatchQueue.main.async { Self.placeOnPrimary(nsView.window) }
    }

    private static func placeOnPrimary(_ window: NSWindow?) {
        guard let window else { return }
        // The primary display is the one at AppKit origin (0,0) (menu-bar screen); fall back to the
        // first screen. Everything XCUITest hit-tests is relative to this display's top-left.
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first else { return }
        let visible = primary.visibleFrame
        guard !visible.contains(window.frame) else { return }
        let origin = NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

/// Reads the seeded board out of the injected UI-test container and hands it, plus a single
/// long-lived `BoardStore`, to the spike view. `@Query` keeps the tree live as drops mutate it.
private struct SpikeRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Board.position) private var boards: [Board]
    @State private var store: BoardStore?

    var body: some View {
        Group {
            if let board = boards.first, let store {
                SpikeBoardView(board: board, store: store)
            } else {
                Color.clear
                    .accessibilityIdentifier(AccessibilityID.rootView)
            }
        }
        .onAppear {
            if store == nil {
                store = BoardStore(context: context)
            }
        }
    }
}

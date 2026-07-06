import SwiftUI
import SwiftData

@main
struct KanbanApp: App {
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
                launchErrorMessage = "Kanban couldn't open its database: \(error.localizedDescription) Quit and retry, or contact support."
            }
        }
    }

    var body: some Scene {
        WindowGroup("Kanban") {
            content
                // Determinism for UI tests: strip implicit animations so XCUITest never races a
                // mid-flight transition. Production launches keep their animations.
                .transaction { transaction in
                    if AppLaunchConfig.isUITest {
                        transaction.animation = nil
                    }
                }
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

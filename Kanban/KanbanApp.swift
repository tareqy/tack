import SwiftUI
import SwiftData

@main
struct KanbanApp: App {
    private let config: AppLaunchConfig
    private let container: ModelContainer
    /// nil only for the `--uitest --fixture spike` path, which owns its own `BoardStore` inside
    /// `SpikeRootView` (see M2). Every other path (production and every other `--uitest` fixture)
    /// builds one here and injects it via `.environment(_:)`.
    private let store: BoardStore?

    init() {
        let config = AppLaunchConfig.current
        self.config = config

        if config.isUITest {
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
        } else {
            let productionContainer = try! ModelContainerFactory.production()
            let productionStore = BoardStore(context: productionContainer.mainContext)
            productionStore.ensureLabelsSeeded()
            container = productionContainer
            store = productionStore
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
        .defaultSize(width: 1100, height: 750)
    }

    @ViewBuilder
    private var content: some View {
        if config.isUITest, config.fixture == "spike" {
            // Drag e2e regression path (M2): unchanged.
            SpikeRootView()
                .modelContainer(container)
        } else if let store {
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

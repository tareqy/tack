import SwiftUI
import SwiftData

@main
struct KanbanApp: App {
    private let config: AppLaunchConfig
    private let uiTestContainer: ModelContainer?

    init() {
        let config = AppLaunchConfig.current
        self.config = config

        if config.isUITest {
            let container = try! ModelContainerFactory.uiTest(storeName: config.storeName, reset: config.reset)
            FixtureSeeder.seed(config.fixture ?? "standard", context: container.mainContext)
            self.uiTestContainer = container
        } else {
            self.uiTestContainer = nil
        }
    }

    var body: some Scene {
        WindowGroup("Kanban") {
            RootView(config: config, uiTestContainer: uiTestContainer)
                // Determinism for UI tests: strip implicit animations so XCUITest never races a
                // mid-flight transition. Production launches keep their animations.
                .transaction { transaction in
                    if AppLaunchConfig.isUITest {
                        transaction.animation = nil
                    }
                }
        }
    }
}

private struct RootView: View {
    let config: AppLaunchConfig
    let uiTestContainer: ModelContainer?

    var body: some View {
        if config.isUITest, config.fixture == "spike", let container = uiTestContainer {
            SpikeRootView()
                .modelContainer(container)
        } else {
            // Production placeholder (M3 replaces it) and the plain `--uitest` smoke path.
            Text("Kanban")
                .accessibilityIdentifier(AccessibilityID.rootView)
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

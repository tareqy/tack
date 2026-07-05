import SwiftUI

@main
struct KanbanApp: App {
    var body: some Scene {
        WindowGroup("Kanban") {
            RootView()
        }
    }
}

private struct RootView: View {
    var body: some View {
        Text("Kanban")
            .accessibilityIdentifier(AccessibilityID.rootView)
    }
}

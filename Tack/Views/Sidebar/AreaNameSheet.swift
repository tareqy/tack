import SwiftUI
import SwiftData

/// M-F: the one small sheet for area names (the CreateBoardSheet/EditBoardSheet pattern) —
/// create mode is reached only via "Move to Area ▸ New Area…" (an area always starts with a
/// board; see Design Decisions (f)), rename via the area header's context menu.
struct AreaNameSheet: View {
    enum Mode {
        /// Creates (or finds — createArea is find-or-create) an area and moves `board` into it.
        case create(moving: Board)
        case rename(Area)
    }

    let mode: Mode
    let store: BoardStore

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.position) private var areas: [Area]
    @State private var name: String

    init(mode: Mode, store: BoardStore) {
        self.mode = mode
        self.store = store
        switch mode {
        case .create: _name = State(initialValue: "")
        case .rename(let area): _name = State(initialValue: area.name)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rename-to-an-existing-name is disabled (rename-to-MERGE is out of scope); create mode
    /// deliberately allows collisions — createArea's find-or-create turns "New Area… 'Office'"
    /// into a plain move, which is the honest reading of the gesture. The collision key is THE
    /// merge key: exact, trimmed, case-sensitive.
    private var renameCollides: Bool {
        guard case .rename(let area) = mode else { return false }
        return areas.contains { $0.name == trimmedName && $0.id != area.id }
    }

    private var title: String {
        switch mode {
        case .create: "New Area"
        case .rename: "Rename Area"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            TextField("Area name", text: $name)
                .textFieldStyle(.roundedBorder)
                // MANDATORY (CLAUDE.md text-input pitfall): the milestone's only new text input.
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.areaNameField)

            HStack {
                Spacer()
                // Esc must cancel any sheet (HIG) — the CreateBoardSheet one-liner.
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    switch mode {
                    case .create(let board):
                        _ = store.createArea(named: trimmedName, moving: board)
                    case .rename(let area):
                        store.renameArea(area, to: trimmedName)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || renameCollides)
                .accessibilityIdentifier(AccessibilityID.areaSheetConfirm)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

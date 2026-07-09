import SwiftUI

/// M-F: one area's section header — explicit chevron Button (the ListColumnView collapse-button
/// pattern: id-addressable, store-routed, no reliance on native Section disclosure hover
/// affordances) + name text, with the area's context menu (collapse/expand, rename, delete).
/// `.contain`, not `.combine`: a combined element would swallow the chevron Button (the
/// atomic-button pitfall), and `.contain` is the proven `card(_:)` container shape whose
/// children stay queryable.
///
/// HOSTING (M-F seam finding, 2026-07-09): this view is the SECTION'S FIRST ROW, deliberately
/// NOT a `Section(header:)` view. NSOutlineView-backed sidebar Section headers FLATTEN their
/// SwiftUI content into one StaticText under XCUITest — the chevron Button vanishes as an
/// interactive element and child identifiers get CONCATENATED (observed verbatim: one element
/// with identifier `area-toggle-Office-area-Office`), so neither `area-<name>` nor
/// `area-toggle-<name>` is ever queryable and the chevron is never clickable. Rows preserve
/// their hosted AX subtree (every `board-<name>` row proves it), so the header rides as a row,
/// styled like a sidebar header and `.selectionDisabled` at the call site. Do NOT move this
/// back into `header:` without re-running AreaUITests.
struct AreaHeaderView: View {
    let area: Area
    let store: BoardStore
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                store.setAreaCollapsed(area, !area.isCollapsed)
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(area.isCollapsed ? -90 : 0))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(area.isCollapsed ? "Expand area" : "Collapse area")
            .accessibilityLabel(area.isCollapsed ? "Expand Area" : "Collapse Area")
            .accessibilityIdentifier(AccessibilityID.areaToggle(area.name))

            Text(area.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.area(area.name))
        .contextMenu {
            Button(area.isCollapsed ? "Expand Area" : "Collapse Area") {
                store.setAreaCollapsed(area, !area.isCollapsed)
            }
            Button("Rename Area…") { onRename() }
            Button("Delete Area…", role: .destructive) { onDelete() }
        }
    }
}

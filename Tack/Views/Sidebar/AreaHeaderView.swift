import SwiftUI

/// M-F: one area's section header — explicit chevron Button (the ListColumnView collapse-button
/// pattern: id-addressable, store-routed, no reliance on native Section disclosure hover
/// affordances) + name text, with the area's context menu (collapse/expand, rename, delete).
/// `.contain`, not `.combine`: a combined element would swallow the chevron Button (the
/// atomic-button pitfall), and `.contain` is the proven `card(_:)` container shape whose
/// children stay queryable.
///
/// HOSTING (M-F seam finding, 2026-07-09; RE-VERIFIED 2026-07-09 review pass): this view is the
/// SECTION'S FIRST ROW, deliberately NOT a `Section(header:)` view. NSOutlineView-backed sidebar
/// Section headers FLATTEN their hosted SwiftUI AX subtree under XCUITest. Re-verification
/// procedure: the original `Section(header:)` variant (WIP commit `0928941`) was temporarily
/// restored and `AreaUITests.testStandardFixtureGroupsWorkUnderOffice` re-run in isolation
/// (`.build/mf-task3-sectionheader-evidence.log`); it fails on the missing `area-Office` element,
/// exactly as before. The exported AX-hierarchy attachment
/// (`.build/mf-task3-sectionheader-attachments/F677872E-0881-4B57-99B2-6099634F35E0.txt:15`)
/// shows the ENTIRE header row collapsed to one element: `StaticText, identifier:
/// 'area-toggle-Office', label: 'Office'` — the chevron Button is gone as an interactive
/// element, and the `.contain` container's `area-Office` identifier does not appear anywhere in
/// the tree. That is what was actually captured. It does NOT match this file's prior "observed
/// verbatim: `area-toggle-Office-area-Office`" claim — that concatenated string was not found in
/// this re-run's evidence, nor in the original session's surviving log (`.build/mf-task3-varA.log`,
/// checked). Read literally, the surviving evidence shows the chevron's identifier winning over
/// (not concatenating with) the container's, plus the Button-to-StaticText demotion; the
/// concatenation description is corrected here — mechanism INFERRED to be an AX-hosting
/// collision/overwrite, not directly observed as concatenation. Either way, the load-bearing
/// fact holds: neither `area-<name>` nor `area-toggle-<name>` is reliably queryable
/// from a `header:`, and the chevron is never clickable. Rows preserve their hosted AX subtree
/// (every `board-<name>` row proves it), so the header rides as a row, styled like a sidebar
/// header and `.selectionDisabled` at the call site. Restoration to the shipped row-based shape
/// was proven green in the same pass (`.build/mf-task3-restore-proof.log`). Do NOT move this
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

import XCTest

class TackUITestCase: XCTestCase {
    /// The most recently launched app; reassigned by `launch` / `relaunchPreservingStore`.
    private(set) var app: XCUIApplication!

    private var currentFixture = "standard"
    private var currentStoreName = ""

    // MARK: - Launch

    /// Original M0 smoke-test entry point: bare `--uitest`, no fixture. Kept for SmokeUITests.
    @discardableResult
    func launchApp() -> XCUIApplication {
        let launched = XCUIApplication()
        launched.launchArguments = ["--uitest"]
        launched.launch()
        app = launched
        ensureWindow(launched)
        return launched
    }

    /// Launches the app against an on-disk UI-test store seeded with `fixture`. `reset: true`
    /// (the default) wipes the store first for a clean start; the store name defaults to a
    /// sanitized form of the test's name so tests don't collide on disk. `appearance` (M10, e.g.
    /// "dark") is passed straight through as `--appearance <value>`, the test-only override
    /// `AppLaunchConfig`/`TackApp` reads to force `NSApp.appearance` — omitted (nil, the default)
    /// for every pre-M10 call site, which is unaffected.
    @discardableResult
    func launch(fixture: String = "standard", reset: Bool = true, storeName: String? = nil, appearance: String? = nil, exportTo: String? = nil) -> XCUIApplication {
        let resolvedStore = storeName ?? Self.sanitized(name)
        currentFixture = fixture
        currentStoreName = resolvedStore

        let launched = XCUIApplication()
        var args = ["--uitest", "--fixture", fixture, "--store-name", resolvedStore]
        if reset { args.append("--reset") }
        if let appearance {
            args.append(contentsOf: ["--appearance", appearance])
        }
        // E-01 export e2e: `--export-to <file>` makes the app write a JSON export of the seeded
        // boards into the sandbox `UITest/` dir on launch (see AppLaunchConfig.exportTo).
        if let exportTo {
            args.append(contentsOf: ["--export-to", exportTo])
        }
        launched.launchArguments = args
        launched.launch()
        app = launched
        ensureWindow(launched)
        return launched
    }

    /// Terminates and relaunches against the SAME on-disk store WITHOUT `--reset`, so the
    /// previous launch's mutations persist and can be re-asserted.
    @discardableResult
    func relaunchPreservingStore() -> XCUIApplication {
        app?.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--uitest", "--fixture", currentFixture, "--store-name", currentStoreName]
        relaunched.launch()
        app = relaunched
        ensureWindow(relaunched)
        return relaunched
    }

    /// macOS does not auto-present the `WindowGroup` window under XCUITest automation (window
    /// restoration is suppressed), so a fresh launch can land with zero windows. Nudge one open
    /// via the standard "New" command when that happens, then wait for it to exist.
    private func ensureWindow(_ app: XCUIApplication) {
        _ = app.wait(for: .runningForeground, timeout: 15)
        if app.windows.firstMatch.waitForExistence(timeout: 3) { return }

        let newWindowItem = app.menuBars.menuItems["New Tack Window"]
        if newWindowItem.waitForExistence(timeout: 5) {
            newWindowItem.click()
        } else {
            app.typeKey("n", modifierFlags: .command)
        }
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
    }

    // MARK: - Drag

    /// Presses `element`, drags to `targetElement` (at `targetNormalizedOffset`), and holds
    /// briefly over the target before releasing so SwiftUI's drop destination registers the drop.
    /// After the drag it POLLS `until` (up to `settleTimeout`) before deciding whether to retry —
    /// this is critical: a successful-but-slow drop must not be mistaken for a failure, or the
    /// retry would drag a second time and corrupt state. Only a genuinely failed drop (still false
    /// after the poll) triggers exactly one retry.
    func drag(_ element: XCUIElement,
              to targetElement: XCUIElement,
              targetNormalizedOffset: CGVector,
              pressDuration: TimeInterval = 0.6,
              holdDuration: TimeInterval = 0.4,
              settleTimeout: TimeInterval = 4,
              until postcondition: (() -> Bool)? = nil) {
        performDrag(element, to: targetElement, offset: targetNormalizedOffset,
                    pressDuration: pressDuration, holdDuration: holdDuration)

        guard let postcondition else { return }
        if poll(timeout: settleTimeout, postcondition) { return }

        performDrag(element, to: targetElement, offset: targetNormalizedOffset,
                    pressDuration: pressDuration, holdDuration: holdDuration)
        _ = poll(timeout: settleTimeout, postcondition)
    }

    /// Polls `condition` until it is true or `timeout` elapses. Returns the final value.
    @discardableResult
    func poll(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    private func performDrag(_ element: XCUIElement,
                             to targetElement: XCUIElement,
                             offset: CGVector,
                             pressDuration: TimeInterval,
                             holdDuration: TimeInterval) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = targetElement.coordinate(withNormalizedOffset: offset)
        start.press(forDuration: pressDuration,
                    thenDragTo: end,
                    withVelocity: .default,
                    thenHoldForDuration: holdDuration)
    }

    // MARK: - Context menus

    /// A row's `.contextMenu` item titled `title`, disambiguated from an identically-titled
    /// standing menu-bar item (e.g. the standard Edit menu always has a "Delete" entry, so
    /// `app.menuItems["Delete"]` alone matches BOTH it and a right-click menu's "Delete" and
    /// throws "multiple matching elements"). Only the contextual popup's item is actually
    /// on-screen/hittable at the moment it's open, so that's the disambiguator.
    func contextMenuItem(_ title: String, timeout: TimeInterval = 10) -> XCUIElement {
        hittableElement(app.menuItems, titled: title, timeout: timeout) ?? app.menuItems[title]
    }

    /// A button titled `title`, disambiguated the same way as `contextMenuItem`: macOS's
    /// `confirmationDialog` buttons are plain descendants of `app` (not scoped under
    /// `app.dialogs`, which never matches on this host), so a bare `app.buttons[title]` can
    /// collide with an identically-titled button elsewhere in the window/menu structure. Scoped to
    /// `app.windows` (NOT plain `app.buttons`): the simulated Touch Bar carries its own duplicate
    /// of every dialog button, and — unlike the stray menu-bar "Delete" `contextMenuItem` guards
    /// against — that duplicate reports `isHittable == true` while still being un-`click()`-able
    /// ("cannot be called with Touch Bar elements"), so hittability alone doesn't disambiguate it.
    func hittableButton(_ title: String, timeout: TimeInterval = 10) -> XCUIElement {
        hittableElement(app.windows.buttons, titled: title, timeout: timeout) ?? app.windows.buttons[title]
    }

    private func hittableElement(_ query: XCUIElementQuery, titled title: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let matches = query.matching(NSPredicate(format: "title == %@", title)).allElementsBoundByIndex
            if let hittable = matches.first(where: { $0.isHittable }) { return hittable }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    // MARK: - Menus

    func openMenu(_ title: String, timeout: TimeInterval = 15) {
        let bar = app.menuBars.menuBarItems[title]
        XCTAssertTrue(bar.waitForExistence(timeout: timeout), "\(title) menu should exist in the menu bar")
        bar.click()
    }

    func closeMenu() {
        app.typeKey(.escape, modifierFlags: [])
    }

    func menuItem(_ title: String) -> XCUIElement {
        app.menuBars.menuItems[title]
    }

    // MARK: - Content

    /// The visible text of an `.accessibilityElement(children: .combine)` element (e.g.
    /// `board-detail`, a sidebar row). Combined SwiftUI text lands in the element's `value`
    /// (comma-joined), NOT its `label` (which is empty for this shape) — checking `.label` here
    /// is a trap that silently never matches. Falls back to `label` for elements where it IS the
    /// meaningful property, so this is safe to use generally.
    func combinedText(_ element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    // MARK: - Queries

    /// Identifiers (e.g. "card-Spike A1") of every card element under `container`, ordered top to
    /// bottom by on-screen Y position — the canonical way to assert visual list order.
    ///
    /// Excludes `card-labels-*` (the M6 label-dots container on a card's face): it is a descendant
    /// of its `card-<title>` row and also begins with "card-", so without the exclusion every
    /// labeled row would be counted twice — the same shadowing trap the `cardtitle-` prefix comment
    /// in `AccessibilityID` documents.
    ///
    /// Reads via ONE atomic `container.snapshot()` rather than a live `descendants(...).matching(...)
    /// .allElementsBoundByIndex` query. That live form re-resolves the accessibility tree ONCE PER
    /// MATCHED ELEMENT (confirmed against a real run: "Get all elements bound by index" followed by
    /// a separate "Find the ... (Element at index N)" round trip for each card, spanning multiple
    /// seconds) — during a drop mutation, the list it's walking is actively being torn down and
    /// rebuilt by SwiftUI in that same window, so a later per-element round trip can land after the
    /// element it already found has been replaced, escalating through XCTest's internal retries into
    /// a HARD "Failed to get matching snapshot" failure that aborts the test outright (reproduced
    /// 100% of the time on `testDropOnCollapsedListAppends`'s post-drop read of "To Do", not a rare
    /// flake). `.snapshot()` instead captures the WHOLE subtree in one shot; every identifier/frame
    /// read below is then plain in-memory traversal of that already-fetched, internally-consistent
    /// tree, so there is nothing left to race against. It also THROWS (unlike the live query, which
    /// fails hard with no catchable error), so a container that vanishes between the `exists` guard
    /// and the snapshot call degrades to an ordinary `[]` "not yet" for the caller's poll loop
    /// instead of a test-ending failure.
    func cardIdentifiersByPosition(under container: XCUIElement) -> [String] {
        guard container.exists, let snapshot = try? container.snapshot() else { return [] }
        let cards = allDescendants(of: snapshot).filter {
            $0.identifier.hasPrefix("card-") && !$0.identifier.hasPrefix("card-labels-")
        }
        return cards.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier)
    }

    private func allDescendants(of snapshot: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        snapshot.children.flatMap { [$0] + allDescendants(of: $0) }
    }

    // MARK: - Helpers

    static func sanitized(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

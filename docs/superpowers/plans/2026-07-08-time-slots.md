# Time Slots on Cards (M-B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cards can carry an optional time-of-day due slot plus an optional duration: `Card.includesTime` becomes user-settable (it existed but was pinned false), a new `Card.durationMinutes: Int?` stores the slot length, `DueDateStatus.classify` becomes time-aware (a timed card goes `.overdue` the moment its slot ends), the card-detail sheet stages a Time toggle + hour-and-minute field + duration menu, the badge renders "Jul 12, 2:00 PM" with a machine-readable `"<iso>T<HH:mm>|<status>"` a11y value, and the export format bumps 2 → 3 to carry the duration.

**Architecture:** `Card.durationMinutes` is an additive optional — it ships inside `TackSchemaV1` (the `isCollapsed`/`Board.about` precedent), no new schema version, no migration stage. `DueDateStatus.classify` and `BoardStore.setDueDate` gain **defaulted** time parameters so every existing call site compiles unchanged and the date-only path stays byte-identical; `BoardStore.applyCardEdits` gains **non-defaulted** `includesTime:`/`durationMinutes:` parameters — a default there would let an unrelated edit (title rename through the sheet) silently wipe a card's time slot, so every call site must state its time semantics explicitly. The normalization invariant everywhere: `includesTime` is true only when a dueDate exists; `durationMinutes` persists only when the card is timed AND the value is positive; date-only dueDates stay start-of-day, timed dueDates store the raw wall-clock slot start. Export bumps to formatVersion 3 per the per-feature-bump policy (feature review 2026-07); the existing tolerant `1...formatVersion` gate needs no code change, and the sanitizer clamps stray durations. Fixture-wise, "Write report" becomes the one timed card (2:00 PM +5d, 60 min) — the roster/names are load-bearing and stay untouched, and BadgeUITests' `hasSuffix("|upcoming")` assertion survives by design since `|status` remains the LAST a11y segment. Date-only badges keep their exact M10 a11y value byte-for-byte (`CardDetailUITests.testDueDateQuickOptionAndClear` asserts exact equality on a date-only flow and must stay green untouched).

**Tech Stack:** SwiftUI (macOS 14), SwiftData, XCUITest, Swift Testing, xcodegen.

## Global Constraints

- Every bare `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `pkill -f xcodebuild; pkill -f Tack.app` before every run; FOREGROUND runs; judge only by the log tail; every `TackUITests` invocation carries `-parallel-testing-enabled NO`.
- A unit-test run past ~6 minutes is a **hang, not a slow run** (classically an NSUndoManager registration outside explicit grouping) — kill it and read the log tail for a FAULT line.
- **This milestone adds/renames NO files** — every change lands in existing files, so `make gen` is never needed. If you find yourself creating a file, stop and re-read the task; if a file genuinely must be added, run `make gen` before building.
- Signature discipline (type-consistent across all tasks): `durationMinutes` is `Int?` everywhere (model, store, DTO, bindings). `classify` and `setDueDate` time params are DEFAULTED (`includesTime: Bool = false, durationMinutes: Int? = nil`); `applyCardEdits` time params are NON-defaulted.
- Time-state invariant (all mutation surfaces + the import sanitizer enforce it identically): `includesTime` true requires a non-nil dueDate; `durationMinutes` non-nil requires `includesTime` true AND a positive value; date-only dueDates are start-of-day.
- No new TextField/TextEditor in this milestone, so `.reportsTextInputFocus()` has no new call sites. The new hour-and-minute `DatePicker` (`.field` style) is NSDatePicker-backed and does **not** publish `textInputFocused` — exactly like the existing date field, a known and accepted behavior, NOT a new pitfall. Do not add `.focused()` bindings anywhere (CLAUDE.md launch-focus pitfall).
- Badge a11y grammar: `|<status>` stays the LAST segment (BadgeUITests asserts by suffix); date-only cards' value stays EXACTLY `"<isoFullDate>|<status>"` (CardDetailUITests asserts exact equality).
- Every `BoardStore` mutation = exactly one `withUndoGroup`; `applyCardEdits` must still whole-call no-op (no undo group, no save) when nothing changed — a pure time toggle IS a change. Imports stay non-undoable (detach-and-clear discipline untouched).
- The environmental keyboard/menu UI-test failure mode can be active on this host. Keyboard/menu-gated suites are NOT gates for this plan; the gates are the unit suite + the mouse-driven suites this plan touches (CardDetailUITests, BadgeUITests, ImportUITests, ExportUITests). Before debugging any red keyboard-driven test, control-run it against committed (known-green) code — if the control fails, it's the environment.
- Commit style: short imperative summary, body optional, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.

---

### Task 0: time-aware `DueDateStatus.classify` (pure, unit TDD)

**Files:**
- Modify: `Tack/Store/DueDateStatus.swift`
- Test: `TackTests/DueDateStatusTests.swift`

**Interfaces:**
- Consumes: nothing new (pure Foundation, fixed-clock testable).
- Produces: `static func classify(dueDate: Date?, includesTime: Bool = false, durationMinutes: Int? = nil, now: Date, calendar: Calendar) -> DueDateStatus`. Defaults keep all 10 existing tests AND `DueDateBadge`'s current call site compiling unchanged. Task 3's badge passes the card's time state into these exact labels.

- [ ] **Step 1: Write the failing timed tests**

Append to `TackTests/DueDateStatusTests.swift` (inside the existing `DueDateStatusTests` struct, reusing its `calendar`/`date(...)`/`now` helpers — `now` is 2026-07-05 15:30 UTC). Do NOT touch the 10 existing tests — the defaulted parameters are what keeps them compiling and their results byte-identical.

```swift
    // MARK: - M-B: timed classification (includesTime / durationMinutes)

    @Test("timed today with the time still ahead is today")
    func timedTodayFutureTimeIsToday() {
        let due = date(2026, 7, 5, 18, 0)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, now: now, calendar: calendar) == .today)
    }

    @Test("timed today with the time just passed is overdue")
    func timedTodayTimePassedIsOverdue() {
        let due = date(2026, 7, 5, 15, 29) // one minute before now — no duration → slot already ended
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, now: now, calendar: calendar) == .overdue)
    }

    @Test("timed slot still running (start passed, start+duration ahead) is today")
    func timedSlotStillRunningIsToday() {
        let due = date(2026, 7, 5, 15, 0) // 60-min slot runs until 16:00 > now (15:30)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, durationMinutes: 60,
                                       now: now, calendar: calendar) == .today)
    }

    @Test("timed slot fully ended (start+duration passed) is overdue")
    func timedSlotEndedIsOverdue() {
        let due = date(2026, 7, 5, 14, 0) // 60-min slot ended 15:00 < now (15:30)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, durationMinutes: 60,
                                       now: now, calendar: calendar) == .overdue)
    }

    @Test("timed tomorrow is tomorrow")
    func timedTomorrowIsTomorrow() {
        let due = date(2026, 7, 6, 9, 0)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, now: now, calendar: calendar) == .tomorrow)
    }

    @Test("timed several days out is upcoming")
    func timedUpcomingIsUpcoming() {
        let due = date(2026, 7, 10, 9, 0)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, durationMinutes: 120,
                                       now: now, calendar: calendar) == .upcoming)
    }

    @Test("zero and negative durations are ignored (treated as nil)")
    func nonPositiveDurationIgnored() {
        // Zero: the slot ends at its start (15:00), already past now (15:30) → overdue, same as nil.
        let passed = date(2026, 7, 5, 15, 0)
        #expect(DueDateStatus.classify(dueDate: passed, includesTime: true, durationMinutes: 0,
                                       now: now, calendar: calendar) == .overdue)
        // Negative must NOT pull the slot end earlier: an 18:00 slot with -600 is still ahead.
        let future = date(2026, 7, 5, 18, 0)
        #expect(DueDateStatus.classify(dueDate: future, includesTime: true, durationMinutes: -600,
                                       now: now, calendar: calendar) == .today)
    }

    @Test("nil dueDate with includesTime true is still none")
    func nilDueDateWithTimeIsNone() {
        #expect(DueDateStatus.classify(dueDate: nil, includesTime: true, durationMinutes: 30,
                                       now: now, calendar: calendar) == .none)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/DueDateStatusTests test 2>&1 | tee .build/mb-task0-red.log
```
Expected: compile FAILURE (`classify` has no `includesTime:` label) — for unit TDD in Swift, a compile error on the new API is the red state.

- [ ] **Step 3: Implement**

Replace `classify` in `Tack/Store/DueDateStatus.swift` (the enum cases and file header stay untouched):

```swift
    /// Classifies `dueDate` relative to `now`. Date-only cards (`includesTime == false` — the
    /// default, matching every pre-M-B call site) compare by calendar day exactly as before.
    /// Timed cards (M-B) go `.overdue` the moment `now` is STRICTLY past the end of the slot —
    /// `dueDate + (durationMinutes ?? 0) minutes` — and otherwise fall through to the same
    /// day-based bucketing (a 2 PM slot later today is `.today`, not some "due soon" state).
    /// Non-positive durations are treated as nil: a zero-length slot ends at its start.
    static func classify(dueDate: Date?, includesTime: Bool = false, durationMinutes: Int? = nil,
                         now: Date, calendar: Calendar) -> DueDateStatus {
        guard let dueDate else { return .none }
        if includesTime {
            let minutes = max(durationMinutes ?? 0, 0)
            let slotEnd = calendar.date(byAdding: .minute, value: minutes, to: dueDate) ?? dueDate
            if now > slotEnd { return .overdue }
        }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDate)
        let dayDelta = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        switch dayDelta {
        case ..<0:
            return .overdue
        case 0:
            return .today
        case 1:
            return .tomorrow
        default:
            return .upcoming
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Same command, log `.build/mb-task0-green.log`. Expected: `** TEST SUCCEEDED **`, all DueDateStatusTests (10 existing + 8 new) pass.

- [ ] **Step 5: Commit**

```bash
git add Tack/Store/DueDateStatus.swift TackTests/DueDateStatusTests.swift
git commit -m "DueDateStatus.classify: time-aware overdue for timed cards (M-B)

Defaulted includesTime/durationMinutes params keep all date-only call
sites byte-identical; a timed card is overdue the moment its slot
(dueDate + duration) has strictly passed.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1: `Card.durationMinutes` + store mutations + fixture (unit TDD)

**Files:**
- Modify: `Tack/Models/Card.swift` (new stored property + defaulted init param + comment fix)
- Modify: `Tack/Store/BoardStore.swift` (`setDueDate`, `applyCardEdits`)
- Modify: `Tack/Store/FixtureSeeder.swift` ("Write report" becomes the timed card)
- Modify: `Tack/Views/CardDetail/CardDetailView.swift` (compile-only interim: `save()` passes the card's current time state through — Task 3 replaces it with staged state)
- Test: `TackTests/LabelTests.swift`, `TackTests/BoardStoreCardTests.swift`, `TackTests/FixtureSeederTests.swift`, `TackTests/BoardStoreImportTests.swift` (signature-only fix in `byteEqualityRoundTrip`)

**Interfaces:**
- Consumes: `withUndoGroup`, `TestContainer(withUndo:)` (read the test files' existing construction style and use it verbatim — `TestContainer()` / `env.store` / `env.undoManager`).
- Produces: `Card.durationMinutes: Int?`; `func setDueDate(_ date: Date?, on card: Card, includesTime: Bool = false, durationMinutes: Int? = nil)`; `func applyCardEdits(_ card: Card, title: String, details: String?, labels: Set<LabelColor>, dueDate: Date?, includesTime: Bool, durationMinutes: Int?)`. Task 2's materialize and Task 3's sheet consume these exact signatures.

**Schema note:** the new property is additive-optional inside `TackSchemaV1` (`Tack/Models/TackSchema.swift` stays completely untouched — the `isCollapsed`/`Board.about` precedent). Do NOT create a TackSchemaV2 or a migration stage.

- [ ] **Step 1: Write the failing unit tests**

Add to `TackTests/LabelTests.swift` (below the existing setDueDate tests, same construction style — the two existing setDueDate tests stay untouched and stay green via the defaults):

```swift
    @Test("setDueDate with includesTime keeps the raw time and stores the duration")
    func setDueDateTimedKeepsRawTimeAndDuration() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 14
        components.minute = 0
        let slotStart = Calendar.current.date(from: components)!

        env.store.setDueDate(slotStart, on: card, includesTime: true, durationMinutes: 60)

        #expect(card.dueDate == slotStart, "timed dates are NOT startOfDay-normalized")
        #expect(card.includesTime == true)
        #expect(card.durationMinutes == 60)
    }

    @Test("setDueDate normalizes non-positive durations to nil")
    func setDueDateNonPositiveDurationNil() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        env.store.setDueDate(.now, on: card, includesTime: true, durationMinutes: 0)
        #expect(card.durationMinutes == nil)
        env.store.setDueDate(.now, on: card, includesTime: true, durationMinutes: -30)
        #expect(card.durationMinutes == nil)
        #expect(card.includesTime == true, "the flag itself survives — only the duration is clamped")
    }

    @Test("date-only and nil setDueDate calls both clear a previous time slot")
    func setDueDateDateOnlyAndNilClearTimeState() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 14
        let slotStart = Calendar.current.date(from: components)!
        env.store.setDueDate(slotStart, on: card, includesTime: true, durationMinutes: 60)

        // Date-only call (the defaults) downgrades: startOfDay, flag off, duration gone.
        env.store.setDueDate(slotStart, on: card)
        #expect(card.dueDate == Calendar.current.startOfDay(for: slotStart))
        #expect(card.includesTime == false)
        #expect(card.durationMinutes == nil)

        // Re-time it, then clear with nil — even with stray time args, everything resets.
        env.store.setDueDate(slotStart, on: card, includesTime: true, durationMinutes: 60)
        env.store.setDueDate(nil, on: card, includesTime: true, durationMinutes: 60)
        #expect(card.dueDate == nil)
        #expect(card.includesTime == false)
        #expect(card.durationMinutes == nil)
    }
```

In `TackTests/BoardStoreCardTests.swift`, update the FIVE existing `applyCardEdits` calls for the new non-defaulted signature — each keeps ALL its existing assertions (including `applyCardEditsAppliesFieldChanges`'s `#expect(card.includesTime == false)`):

1. `applyCardEditsNoOpRegistersNoUndoStep` — call becomes:
```swift
        env.store.applyCardEdits(
            card,
            title: card.title,
            details: card.details,
            labels: [.red],
            dueDate: card.dueDate,
            includesTime: false,
            durationMinutes: nil
        )
```
(the card is date-only, so `includesTime: false, durationMinutes: nil` matches current state and the call stays a whole-call no-op — the 4-undo-step count assertion is unchanged).

2. `applyCardEditsAppliesFieldChanges` — the call gains `includesTime: false, durationMinutes: nil` after `dueDate: dueDateWithTime`.
3. `applyCardEditsDiffsLabels` — gains `includesTime: false, durationMinutes: nil` after `dueDate: card.dueDate`.
4. `applyCardEditsUndoesInOneStep` — gains `includesTime: false, durationMinutes: nil` after `dueDate: .now`.
5. `applyCardEditsEmptyTitleIsNoOp` — gains `includesTime: false, durationMinutes: nil` after `dueDate: nil`.

Then add three new tests below them:

```swift
    @Test("applyCardEdits with includesTime keeps the raw time and stores the duration")
    func applyCardEditsTimedKeepsRawTimeAndDuration() {
        let env = TestContainer()
        let board = makeBoard(env)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Task")

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 14
        let slotStart = Calendar.current.date(from: components)!

        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: slotStart, includesTime: true, durationMinutes: 90)

        #expect(card.dueDate == slotStart, "timed dates are NOT startOfDay-normalized")
        #expect(card.includesTime == true)
        #expect(card.durationMinutes == 90)
    }

    @Test("a pure time-toggle edit is a real change: exactly one undo step, not a no-op")
    func applyCardEditsTimeToggleIsOneUndoStep() {
        let env = TestContainer(withUndo: true)
        let board = makeBoard(env)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Task")
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        let day = Calendar.current.date(from: components)!
        env.store.setDueDate(day, on: card) // date-only: startOfDay, includesTime false
        env.undoManager?.removeAllActions()

        // Same dueDate VALUE (already start-of-day) — dueDateChanged is false; timeChanged
        // alone must open the one "Edit Card" undo group.
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: card.dueDate, includesTime: true, durationMinutes: nil)

        #expect(card.includesTime == true)
        #expect(env.undoManager?.canUndo == true, "a pure time toggle must register an undo step")
        env.undoManager?.undo()
        #expect(card.includesTime == false)
        #expect(env.undoManager?.canUndo == false, "…and exactly one")
    }

    @Test("clearing the due date also clears includesTime and durationMinutes")
    func applyCardEditsClearingDueDateClearsTimeState() {
        let env = TestContainer()
        let board = makeBoard(env)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Task")
        env.store.setDueDate(.now, on: card, includesTime: true, durationMinutes: 60)

        // nil dueDate with stray time args is the picker's Clear shape — the normalization
        // (`dueDate != nil && includesTime`) must win over the leftover flags.
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: true, durationMinutes: 60)

        #expect(card.dueDate == nil)
        #expect(card.includesTime == false)
        #expect(card.durationMinutes == nil)
    }
```

In `TackTests/FixtureSeederTests.swift`, replace `dueDatesNormalizedAndRelative` (same function name, updated description and body):

```swift
    @Test("due dates: date-only cards are start-of-day; Write report is a timed 14:00 slot")
    func dueDatesNormalizedAndRelative() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let groceries = fetchBoards(env.context)[0]
        let toDo = groceries.sortedLists[0]
        let inProgress = groceries.sortedLists[1]
        let done = groceries.sortedLists[2]

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let plusFiveStart = calendar.date(byAdding: .day, value: 5, to: todayStart)!

        #expect(card("Buy milk", in: toDo)?.dueDate == yesterdayStart)
        #expect(card("Call plumber", in: toDo)?.dueDate == todayStart)
        #expect(card("Return library books", in: toDo)?.dueDate == tomorrowStart)
        #expect(card("Book flights", in: done)?.dueDate == nil)

        // M-B: Write report is the fixture's ONE timed card — a 2:00 PM slot, 60 minutes, +5d.
        let writeReport = card("Write report", in: inProgress)
        #expect(writeReport?.dueDate == calendar.date(bySettingHour: 14, minute: 0, second: 0, of: plusFiveStart))
        #expect(writeReport?.includesTime == true)
        #expect(writeReport?.durationMinutes == 60)

        // Every DATE-ONLY card must be start-of-day normalized with no stray time state.
        let allCards = toDo.sortedCards + inProgress.sortedCards + done.sortedCards
        for c in allCards where c.title != "Write report" {
            #expect(c.includesTime == false)
            #expect(c.durationMinutes == nil)
            if let due = c.dueDate {
                #expect(due == calendar.startOfDay(for: due))
            }
        }
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/LabelTests -only-testing:TackTests/BoardStoreCardTests -only-testing:TackTests/FixtureSeederTests test 2>&1 | tee .build/mb-task1-red.log
```
Expected: compile FAILURE (no `durationMinutes` on Card, no `includesTime:` label on `setDueDate`/`applyCardEdits`) — the red state.

- [ ] **Step 3: Implement**

`Tack/Models/Card.swift` — replace the `dueDate`/`includesTime` property lines and add `durationMinutes` (relaxed invariant comment on line 10 is part of the change):

```swift
    var dueDate: Date?          // startOfDay when includesTime == false; the raw slot start (M-B) when true
    var includesTime: Bool
    /// M-B: length of the time slot in minutes (nil = a point-in-time due, no slot). Only
    /// meaningful when `includesTime == true`; the store/sanitizer normalize it to nil otherwise
    /// and never persist a non-positive value. Additive optional in TackSchemaV1 (the
    /// `isCollapsed`/`Board.about` precedent — no schema version bump, no migration stage).
    var durationMinutes: Int?
```

and in the init, add `durationMinutes: Int? = nil,` immediately after the `includesTime: Bool = false,` parameter, with `self.durationMinutes = durationMinutes` after `self.includesTime = includesTime`. The default keeps `FixtureSeeder`'s direct `Card(...)` constructions (spike/large) and `BoardStore.materialize` compiling unchanged (Task 2 threads it through materialize explicitly).

`Tack/Store/BoardStore.swift` — replace `setDueDate` (including its doc comment):

```swift
    /// One undo step ("Set Due Date"). Date-only calls (the defaults — every pre-M-B call site)
    /// normalize to local start-of-day with `includesTime` false, exactly as before. Timed calls
    /// (M-B) store the raw wall-clock `date` with `includesTime` true. `durationMinutes` is kept
    /// only when the call is timed AND the value is positive — nil otherwise, so a date-only card
    /// can never carry a stray duration and a zero/negative slot is never persisted.
    func setDueDate(_ date: Date?, on card: Card, includesTime: Bool = false, durationMinutes: Int? = nil) {
        withUndoGroup("Set Due Date") {
            let normalizedIncludesTime = date != nil && includesTime
            if let date {
                card.dueDate = normalizedIncludesTime ? date : Calendar.current.startOfDay(for: date)
            } else {
                card.dueDate = nil
            }
            card.includesTime = normalizedIncludesTime
            card.durationMinutes = (normalizedIncludesTime && (durationMinutes ?? 0) > 0) ? durationMinutes : nil
            card.updatedAt = .now
            save()
        }
    }
```

Replace `applyCardEdits` (doc comment updated; the labels block inside the undo group is UNCHANGED — shown elided here, keep the file's existing code):

```swift
    /// Commits every staged field of the M6 card-detail sheet as ONE undo group ("Edit Card"), so a
    /// single ⌘Z reverses title/details/labels/dueDate/time together. Applies only the fields that
    /// actually changed (labels are diffed against the card's current set; untouched labels aren't
    /// re-written) and bumps `updatedAt` only if something changed — a call where every argument
    /// already matches the card's current state registers no undo step at all. `title` is trimmed;
    /// an empty/whitespace-only result is a no-op for the title specifically (the existing title is
    /// kept) rather than clearing it — other changed fields in the same call still apply and still
    /// bump `updatedAt`. `dueDate` is normalized exactly like `setDueDate`: local start-of-day when
    /// `includesTime` is false, the raw wall-clock value when true; `durationMinutes` survives only
    /// on a timed edit with a positive value. `includesTime`/`durationMinutes` are deliberately
    /// NOT defaulted — a defaulted `includesTime: false` here would let any unrelated edit (a title
    /// rename committed through the sheet) silently wipe a card's time slot, so every call site
    /// must state its time semantics explicitly.
    func applyCardEdits(_ card: Card, title: String, details: String?, labels: Set<LabelColor>,
                        dueDate: Date?, includesTime: Bool, durationMinutes: Int?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = trimmedTitle.isEmpty ? card.title : trimmedTitle
        let normalizedIncludesTime = dueDate != nil && includesTime
        let normalizedDueDate = includesTime ? dueDate : dueDate.map { Calendar.current.startOfDay(for: $0) }
        let normalizedDuration = (normalizedIncludesTime && (durationMinutes ?? 0) > 0) ? durationMinutes : nil
        let currentLabelColors = Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) })
        let labelsToAdd = labels.subtracting(currentLabelColors)
        let labelsToRemove = currentLabelColors.subtracting(labels)

        let titleChanged = newTitle != card.title
        let detailsChanged = details != card.details
        let dueDateChanged = normalizedDueDate != card.dueDate
        let timeChanged = normalizedIncludesTime != card.includesTime || normalizedDuration != card.durationMinutes
        let labelsChanged = !labelsToAdd.isEmpty || !labelsToRemove.isEmpty

        guard titleChanged || detailsChanged || dueDateChanged || timeChanged || labelsChanged else { return }

        withUndoGroup("Edit Card") {
            if titleChanged { card.title = newTitle }
            if detailsChanged { card.details = details }
            if dueDateChanged || timeChanged {
                // The dueDate family (date + flag + duration) writes as one unit: a pure time
                // toggle must also settle the date's normalization, and vice versa.
                card.dueDate = normalizedDueDate
                card.includesTime = normalizedIncludesTime
                card.durationMinutes = normalizedDuration
            }
            if labelsChanged {
                // ... UNCHANGED — keep the existing labelsByColorName add/remove block verbatim ...
            }
            card.updatedAt = .now
            save()
        }
    }
```

`Tack/Store/FixtureSeeder.swift` — in `seedGroceries`, replace the "Write report" block:

```swift
        let writeReport = store.addCard(to: inProgress, title: "Write report")
        // M-B: the fixture's ONE timed card — a 2:00 PM slot, 60 minutes, five days out. Still
        // `|upcoming` for BadgeUITests' suffix assertion (+5d 14:00 is always in the future),
        // and the card roster/names are load-bearing across the UI suites — do not rename.
        let writeReportSlot = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: daysFromNow(5))!
        store.setDueDate(writeReportSlot, on: writeReport, includesTime: true, durationMinutes: 60)
        store.toggleLabel(.red, on: writeReport)
```

Call-site sweep for the new non-defaulted `applyCardEdits` signature (both break the compile until fixed):

`Tack/Views/CardDetail/CardDetailView.swift` — `save()` becomes:

```swift
        store.applyCardEdits(
            card,
            title: title,
            details: trimmedDetails.isEmpty ? nil : trimmedDetails,
            labels: labels,
            dueDate: dueDate,
            // Interim (M-B Task 1): pass the card's CURRENT time state through unchanged so an
            // unrelated edit never wipes a time slot. Task 3 replaces both with staged @State.
            includesTime: card.includesTime,
            durationMinutes: card.durationMinutes
        )
```

`TackTests/BoardStoreImportTests.swift` — `byteEqualityRoundTrip`'s `applyCardEdits` call gains the explicit date-only args:

```swift
        a.store.applyCardEdits(cardOne, title: "Card One", details: "line1\nline2",
                               labels: [.red, .blue], dueDate: Date(timeIntervalSince1970: 1_781_800_000),
                               includesTime: false, durationMinutes: nil)
```
(Task 2 gives this test a timed card; here it only needs to compile with unchanged semantics.)

- [ ] **Step 4: Run to verify pass**

Same command as Step 2, log `.build/mb-task1-green.log`. Expected: `** TEST SUCCEEDED **` — LabelTests (5 existing + 3 new), BoardStoreCardTests (13 existing + 3 new), FixtureSeederTests all green.

- [ ] **Step 5: Run the full unit suite** (fixture + signature changes ripple)

`pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/mb-task1-unit.log` — expected `** TEST SUCCEEDED **`. ExportDocumentTests must still be green at this point WITHOUT changes (it doesn't assert `includesTime`/duration yet; the timed fixture card round-trips through the v2 DTO with its duration simply not exported). If any Export/Import unit test fails here, STOP — you touched Task 2's surface early.

- [ ] **Step 6: Commit**

```bash
git add Tack/Models/Card.swift Tack/Store/BoardStore.swift Tack/Store/FixtureSeeder.swift Tack/Views/CardDetail/CardDetailView.swift TackTests/LabelTests.swift TackTests/BoardStoreCardTests.swift TackTests/FixtureSeederTests.swift TackTests/BoardStoreImportTests.swift
git commit -m "Card.durationMinutes + time-aware setDueDate/applyCardEdits (M-B)

Additive TackSchemaV1 optional (isCollapsed/about precedent). setDueDate
keeps defaulted date-only behavior; applyCardEdits takes NON-defaulted
time params so no call site can silently wipe a slot. Fixture: Write
report is now the one timed card (14:00 +5d, 60 min).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Export v3 — `ExportCard.durationMinutes` + sanitizer clamp (unit TDD)

**Files:**
- Modify: `Tack/Export/ExportDocument.swift` (DTO field, mapping, version constant, sanitizer)
- Modify: `Tack/Store/BoardStore.swift` (`materialize` threads `durationMinutes`)
- Test: `TackTests/ExportDocumentTests.swift`, `TackTests/ImportDecodeTests.swift`, `TackTests/BoardStoreImportTests.swift`

**Interfaces:**
- Consumes: `Card.durationMinutes` and the extended `setDueDate` from Task 1.
- Produces: `ExportCard.durationMinutes: Int?` (defaulted); `ExportDocument.formatVersion == 3`; the existing `1...formatVersion` gate needs NO code change (it widens automatically — v1 AND v2 files keep importing); sanitizer nils durations on date-only or non-positive cards. `ImportError.unsupportedVersion`'s message interpolates `ExportDocument.formatVersion` and needs no edit either. Task 3's UI tests rely on nothing here; Task 4's Import/Export UI suites round-trip the app's own exports, so no UI fixture carries a version literal (verified: `formatVersion` appears nowhere outside `ExportDocument.swift` and unit tests).

- [ ] **Step 1: Update the version-pinning tests + add new ones (the red set)**

In `TackTests/ExportDocumentTests.swift`:
- `formatVersionIsTwo`: rename to `formatVersionIsThree`, `@Test("formatVersion is 3 and present in the encoded JSON")`, both `== 2` expectations become `== 3`.
- `emptyStoreExportsZeroBoards`: `#expect(decoded.formatVersion == 3)`.
- In `roundTripPreservesStructureAndValues`, after the labels assertions add:

```swift
            // M-B: the fixture's timed card round-trips its time state and duration.
            let writeReport = groceries.lists[1].cards[0]
            #expect(writeReport.includesTime == true)
            #expect(writeReport.durationMinutes == 60)
```

- In `datesRoundTrip`, after the "Book flights" nil assertion add:

```swift
            // Timed due dates (14:00:00, zero sub-seconds) are also ISO-8601-lossless: exact equality.
            let writeReportDue = boards[0].sortedLists[1].sortedCards[0].dueDate
            #expect(decoded.boards[0].lists[1].cards[0].dueDate == writeReportDue)
```

In `TackTests/ImportDecodeTests.swift`:
- Extend the `cardJSON` helper with a duration parameter (keys stay alphabetical-ish but order is irrelevant to decoding):

```swift
    private func cardJSON(labels: String = "[]", dueDate: String? = nil, includesTime: Bool = false,
                          durationMinutes: Int? = nil) -> String {
        let due = dueDate.map { "\"dueDate\":\"\($0)\"," } ?? ""
        let duration = durationMinutes.map { "\"durationMinutes\":\($0)," } ?? ""
        return """
        {"createdAt":"2026-01-01T00:00:00Z","details":null,\(due)\(duration)"includesTime":\(includesTime),
         "labels":\(labels),"position":0,"title":"C","updatedAt":"2026-01-01T00:00:00Z"}
        """
    }
```
- `versionGate`: the loop becomes `for version in [4, 0]` (3 is now valid; 4 is the unsupported future, 0 still invalid), `@Test("formatVersion 4 and 0 throw .unsupportedVersion carrying the file's version")`, same `.unsupportedVersion(version)` expectation.
- Add below `v1FileStillImports`:

```swift
    @Test("a version-2 file (no durationMinutes key) still imports; duration decodes nil")
    func v2FileStillImports() throws {
        let data = json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true)),
                        formatVersion: 2)
        let envelope = try ExportDocument.decodeForImport(data)
        #expect(envelope.formatVersion == 2)
        #expect(envelope.boards[0].lists[0].cards[0].durationMinutes == nil)
    }
```
- Add to the gray-zone sanitization section (below `dueDateUntouchedWhenIncludesTime`):

```swift
    @Test("durationMinutes is nilled when the card is date-only")
    func durationNilledWhenDateOnly() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: false,
                                           durationMinutes: 60))), calendar: utcCalendar)
        #expect(envelope.boards[0].lists[0].cards[0].durationMinutes == nil)
    }

    @Test("non-positive durationMinutes is nilled; a positive timed duration passes through")
    func durationClampedWhenNonPositive() throws {
        for bad in [0, -15] {
            let envelope = try ExportDocument.decodeForImport(
                json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true,
                                               durationMinutes: bad))), calendar: utcCalendar)
            #expect(envelope.boards[0].lists[0].cards[0].durationMinutes == nil)
        }
        let kept = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true,
                                           durationMinutes: 45))), calendar: utcCalendar)
        #expect(kept.boards[0].lists[0].cards[0].durationMinutes == 45)
    }
```
- `sanitizeIdempotent`: extend the input so it ALSO carries a timed card with a duration (the original date-only card keeps the startOfDay-normalization leg in play):

```swift
        let data = json(boardJSON(cards: cardJSON(labels: #"["blue","red","neon"]"#,
                                                  dueDate: "2026-07-08T15:30:00Z") + "," +
                                         cardJSON(dueDate: "2026-07-08T15:30:00Z",
                                                  includesTime: true, durationMinutes: 45),
                          customThemeHex: "\"#ff0000\""))
```
(the `once == twice` assertions are unchanged).

In `TackTests/BoardStoreImportTests.swift` — `byteEqualityRoundTrip` builds its store via store ops; give "Card Two" a timed slot through the Task 1 `setDueDate` extension (replace the bare `a.store.addCard(to: alphaLists[0], title: "Card Two")` line):

```swift
        let cardTwo = a.store.addCard(to: alphaLists[0], title: "Card Two")
        // M-B: a timed card with a duration — includesTime true skips startOfDay normalization,
        // so the raw whole-second epoch survives ISO-8601 byte-stably.
        a.store.setDueDate(Date(timeIntervalSince1970: 1_781_803_800), on: cardTwo,
                           includesTime: true, durationMinutes: 90)
```
and extend the test's header comment's field list with "a timed card + duration". The `sampleEnvelope()` `ExportCard(...)` literals compile unchanged (the new DTO field is defaulted — deliberately, same as `ExportBoard.about`); they stay `formatVersion: 1` exercising the tolerant gate.

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/ExportDocumentTests -only-testing:TackTests/ImportDecodeTests -only-testing:TackTests/BoardStoreImportTests test 2>&1 | tee .build/mb-task2-red.log
```
Expected: compile failure on `ExportCard.durationMinutes` + assertion failures on `formatVersion == 3`.

- [ ] **Step 3: Implement in `Tack/Export/ExportDocument.swift`**

- `ExportCard`: add after the `includesTime` property:

```swift
    // Defaulted (the ExportBoard.about precedent) so out-of-scope ExportCard(...) construction
    // sites keep compiling; a missing JSON key always decodes an Optional as nil, so v1/v2
    // files import with no duration.
    var durationMinutes: Int? = nil
```
- `exportCard(_:)`: add `durationMinutes: card.durationMinutes,` after the `includesTime:` line.
- `formatVersion`: becomes `static let formatVersion = 3`, doc comment gains the line:

```swift
    /// v3 (M-B): + ExportCard.durationMinutes; includesTime is now user-settable.
```
- `sanitized`: extend the doc-comment bullet list with `- durationMinutes → nil unless includesTime && > 0 (the Card invariant M-B adds);` and, inside the card map, immediately after the dueDate start-of-day normalization `if`:

```swift
                    if !card.includesTime || (card.durationMinutes ?? 0) <= 0 {
                        card.durationMinutes = nil
                    }
```
- The version gate and `ImportError.unsupportedVersion`'s message both derive from `formatVersion` — verify by reading, change nothing.

And in `Tack/Store/BoardStore.swift` `materialize`, thread the field into the `Card(...)` construction: `durationMinutes: exportCard.durationMinutes,` after the `includesTime:` line.

- [ ] **Step 4: Run to verify pass** — same command, log `.build/mb-task2-green.log`. Expected `** TEST SUCCEEDED **` (byte-equality round trip now proves the timed card + duration survive export → import → re-export byte-stably).

- [ ] **Step 5: Full unit suite** — `pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/mb-task2-unit.log`, expected `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Tack/Export/ExportDocument.swift Tack/Store/BoardStore.swift TackTests/ExportDocumentTests.swift TackTests/ImportDecodeTests.swift TackTests/BoardStoreImportTests.swift
git commit -m "Export formatVersion 3: ExportCard.durationMinutes, sanitizer duration clamp

v1/v2 files keep importing through the existing tolerant gate (missing
durationMinutes decodes nil). Sanitizer nils durations on date-only or
non-positive cards, mirroring the store invariant.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: DueDatePicker time controls + detail staging + timed badge (UI TDD)

**Files:**
- Modify: `Tack/Support/AccessibilityID.swift` (three new M6-section ids)
- Modify: `Tack/Views/CardDetail/DueDatePicker.swift` (Time toggle + hour-and-minute field + duration menu)
- Modify: `Tack/Views/CardDetail/CardDetailView.swift` (staged time state; replaces Task 1's interim passthrough)
- Modify: `Tack/Views/Components/DueDateBadge.swift` (timed visible text + timed a11y value + time-aware classify)
- Test: `TackUITests/CardDetailUITests.swift`

**Interfaces:**
- Consumes: `applyCardEdits(_:title:details:labels:dueDate:includesTime:durationMinutes:)` from Task 1; time-aware `classify` from Task 0.
- Produces: AX ids `due-time-toggle`, `due-time-field`, `due-duration-field`; badge visible text `"Jul 12, 2:00 PM"` and a11y value `"<isoFullDate>T<HH:mm>|<status>"` for timed cards ONLY. Date-only badge output is byte-identical to M10 (`testDueDateQuickOptionAndClear`'s exact-equality assertion is the regression gate — do NOT touch that test).

- [ ] **Step 1: Write the failing UI test**

Add to `TackUITests/CardDetailUITests.swift`, after `testDueDateQuickOptionAndClear` (reuse the file's existing helpers — `openDetailViaBodyDoubleClick`, `element(_:)`, `hittableButton`, `detailSheet`, `poll`, `timeout` — read them first and use them verbatim):

```swift
    /// M-B: the Time toggle stages a 9:00 AM slot on a date-only pick (deterministic — the staged
    /// quick-button date is bare midnight), Save persists it, the badge exposes the timed a11y
    /// value ("<iso>T09:00|tomorrow" — status stays the LAST segment), and reopening shows the
    /// toggle on. The duration menu's interaction is human-verified (menu-style Picker popups
    /// under synthetic input are the B-06 class of problem); this test pins its presence only.
    func testTimedDueDateTogglePersists() {
        launch(fixture: "standard")

        // "Book flights" (Done) starts with no due date at all.
        openDetailViaBodyDoubleClick("Book flights")
        element(AccessibilityID.dueQuickTomorrow).click()
        let toggle = element(AccessibilityID.dueTimeToggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout),
                      "Time toggle should appear once a date is staged")
        toggle.click()

        XCTAssertTrue(element(AccessibilityID.dueTimeField).waitForExistence(timeout: timeout),
                      "hour-and-minute field should appear when the toggle is on")
        XCTAssertTrue(element(AccessibilityID.dueDurationField).exists,
                      "duration menu should appear when the toggle is on")

        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        let badge = element(AccessibilityID.dueDateBadge(card: "Book flights"))
        XCTAssertTrue(poll(timeout: timeout) { badge.exists }, "badge should appear after Save")
        let value = badge.value as? String ?? ""
        XCTAssertTrue(value.contains("T09:00"),
                      "timed badge value should carry the deterministic 9:00 AM default slot, got '\(value)'")
        XCTAssertTrue(value.hasSuffix("|tomorrow"),
                      "status must stay the LAST a11y segment, got '\(value)'")

        // Reopen: staged state seeds from the card — the toggle reads on.
        openDetailViaBodyDoubleClick("Book flights")
        XCTAssertTrue(poll(timeout: timeout) { toggle.exists })
        // AX bridges a checkbox value as String or NSNumber depending on macOS build — coerce.
        let toggleValue = (toggle.value as? String) ?? (toggle.value as? Int).map(String.init) ?? ""
        XCTAssertEqual(toggleValue, "1", "Time toggle should read ON for a timed card")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
    }
```

BadgeUITests is deliberately NOT edited in this task: "Write report" (the fixture's timed card) changes its badge value from `"<iso>|upcoming"` to `"<iso>T14:00|upcoming"`, and `assertBadgeSuffix` asserts `hasSuffix("|upcoming")` — the suffix grammar survives by design. Verify this in the Step 4 run rather than changing that test; if BadgeUITests goes red there, the badge implementation broke the `|status`-last grammar — fix the badge, not the test.

- [ ] **Step 2: Run the red set**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests -parallel-testing-enabled NO test 2>&1 | tee .build/mb-task3-red.log
```
Expected: compile failure on the new AccessibilityID names — the ids don't exist yet; that is the red gate for this step.

- [ ] **Step 3: Implement**

`Tack/Support/AccessibilityID.swift` — add to the M6 card-detail section, after `dueClear`:

```swift
    /// M-B time-slot controls. The toggle/time-field/duration-menu trio exists only while a due
    /// date is staged; the field and menu additionally require the toggle on.
    static let dueTimeToggle = "due-time-toggle"
    static let dueTimeField = "due-time-field"
    static let dueDurationField = "due-duration-field"
```

`Tack/Views/CardDetail/DueDatePicker.swift` — replace the whole file body with:

```swift
import SwiftUI

/// Quick-pick buttons (Today / Tomorrow / Next Week), a compact date field, an optional time slot
/// (M-B: Time toggle → hour-and-minute field + duration menu), and Clear — all mutate ONLY the
/// caller's staged bindings (see `CardDetailView`, which commits the whole staged edit through
/// `BoardStore.applyCardEdits` on Save). Shows an explicit "No due date" label when nil, matching
/// the card face's own "no badge at all" convention for the same state.
///
/// Time-state contract (M-B):
///   - Quick buttons are DATE-ONLY by contract (`DueDateQuickOption` always returns start-of-day,
///     per its doc), so they ALSO reset `includesTime`/`durationMinutes` — the stage always
///     matches what the store persists for that pick; re-enabling time goes through the toggle.
///   - Toggle ON with a bare-midnight staged date sets the slot to 9:00 AM of that day —
///     deterministic (UI-testable) and a sane working-hours default. A date that already carries
///     a time (a previously timed card) is left alone.
///   - Toggle OFF re-normalizes the staged date to start-of-day and drops the duration, so the
///     stage never carries a hidden time on a card the user just made date-only.
///   - Clear resets all three (date, flag, duration).
struct DueDatePicker: View {
    @Binding var dueDate: Date?
    @Binding var includesTime: Bool
    @Binding var durationMinutes: Int?

    /// The duration menu's fixed options, in minutes; nil renders as "None".
    private static let durationOptions: [Int] = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Due Date")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                quickButton("Today", option: .today, id: AccessibilityID.dueQuickToday)
                quickButton("Tomorrow", option: .tomorrow, id: AccessibilityID.dueQuickTomorrow)
                quickButton("Next Week", option: .nextWeek, id: AccessibilityID.dueQuickNextWeek)
            }

            if let resolvedDueDate = dueDate {
                HStack(spacing: 12) {
                    DatePicker(
                        "",
                        selection: Binding(get: { resolvedDueDate }, set: { dueDate = $0 }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .accessibilityIdentifier(AccessibilityID.dueDatePickerField)

                    Button("Clear", role: .destructive) {
                        dueDate = nil
                        includesTime = false
                        durationMinutes = nil
                    }
                    .accessibilityIdentifier(AccessibilityID.dueClear)
                }

                Toggle("Time", isOn: timeToggleBinding)
                    .accessibilityIdentifier(AccessibilityID.dueTimeToggle)

                if includesTime {
                    HStack(spacing: 12) {
                        DatePicker(
                            "",
                            selection: Binding(get: { resolvedDueDate }, set: { dueDate = $0 }),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .accessibilityIdentifier(AccessibilityID.dueTimeField)

                        Picker("Duration", selection: $durationMinutes) {
                            Text("None").tag(Int?.none)
                            ForEach(Self.durationOptions, id: \.self) { minutes in
                                Text("\(minutes) min").tag(Int?.some(minutes))
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier(AccessibilityID.dueDurationField)
                    }
                }
            } else {
                Text("No due date")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Routes the toggle through the M-B time-state contract (see the type doc comment). A custom
    /// Binding (not `.onChange`) so the date/duration adjustments land in the same mutation as the
    /// flag flip — no intermediate render with inconsistent staged state.
    private var timeToggleBinding: Binding<Bool> {
        Binding(
            get: { includesTime },
            set: { turnedOn in
                includesTime = turnedOn
                let calendar = Calendar.current
                if turnedOn {
                    if let current = dueDate, calendar.startOfDay(for: current) == current {
                        dueDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: current) ?? current
                    }
                } else {
                    dueDate = dueDate.map { calendar.startOfDay(for: $0) }
                    durationMinutes = nil
                }
            }
        )
    }

    private func quickButton(_ title: String, option: DueDateQuickOption, id: String) -> some View {
        Button(title) {
            dueDate = DueDateQuickOption.date(for: option, now: .now, calendar: .current)
            // Date-only by contract — see the time-state contract in the type doc comment.
            includesTime = false
            durationMinutes = nil
        }
        .accessibilityIdentifier(id)
    }
}
```

`Tack/Views/CardDetail/CardDetailView.swift`:
- Add below `@State private var dueDate: Date?`:

```swift
    @State private var includesTime: Bool
    @State private var durationMinutes: Int?
```
- In `init`, after `_dueDate = State(initialValue: card.dueDate)`:

```swift
        _includesTime = State(initialValue: card.includesTime)
        _durationMinutes = State(initialValue: card.durationMinutes)
```
- The picker call becomes:

```swift
                DueDatePicker(dueDate: $dueDate, includesTime: $includesTime, durationMinutes: $durationMinutes)
```
- `save()` replaces Task 1's interim passthrough (delete that comment) with the staged values:

```swift
        store.applyCardEdits(
            card,
            title: title,
            details: trimmedDetails.isEmpty ? nil : trimmedDetails,
            labels: labels,
            dueDate: dueDate,
            includesTime: includesTime,
            durationMinutes: durationMinutes
        )
```

`Tack/Views/Components/DueDateBadge.swift` — the `status` computed property, the body's `Text` content, and the a11y representation change; `wireValue(for:)`, `shortDateFormatter`, `isoDateFormatter`, and the M6/M10 comment block above `.accessibilityRepresentation` stay verbatim:

- Extend the type doc comment with:

```swift
/// M-B feeds the card's time state into `classify` (a timed card goes overdue the moment its slot
/// ends) and extends BOTH representations for TIMED cards only: visible "Jul 12, 2:00 PM", a11y
/// "<isoFullDate>T<HH:mm>|<status>". Date-only cards keep the exact M10 forms — the a11y value is
/// pinned byte-for-byte by CardDetailUITests.testDueDateQuickOptionAndClear, and `|status` stays
/// the LAST segment either way (BadgeUITests asserts by suffix).
```
- `status` becomes:

```swift
    private var status: DueDateStatus {
        DueDateStatus.classify(dueDate: dueDate, includesTime: card.includesTime,
                               durationMinutes: card.durationMinutes, now: .now, calendar: .current)
    }
```
- The body's leading line becomes `Text(visibleText)` and the representation's Text becomes:

```swift
                Text("\(wireDateValue)|\(Self.wireValue(for: status))")
                    .accessibilityIdentifier(AccessibilityID.dueDateBadge(card: card.title))
```
- Add the two computed values and two formatters:

```swift
    /// "Jul 12" for date-only cards (unchanged); "Jul 12, 2:00 PM" for timed cards (M-B).
    private var visibleText: String {
        let day = Self.shortDateFormatter.string(from: dueDate)
        guard card.includesTime else { return day }
        return "\(day), \(Self.shortTimeFormatter.string(from: dueDate))"
    }

    /// The date leg of the a11y value: "<isoFullDate>" for date-only cards — EXACTLY the M10
    /// form — and "<isoFullDate>T<HH:mm>" for timed cards.
    private var wireDateValue: String {
        let iso = Self.isoDateFormatter.string(from: dueDate)
        guard card.includesTime else { return iso }
        return "\(iso)T\(Self.wireTimeFormatter.string(from: dueDate))"
    }

    /// Locale-appropriate short time for the VISIBLE capsule ("2:00 PM" or "14:00" per locale).
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Machine-readable 24-hour "HH:mm" for the a11y value. POSIX-pinned: without it, the user's
    /// 12/24-hour system preference can rewrite even an explicit dateFormat (HH → hh), which
    /// would flake the e2e "T09:00" assertion per-host. Local time zone, matching
    /// `isoDateFormatter`'s explicitly-local rationale.
    private static let wireTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter
    }()
```

Build once before the UI run: `pkill -f xcodebuild; pkill -f Tack.app; make build 2>&1 | tee .build/mb-task3-build.log` (expected `** BUILD SUCCEEDED **`).

- [ ] **Step 4: Run the green set** (the detail suite + the badge suite that must survive untouched)

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests -only-testing:TackUITests/BadgeUITests \
  -parallel-testing-enabled NO test 2>&1 | tee .build/mb-task3-green.log
```
Expected: `** TEST SUCCEEDED **` — all CardDetailUITests (including the untouched `testDueDateQuickOptionAndClear` and the new `testTimedDueDateTogglePersists`) plus all BadgeUITests (untouched — proves the suffix grammar survived). Both suites are mouse-driven with in-sheet typing, historically green even in the degraded-keyboard environment; if a failure looks focus/keyboard-shaped, apply the control-run triage rule from Global Constraints before touching app code, and check the xcresult recording for desktop-notification interference.

- [ ] **Step 5: Commit**

```bash
git add Tack/Support/AccessibilityID.swift Tack/Views/CardDetail/DueDatePicker.swift Tack/Views/CardDetail/CardDetailView.swift Tack/Views/Components/DueDateBadge.swift TackUITests/CardDetailUITests.swift
git commit -m "Card detail time slot UI: Time toggle, hour field, duration menu; timed badge

Toggle-on defaults a bare-midnight staged date to 9:00 AM (deterministic,
e2e-pinned); quick buttons stay date-only by contract. Badge shows
'Jul 12, 2:00 PM' and exposes '<iso>T<HH:mm>|<status>' for timed cards;
date-only badge output stays byte-identical to M10.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Milestone gate

**Files:** none (verification only).

- [ ] **Step 1:** `pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/mb-gate-unit.log` → `** TEST SUCCEEDED **`.

- [ ] **Step 2:** Mouse-driven UI suites this milestone touched or depends on:

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests -only-testing:TackUITests/BadgeUITests \
  -only-testing:TackUITests/ImportUITests -only-testing:TackUITests/ExportUITests \
  -parallel-testing-enabled NO test 2>&1 | tee .build/mb-gate-ui.log
```
Expected: green EXCEPT the documented environmentally-failing keyboard/menu-gated tests (`testExportMenuItemExistsAndEnabled`, `testImportMenuItemExistsAndEnabledOnBothFixtures`). Each failure must be one of the environmentally-failing set from the M-A gate log (`.build/ma-gate-ui.log`); any NEW failing test = real regression, fix before proceeding. The Import/Export content e2es round-trip the app's OWN v3 exports (`--export-to` → `--import-from`), so the version bump is self-consistent there by construction — a version-shaped failure in those suites means the gate or DTO regressed, not the fixtures.

- [ ] **Step 3: Human checklist (hand to Ty, accumulate with M-A's)**

Launch against a scratch store — and remember the windowless-launch pitfall: **File ▸ New Tack Window (⌘N) is the second step**, or every board-dependent menu item stays disabled:

```sh
open .build/DerivedData/Build/Products/Debug/Tack.app --args --uitest --fixture standard --store-name scratch --reset
```

1. Open "Write report" (In Progress): the Time toggle reads on, the time field shows 2:00 PM, the duration menu shows "60 min"; its card-face badge reads "‹Mon date›, 2:00 PM".
2. Open a date-only card → pick Tomorrow → toggle Time on: field jumps to 9:00 AM; pick a duration from the menu (the menu-style Picker is NOT e2e-driven — B-06 native-input precedent — this is its verification); Save; badge shows the time; ONE ⌘Z reverts the whole edit (date, flag, and duration together).
3. Toggle Time off on a timed card → Save: badge drops the time; reopen — toggle off, duration "None" (no hidden time state survived).
4. Badge rendering light AND dark (relaunch with `--appearance dark`): the longer timed badge ("Jul 12, 2:00 PM") must not wrap, clip, or crowd the label dots on the card face.
5. Quick-button contract: on a timed card, click "Next Week" — the stage goes date-only (toggle off, duration cleared); Save and confirm the badge is date-only.

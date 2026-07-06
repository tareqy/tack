# Repository Guidelines

## Project Structure & Module Organization

This is a macOS SwiftUI Kanban app generated from `project.yml` with XcodeGen. App code lives in `Kanban/`: `Models/` contains SwiftData models, `Store/` contains state and persistence logic, `Views/` contains SwiftUI screens and components, `DragDrop/` contains transfer/drop helpers, `Commands/` contains menu command wiring, and `Support/` contains launch and accessibility utilities. Unit tests live in `KanbanTests/`, with shared fixtures in `KanbanTests/Helpers/`. UI tests live in `KanbanUITests/`. Product/spec notes are in `PRD-Kanban-Board-Mac.md` and `docs/`.

## Build, Test, and Development Commands

- `make gen`: regenerate `Kanban.xcodeproj` from `project.yml` using XcodeGen.
- `make build`: build the `Kanban` scheme for the current Mac architecture.
- `make unit`: run only `KanbanTests`.
- `make ui`: run only `KanbanUITests`; disables parallel UI testing and writes result bundles under `.build/results/`.
- `make test`: run unit tests, then UI tests.

The `Makefile` sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, which is required on machines where `xcode-select` points at Command Line Tools.

## Coding Style & Naming Conventions

Use Swift 5, SwiftUI, and SwiftData patterns already present in the app. Follow 4-space indentation, `PascalCase` for types, and `lowerCamelCase` for properties, methods, and test helpers. Keep view code organized by feature folder, and put reusable UI in `Kanban/Views/Components/`. Prefer explicit accessibility identifiers from `Kanban/Support/AccessibilityID.swift` for UI-testable elements. Keep comments focused on non-obvious behavior, especially launch paths, persistence, drag/drop, and UI-test determinism.

## Testing Guidelines

Unit tests use the Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`) and should be named after the behavior under test, for example `BoardStoreBoardTests` or `DueDateStatusTests`. Use `TestContainer` for isolated SwiftData tests. UI tests use XCTest/XCUITest and shared launch helpers in `KanbanUITests/KanbanUITestCase.swift`. Run `make unit` for logic changes and `make ui` for view, command, drag/drop, or persistence flows.

## Commit & Pull Request Guidelines

Recent commits use concise milestone or scope prefixes, such as `M10: due-date urgency colors + dark-mode audit` or `M9 review fixes: ...`. Keep commits focused and descriptive. Pull requests should include a short summary, tests run, linked issue/spec when applicable, and screenshots or recordings for visible UI changes. Call out migrations, launch-argument changes, or persistence behavior that reviewers should verify manually.

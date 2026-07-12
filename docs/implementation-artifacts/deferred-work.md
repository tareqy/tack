- source_spec: `docs/implementation-artifacts/spec-build-latest-version.md`
  summary: Replace the future-deprecated `NSApp.activate(ignoringOtherApps:)` call in the custom About-panel action.
  evidence: The macOS 26.5 AppKit SDK marks the method for future deprecation and recommends `NSApp.activate` instead; this was already present in upstream commit `270d4b0` before the build task.

- source_spec: `docs/implementation-artifacts/spec-build-latest-version.md`
  summary: Add UI coverage for the custom About menu item and its credits, name, and version content.
  evidence: No test under `TackTests/` or `TackUITests/` references the About command or credits, so compilation alone does not verify the runtime panel contents; this gap belongs to upstream commit `270d4b0` rather than the build task.

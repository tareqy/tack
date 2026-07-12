---
title: 'Build Latest Tack Version'
type: 'chore'
created: '2026-07-12'
status: 'done'
route: 'one-shot'
---

# Build Latest Tack Version

## Intent

**Problem:** The local checkout was one commit behind `origin/main`, and its existing DerivedData contained stale paths and test artifacts from an earlier checkout location.

**Approach:** Fast-forward `main` to commit `270d4b0`, clean DerivedData, build Tack with the repository Makefile, and validate the resulting app bundle and code signature.

## Suggested Review Order

**Latest upstream behavior**

- Replaces the stock About command with the release's custom About action.
  [`AppCommands.swift:22`](../../Tack/Commands/AppCommands.swift#L22)

- Supplies credits while retaining bundle-derived name, icon, and version rendering.
  [`AppCommands.swift:211`](../../Tack/Commands/AppCommands.swift#L211)

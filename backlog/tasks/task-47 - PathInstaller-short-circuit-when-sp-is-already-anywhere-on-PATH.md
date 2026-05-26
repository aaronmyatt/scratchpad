---
id: TASK-47
title: 'PathInstaller: short-circuit when sp is already anywhere on $PATH'
status: Done
assignee: []
created_date: '2026-05-26 02:05'
updated_date: '2026-05-26 02:07'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
modified_files:
  - Sources/Scratchpad/PathInstaller.swift
  - Tests/ScratchpadTests/PathInstallerTests.swift
priority: medium
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PathInstaller currently checks only `/usr/local/bin/sp` for an existing install. With the Cask now using a `binary` stanza (TASK-32 follow-up), Homebrew puts `sp` at `/opt/homebrew/bin/sp` on Apple Silicon — which PathInstaller doesn't see, so it presents a redundant install dialog on first launch and creates a second symlink at `/usr/local/bin/sp`. Harmless but noisy.

Fix: before showing the dialog or checking `/usr/local/bin`, walk `$PATH`. If `sp` is already a resolvable executable there, mark the UserDefaults didPrompt flag and return silently. Three install paths (brew/curl/direct) then converge on identical behaviour:

- brew install → `binary` stanza creates `/opt/homebrew/bin/sp` → first launch: silent no-op.
- curl install → no symlink → first launch: dialog appears.
- direct DMG download → no symlink → first launch: dialog appears.

Implementation: a static `spOnPath()` helper that splits `ProcessInfo.processInfo.environment["PATH"]` on `:` and probes each dir for an executable `sp`. Same idea as which(1), no Process spawn needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PathInstaller adds a helper that walks $PATH and returns the first executable `sp` it finds (or nil)
- [x] #2 runIfNeeded() short-circuits silently (and sets didPrompt) if spOnPath() finds anything
- [x] #3 Existing /usr/local/bin/sp behaviour preserved as a fallback path for users without brew's bin on $PATH
- [x] #4 Swift Testing case covers the new short-circuit path with a temp dir prepended to $PATH containing an executable file named sp
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added `PathInstaller.spOnPath()` — a `which(1)`-style helper that splits `$PATH` on `:` and returns the first executable named `sp` (or nil). Used as a Case-0 short-circuit in `runIfNeeded()` before the existing `/usr/local/bin/sp` check: if `sp` is already anywhere on PATH (Homebrew Cask binary stanza, manual install, prior PathInstaller run), the new code marks didPrompt=true and returns silently. The three install paths now converge:

- brew → `binary` stanza creates `/opt/homebrew/bin/sp` → first launch: silent.
- curl/direct → no symlink → first launch: dialog as before.

Visibility: `spOnPath` is `static` (was `private static`) so tests can call it without spinning up a real .app bundle. Documented in a comment why.

Edge cases the test suite pins:
- Happy path — sp executable in a dir on PATH is found and returned by full path.
- Returns nil when sp absent.
- Non-executable file named `sp` is ignored (matches which(1) semantics).
- Empty PATH segments (`::`, leading `:`, trailing `:`) are skipped rather than probed as `/sp`.

All four are `@MainActor` since PathInstaller is `@MainActor final class`; the test helpers use a `withPath` setenv/unsetenv pair to scope PATH mutations to a single test (ProcessInfo reads env at access time, so changes are immediately visible to `spOnPath`).

Verified: `swift test` → 14 tests, 0 failures. The four new PathInstaller cases passed in ~0.001-2.9s each (the longer ones are wall-clock from the parallel suite).

Caveat noted in code: `$PATH` here is whatever launchd seeded Scratchpad with — login PATH + macOS defaults. PATH entries from interactive shell rc files won't be visible unless they propagate through launchd's envvar layer too. For our case (brew at /opt/homebrew/bin which launchd sees, plus /usr/local/bin in macOS defaults), that's enough.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PathInstaller now silently no-ops when `sp` is already anywhere on $PATH, eliminating the redundant first-launch dialog that brew users were hitting after the Cask gained its `binary` stanza. Four new test cases cover the happy path, absent-sp, non-executable masquerade, and empty-PATH-segment edge cases. swift test: 14/14 green.
<!-- SECTION:FINAL_SUMMARY:END -->

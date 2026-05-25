---
id: TASK-38
title: Install full Xcode + reinstate test target
status: Done
assignee: []
created_date: '2026-05-24 07:03'
updated_date: '2026-05-25 10:11'
labels: []
milestone: M1 — Core receiver + display
dependencies: []
modified_files:
  - Package.swift
  - Tests/ScratchpadTests/InputHistoryTests.swift
priority: low
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Command Line Tools alone doesn't ship XCTest or the Swift Testing framework, so the test target was removed from Package.swift during initial scaffolding. Once full Xcode is installed (also required for TASK-37 codesign/notarization, currently deferred per decision-3), add the .testTarget back and restore Tests/ScratchpadTests/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Full Xcode installed
- [x] #2 Package.swift declares a .testTarget for ScratchpadTests
- [x] #3 swift test runs and passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Full Xcode 26.5 (Swift 6.3.2) now active. Reinstated the .testTarget in Package.swift and wrote the first real test suite against `InputHistory`.

Why InputHistory as the first thing under test:
- Pure-Foundation logic, no AppKit/SwiftUI surface — no NSApplication bootstrap required.
- Already exposed a `SCRATCHPAD_HISTORY_FILE` env-var seam (added back in TASK-11) — each test points at a fresh tmp file via `setenv` before constructing the instance, so test isolation is trivial.
- Has crisp TASK-11 invariants worth pinning: ignoredups, empty-skip, FIFO capacity cap, disk round-trip.

Framework choice: Swift Testing (`@Test` / `#expect`) over XCTest. Less ceremony, `@MainActor` attaches cleanly to individual tests (InputHistory is `@MainActor final class`), parameterized arguments-table support, bundled with Xcode 16+. Rationale captured in the test-file header.

Test target wiring: depends on the `Scratchpad` executable target (SwiftPM has supported testing executable targets since Swift 5.7; the `@main` attribute doesn't collide because Swift Testing injects its own runner entry). Uses `@testable import Scratchpad`.

Tests (4 cases, all pass):
- ignoresEmptyAndWhitespaceCommands — empty / whitespace-only adds are dropped.
- deduplicatesConsecutiveCommands — `["ls", "ls", "ls", "pwd", "ls"]` collapses to `["ls", "pwd", "ls"]`.
- evictsOldestWhenCapacityExceeded — at capacity+5 inserts, count clamps to capacity and the oldest 5 are evicted (test takes ~3.4s because it writes 10,005 entries to disk synchronously; acceptable for a one-shot CI run and surfaces real IO behaviour, so left as-is rather than mocked).
- persistsAcrossReinit — second InputHistory pointed at the same file reads back exactly what the first wrote (regression guard against trailing-newline or encoding-drift bugs).

Output of `swift test`:
  ✔ Test run with 4 tests in 0 suites passed after 3.392 seconds.

Note on the Xcode-26 + macOS-14 target combo: tests run on `arm64e-apple-macos14.0` per the Package.swift platforms line, consistent with the deployment target. No warnings or deprecations from the new toolchain.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Test target reinstated. Package.swift now declares `.testTarget(name: "ScratchpadTests", dependencies: ["Scratchpad"], path: "Tests/ScratchpadTests")` using Swift Testing. First suite covers InputHistory's four invariants (empty-skip, ignoredups, capacity cap, disk round-trip). `swift test` → 4 tests, 0 failures, ~3.4s wall time.
<!-- SECTION:FINAL_SUMMARY:END -->

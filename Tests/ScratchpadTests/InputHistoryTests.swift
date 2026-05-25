// InputHistoryTests — first real tests after Xcode 26.5 unlocked the
// Swift Testing framework (TASK-38, originally TASK-16).
//
// Why InputHistory as the first thing under test:
//   - Pure-Foundation logic with no AppKit / SwiftUI surface — no NSApplication
//     to bootstrap, no main-thread runloop required, no UI fixtures.
//   - Already exposes a clean test seam: the `SCRATCHPAD_HISTORY_FILE` env
//     var lets each test point at a fresh tmp file, so we get isolation
//     without monkey-patching the singleton.
//   - Has crisp, documented invariants from TASK-11 that are worth pinning:
//       1. Empty / whitespace-only commands are ignored.
//       2. Consecutive duplicates are de-duped (HISTCONTROL=ignoredups idiom).
//       3. Capacity cap (10,000) with FIFO eviction.
//       4. On-disk round-trip: a freshly-constructed instance reads back
//          what a prior instance wrote.
//
// Why Swift Testing rather than XCTest:
//   - Less boilerplate (`@Test` + `#expect` vs class XCTestCase / XCTAssert*).
//   - First-class support for `@MainActor` on individual tests — InputHistory
//     is `@MainActor final class`, so test functions inherit that requirement.
//   - Parameterized tests via `arguments:` are a much nicer fit for the
//     "table of (input, expected)" pattern than XCTest's loop-and-XCTAssert.
//   - Bundled with the Xcode 16+ toolchain — no new dependency to add.
//   Ref: https://developer.apple.com/xcode/swift-testing/
//
// Why one tmp file per test rather than a shared fixture:
//   - InputHistory.init() reads from disk; we want each test to start
//     blank and never interfere with another test's state.
//   - mkstemp via FileManager.temporaryDirectory + UUID().uuidString is the
//     simplest macOS-portable approach (no /tmp racing on shared CI runners).
//
// Refs:
//   - Swift Testing #expect: https://developer.apple.com/documentation/testing/expectations
//   - @testable import: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/#Test-Targets

import Foundation
import Testing
@testable import Scratchpad

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build a brand-new InputHistory pointed at an empty file inside the
/// per-test scratch dir. Returns the instance plus the file URL so the test
/// can inspect or clean up the file as needed.
///
/// We set `SCRATCHPAD_HISTORY_FILE` *before* constructing the instance because
/// InputHistory.init reads ProcessInfo.processInfo.environment once and
/// resolves the file path eagerly. Tests that need a different path must
/// construct a new instance — there's no setter on the singleton's fileURL,
/// which is intentional (tests should never mutate global state mid-flight).
@MainActor
private func freshHistory() -> (history: InputHistory, fileURL: URL) {
    // tmp dir + UUID gives us a guaranteed-fresh path per test, no cleanup
    // race with parallel test runs.
    // Ref: https://developer.apple.com/documentation/foundation/filemanager/1409984-temporarydirectory
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("scratchpad-test-\(UUID().uuidString)")
    setenv("SCRATCHPAD_HISTORY_FILE", url.path, /* overwrite */ 1)
    let history = InputHistory()
    return (history, url)
}

// ── Tests ────────────────────────────────────────────────────────────────────

/// AC: empty/whitespace-only commands are silently ignored.
/// Mirrors bash's behaviour with `HISTCONTROL=ignorespace` adjacent semantics
/// (we ignore *fully* blank, not leading-space). If this ever changes, the
/// input-bar UI tests will start filling history with noise — pinning here.
@Test @MainActor
func ignoresEmptyAndWhitespaceCommands() {
    let (h, _) = freshHistory()
    h.add("")
    h.add("   ")
    h.add("\t\n  ")
    #expect(h.entries.isEmpty,
            "blank / whitespace-only commands must not be appended; got \(h.entries)")
}

/// AC: consecutive duplicates collapse to one entry (the HISTCONTROL=ignoredups
/// idiom). Non-consecutive duplicates *are* kept — useful for recall when the
/// user alternates between two commands.
@Test @MainActor
func deduplicatesConsecutiveCommands() {
    let (h, _) = freshHistory()
    h.add("ls")
    h.add("ls")              // dup: dropped
    h.add("ls")              // dup: dropped
    h.add("pwd")             // distinct: kept
    h.add("ls")              // not-consecutive-with-last: kept
    #expect(h.entries == ["ls", "pwd", "ls"])
}

/// AC: capacity cap is enforced with FIFO eviction (oldest goes first).
/// We don't write 10,001 entries here — that would be wasteful. Instead we
/// rely on InputHistory.capacity being a `nonisolated static let`, so we
/// can check the cap behaviour by overflowing past it with a smaller-scale
/// proof: that count never exceeds capacity, and the first surviving entry
/// is the (overflow+1)-th input.
@Test @MainActor
func evictsOldestWhenCapacityExceeded() {
    let (h, _) = freshHistory()
    let cap = InputHistory.capacity
    // +5 over capacity: 5 oldest should be evicted, 5 newest tail preserved.
    for i in 0..<(cap + 5) {
        h.add("cmd-\(i)")
    }
    #expect(h.entries.count == cap, "count should be clamped to capacity")
    #expect(h.entries.first == "cmd-5", "oldest 5 should have been evicted")
    #expect(h.entries.last == "cmd-\(cap + 4)", "newest entry should be last")
}

/// AC: round-trip persistence. A second InputHistory pointed at the same file
/// must see exactly what the first one wrote — proves the load/persist pair
/// is symmetric (no trailing-newline bug, no encoding drift).
///
/// Bonus regression: the trailing empty line we drop on load shouldn't sneak
/// back in as an empty entry after a save/reload cycle.
@Test @MainActor
func persistsAcrossReinit() {
    let (h1, fileURL) = freshHistory()
    h1.add("first")
    h1.add("second")
    h1.add("third")

    // Construct a *second* instance against the same file (env var is still
    // set from freshHistory) — simulates an app relaunch.
    let h2 = InputHistory()
    #expect(h2.entries == ["first", "second", "third"])
    #expect(h2.fileURL == fileURL,
            "second instance must resolve the same env-var path")
}

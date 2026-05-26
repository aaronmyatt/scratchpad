// PathInstallerTests — covers the $PATH-walk helper added in TASK-47.
//
// We can't easily test runIfNeeded() end-to-end in unit tests because it
// requires Bundle.main.bundlePath to end in ".app" (i.e. running from a real
// .app bundle, not via `swift test`). What we *can* test cheaply is the pure
// PATH-walking helper that gates the new short-circuit — that's the part
// most likely to regress on edge cases like empty PATH segments and
// non-executable files masquerading as candidates.
//
// Refs:
//   - which(1) semantics this helper mirrors: https://ss64.com/mac/which.html
//   - FileManager.isExecutableFile: https://developer.apple.com/documentation/foundation/filemanager/1413758-isexecutablefile

import Foundation
import Testing
@testable import Scratchpad

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Make an executable file with the given name in a freshly-created tmp dir.
/// Returns the dir's path (caller prepends it to PATH) and the file's path
/// (caller asserts on it).
private func makeExecutable(named name: String,
                            contents: String = "#!/bin/sh\nexit 0\n") -> (dir: String, file: String) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pathinstaller-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent(name)
    try! contents.data(using: .utf8)!.write(to: file)
    // mode 0755 so isExecutableFile returns true. Without the chmod the
    // helper would (correctly) skip the file as non-executable, which is
    // the *opposite* of what we're trying to test.
    try! FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: file.path
    )
    return (dir.path, file.path)
}

/// Set $PATH for the duration of a test, restoring the previous value on exit.
/// ProcessInfo reads `environment` on access, so `setenv` changes are picked
/// up by `spOnPath()` immediately — no caching to invalidate.
private func withPath<T>(_ newPath: String, body: () -> T) -> T {
    let previous = ProcessInfo.processInfo.environment["PATH"]
    setenv("PATH", newPath, /* overwrite */ 1)
    defer {
        if let prev = previous {
            setenv("PATH", prev, 1)
        } else {
            unsetenv("PATH")
        }
    }
    return body()
}

// ── Tests ────────────────────────────────────────────────────────────────────

/// Happy path: sp exists in a directory on PATH → spOnPath returns its full
/// path. This is the case that fires when Homebrew's `binary` Cask stanza
/// has put sp at /opt/homebrew/bin/sp and the user launches Scratchpad.
@Test @MainActor
func findsSpWhenPresentOnPath() {
    let (dir, file) = makeExecutable(named: "sp")
    let resolved = withPath("\(dir):/usr/bin:/bin") {
        PathInstaller.spOnPath()
    }
    #expect(resolved == file,
            "expected to find sp at \(file), got \(resolved ?? "<nil>")")
}

/// No sp anywhere on PATH → returns nil. The dialog flow downstream of this
/// helper relies on the nil signal to mean "user hasn't installed sp via any
/// channel; show the dialog."
@Test @MainActor
func returnsNilWhenSpAbsent() {
    // Use a PATH containing only an empty tmp dir + standard system paths
    // (which on a CI box won't have sp unless someone *put* one there).
    let emptyDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("empty-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
    let resolved = withPath(emptyDir.path) {
        PathInstaller.spOnPath()
    }
    #expect(resolved == nil)
}

/// A non-executable file named `sp` on PATH should NOT be considered a
/// match. Otherwise we'd skip the install dialog because someone happened
/// to have a text file called `sp` in their PATH — silly, but the kind of
/// edge case which(1) gets right and we should too.
@Test @MainActor
func ignoresNonExecutableSpFiles() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nonexec-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("sp")
    try! "I'm not executable".data(using: .utf8)!.write(to: file)
    // Mode 0644 — readable but not executable.
    try! FileManager.default.setAttributes(
        [.posixPermissions: 0o644], ofItemAtPath: file.path
    )
    let resolved = withPath(dir.path) {
        PathInstaller.spOnPath()
    }
    #expect(resolved == nil,
            "non-executable file shouldn't count as sp on PATH; got \(resolved ?? "<nil>")")
}

/// Empty PATH segments (typically a trailing `:` or `::` in PATH) must not
/// be probed as `/sp` against the filesystem root — that would be both
/// nonsensical and (on a writable / pre-SIP system) a real file.
@Test @MainActor
func handlesEmptyPathSegments() {
    let (dir, file) = makeExecutable(named: "sp")
    // PATH with leading, mid, and trailing empties — all three should be skipped.
    let resolved = withPath(":\(dir)::") {
        PathInstaller.spOnPath()
    }
    #expect(resolved == file)
}

// InputHistory — persistent history of shell commands submitted via the input bar.
//
// Scope (M5, TASK-11):
//   - Capped at `capacity` entries (10,000) with FIFO eviction.
//   - Persists to a plain-text file (one command per line), atomically on
//     each append. Plain text rather than JSONL because: commands are
//     single-line by construction (the TextField is single-line), and a
//     plain file is grep-able and editable with any text editor.
//   - De-duplicates consecutive identical entries (à la bash with
//     `HISTCONTROL=ignoredups`). A user holding Enter to re-run the same
//     command shouldn't fill 10k slots with one command.
//
// File location:
//   - `~/Library/Application Support/Scratchpad/input_history`
//     (or override with the `SCRATCHPAD_HISTORY_FILE` env var)
//
// Refs:
//   - FileManager directory URLs: https://developer.apple.com/documentation/foundation/filemanager/1409774-urls
//   - Atomic writes:               https://developer.apple.com/documentation/foundation/data/writingoptions/atomic
//
// Usage examples:
//   InputHistory.shared.add("jq .")
//   InputHistory.shared.entries.last       // -> "jq ."
//   InputHistory.shared.entries.count

import Foundation

@MainActor
final class InputHistory {
    static let shared = InputHistory()

    /// Hard cap — keeps the file bounded (10k * ~100B avg ≈ 1 MiB).
    nonisolated static let capacity = 10_000

    /// Oldest first, most recent last. Public read so the view can compute
    /// recall positions; mutation goes through `add` to enforce invariants.
    private(set) var entries: [String] = []

    /// Path to the on-disk history file. Resolved once at init.
    let fileURL: URL

    init() {
        let fm = FileManager.default

        // Allow an env-var override for tests / power users. Same pattern as
        // SCRATCHPAD_PORT — single shell-env knob configures both server and
        // tools, and tests can point at a tmp file.
        if let override = ProcessInfo.processInfo.environment["SCRATCHPAD_HISTORY_FILE"],
           !override.isEmpty {
            self.fileURL = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            // Standard macOS app-data location. Created if missing.
            let appSupport = fm.urls(for: .applicationSupportDirectory,
                                     in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
            let dir = appSupport.appending(path: "Scratchpad")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appending(path: "input_history")
        }
        load()
    }

    // ── Mutation ─────────────────────────────────────────────────────────

    /// Append a new command. Ignored if empty/whitespace or identical to the
    /// last entry. Writes the file synchronously on every successful add —
    /// 10k lines * ~100 B = ~1 MiB worst case, well below the threshold where
    /// rewrite cost would matter on a modern SSD. Simpler than incremental
    /// append + periodic compaction.
    func add(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if entries.last == trimmed { return } // ignoredups
        entries.append(trimmed)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        persist()
    }

    // ── Persistence ──────────────────────────────────────────────────────

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        // Plain text, one entry per line. Preserve empty middle lines just in
        // case (we never write them, but a hand-edited file might), then drop
        // empties to keep recall clean.
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "" { lines.removeLast() }
        entries = lines.filter { !$0.isEmpty }
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    private func persist() {
        // Atomic write: Foundation writes to a temp file then renames, so a
        // crash mid-write doesn't leave a half-written history file.
        let text = entries.joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: fileURL, options: .atomic)
    }
}

// EventStore — unified history of everything shown in the display area.
//
// Replaces the older DumpStore (which only held the most-recent dump). Each
// event is either a raw dump received over a transport, OR a shell command
// result produced by the input bar. The store is the single source of truth
// for the display area; back/forward navigation (TASK-22) and copy (TASK-23)
// both read from here.
//
// Scope (M6, TASK-21):
//   - In-memory ring buffer, capped at `capacity`.
//   - Monotonic ids — stable across FIFO eviction so view code can pin to a
//     specific event without index drift.
//   - Two payload representations per event:
//       * `displayText`  — the human-readable string shown in the dump area.
//       * `pipeData`     — the raw bytes piped to the next shell command's
//                          stdin when this event is the active one. For dumps
//                          that's the body; for command results it's the
//                          subprocess's stdout (no '$ cmd' header noise).
//
// Persistence across launches is deliberately NOT in v1. Easy follow-up.
//
// Refs:
//   - @Observable: https://developer.apple.com/documentation/observation/observable()
//
// Usage examples (inside the app):
//   EventStore.shared.appendDump("hi".data(using: .utf8)!)
//   EventStore.shared.appendCommandResult(command: "wc -c",
//                                         result: shellRunnerResult,
//                                         displayText: formatted)
//   EventStore.shared.events.last?.displayText

import Foundation
import Observation

@MainActor
@Observable
final class EventStore {
    static let shared = EventStore()

    // ── Types ────────────────────────────────────────────────────────────

    enum Kind: Sendable {
        case dump
        case commandResult(
            command: String,
            exitCode: Int32,
            timedOut: Bool,
            truncated: Bool
        )
    }

    struct Event: Identifiable, Sendable {
        let id: Int
        let timestamp: Date
        let kind: Kind
        let displayText: String
        let pipeData: Data

        /// Text to place on the clipboard when this event is copied.
        ///
        /// Dumps copy verbatim. Command results copy displayText *minus the
        /// leading "$ <command>" line* — that header is a display affordance
        /// to remind the user what produced the output, not part of the
        /// output itself. Pasting `$ jq .a\n{...}` into another tool would
        /// be cruft; the user wants `{...}`.
        ///
        /// Trailing decorations like `[exit N]`, `--- stderr ---`, and
        /// `[output truncated]` are *kept* — they're real information about
        /// the command's result that the user typically wants alongside the
        /// output when pasting elsewhere.
        var copyText: String {
            switch kind {
            case .dump:
                return displayText
            case .commandResult:
                if displayText.hasPrefix("$ "),
                   let newlineIdx = displayText.firstIndex(of: "\n") {
                    return String(displayText[displayText.index(after: newlineIdx)...])
                }
                return displayText
            }
        }
    }

    // ── Tunables ─────────────────────────────────────────────────────────

    /// Max events retained. 100 is generous for an interactive session and
    /// keeps total RAM trivial (each event is bounded by transport / output
    /// caps elsewhere: 16 MiB per dump, 4 MiB per command stdout).
    nonisolated static let capacity = 100

    // ── State ────────────────────────────────────────────────────────────

    private(set) var events: [Event] = []
    private var nextId: Int = 0

    // ── Mutations ────────────────────────────────────────────────────────

    /// Record an incoming dump. `payload` is the raw bytes; we derive a
    /// displayable string via best-effort UTF-8 decoding (with a byte-count
    /// placeholder for binary).
    func appendDump(_ payload: Data) {
        let text: String = String(data: payload, encoding: .utf8)
            ?? "<\(payload.count) bytes of non-UTF-8 data>"
        append(Event(
            id: nextId,
            timestamp: Date(),
            kind: .dump,
            displayText: text,
            pipeData: payload
        ))
    }

    /// Record a finished shell command run. `displayText` is the fully
    /// formatted string the view will show ('$ cmd' header, stderr if
    /// relevant, exit-code/timeout/truncation banners). `result.stdout` is
    /// kept as the pipeData so the user can chain another command against
    /// just the subprocess's output, not the formatted text.
    func appendCommandResult(
        command: String,
        result: ShellRunner.Result,
        displayText: String
    ) {
        append(Event(
            id: nextId,
            timestamp: Date(),
            kind: .commandResult(
                command: command,
                exitCode: result.exitCode,
                timedOut: result.timedOut,
                truncated: result.truncated
            ),
            displayText: displayText,
            pipeData: result.stdout
        ))
    }

    private func append(_ event: Event) {
        events.append(event)
        // `&+` is overflow-wrapping addition; we'll never get near Int.max in
        // practice, but it costs nothing to be defensive.
        nextId &+= 1
        if events.count > Self.capacity {
            // FIFO eviction. Any view state pinning a now-evicted event id
            // must reset to "follow newest" — see ContentView's onChange.
            events.removeFirst(events.count - Self.capacity)
        }
    }

    // ── Derived views ────────────────────────────────────────────────────

    /// Count of dump events only — drives the header counter in ContentView.
    var dumpCount: Int {
        events.reduce(0) { acc, event in
            if case .dump = event.kind { return acc + 1 }
            return acc
        }
    }
}

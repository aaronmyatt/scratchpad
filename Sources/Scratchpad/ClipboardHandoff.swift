// ClipboardHandoff — escape hatch from the inline-run model into the user's
// own terminal, via the system clipboard.
//
// Scope (M6, TASK-44): the inline `ShellRunner` path uses `/bin/sh -c <cmd>`
// with captured stdout/stderr — perfect for `jq`, `wc`, `grep`, anything
// that runs to completion and emits text. It is useless for tty-bound
// programs (`vim`, `less`, `top`, `fzf`, `nvim`, `nano`, ncurses anything),
// which either hang or fail silently without a real terminal.
//
// Earlier iterations of TASK-44 spawned a terminal app via `open -a` and
// a wrapper script. That approach worked but bloated Scratchpad's scope:
// terminal-app detection, cross-shell wrapper scripts, window hide/show
// orchestration, and a long tail of edge cases per terminal flavour.
//
// The simpler model: when the user hits ⌘↩, stage the dump to a temp file
// and copy the *effective* command line to the system clipboard. The user
// pastes into whatever terminal they already have open. Scratchpad does
// no spawning, owns no terminal-app logic, and the user retains complete
// control over where the command runs.
//
// Threat model (decision-2 preserved):
//   - Dump bytes are written to a 0600 temp file. The file PATH is
//     embedded into the copied command; the BYTES are never inlined
//     into shell syntax.
//   - The user's typed command is concatenated verbatim with the path
//     — same posture as the inline ShellRunner: the command is code
//     the user typed, the dump is data accessible via a quoted path.
//
// Refs:
//   - NSPasteboard:    https://developer.apple.com/documentation/appkit/nspasteboard
//   - FileManager.createFile: https://developer.apple.com/documentation/foundation/filemanager/1410695-createfile
//   - decision-2:      backlog/decisions/decision-2
//
// Usage:
//   let path = try ClipboardHandoff.stageDump(payload: dumpBytes)
//   let cmd  = ClipboardHandoff.clipboardCommand(typedCommand: "vim", dumpPath: path)
//   NSPasteboard.general.setString(cmd, forType: .string)

import Foundation

enum ClipboardHandoff {

    // ── Errors ───────────────────────────────────────────────────────────

    enum Failure: Error {
        case writeFailed(String)
    }

    // ── Staging the dump ─────────────────────────────────────────────────

    /// Write the dump bytes to a fresh 0600 temp file and return the path.
    ///
    /// The file lives until macOS's `/var/folders/.../T/` cleanup reaps it
    /// — we don't engineer an explicit lifecycle. The copied command is
    /// the user's to use whenever; pretending we know when they're done
    /// with it would add complexity for no real benefit.
    ///
    /// 0600 perms ensure that no other local user can read the dump —
    /// matches decision-2's general posture of "data Scratchpad accepts
    /// stays as private as we can make it without ceremony".
    nonisolated static func stageDump(payload: Data) throws -> String {
        let tmpDir = NSTemporaryDirectory()
        // UUID gives 36 chars of collision-resistant entropy — vastly
        // more than `mktemp`'s six-char XXXXXX template, and easier to
        // use without bridging out to a C function.
        let path = (tmpDir as NSString).appendingPathComponent(
            "scratchpad-dump-\(UUID().uuidString)"
        )
        // createFile + posixPermissions sets perms atomically with
        // creation — no race window between create and chmod.
        let ok = FileManager.default.createFile(
            atPath: path,
            contents: payload,
            attributes: [.posixPermissions: NSNumber(value: 0o600)]
        )
        guard ok else {
            throw Failure.writeFailed("could not write dump to \(path)")
        }
        return path
    }

    // ── Command construction ─────────────────────────────────────────────

    /// Build the command that should land on the clipboard when the user
    /// hits ⌘↩ with `typedCommand` in the input bar.
    ///
    /// Rules:
    ///   - Empty typedCommand → quoted dump path on its own. Useful if
    ///     the user is mid-command in their terminal and just wants to
    ///     paste a path argument (e.g. they've typed `vim ` and want
    ///     to complete with the path).
    ///   - typedCommand references `$SCRATCHPAD_DUMP_FILE`, `${...}`,
    ///     `$F`, or `${F}` → substitute the literal quoted path in
    ///     place of each reference. There's no wrapper script defining
    ///     `$F` anymore, so the copied command must be runnable in any
    ///     vanilla shell with no setup.
    ///   - Otherwise → append the quoted path as the last positional
    ///     argument. Most CLI tools accept a file path as a positional;
    ///     this matches the inline-run mode's "dump is the implicit
    ///     input" semantics in a way that works for TTY commands too
    ///     (vim, less, nano, etc.).
    nonisolated static func clipboardCommand(
        typedCommand: String,
        dumpPath: String
    ) -> String {
        let quotedPath = singleQuoteShell(dumpPath)
        let trimmed = typedCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return quotedPath
        }
        if commandReferencesDumpVar(trimmed) {
            return substituteDumpVar(in: trimmed, with: quotedPath)
        }
        return "\(trimmed) \(quotedPath)"
    }

    /// Live preview shown in the input-bar caption. Same rules as
    /// `clipboardCommand` but with a placeholder where the real path
    /// would go — temp paths are noisy in a 14pt caption and the user
    /// gets nothing from staring at `/var/folders/9k/...`.
    nonisolated static func clipboardPreview(
        command: String,
        placeholder: String = "‹dump-file›"
    ) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return placeholder }
        if commandReferencesDumpVar(trimmed) {
            return substituteDumpVar(in: trimmed, with: placeholder)
        }
        return "\(trimmed) \(placeholder)"
    }

    // ── Variable handling ────────────────────────────────────────────────

    /// True iff `s` references the dump via any of the supported forms:
    /// `$SCRATCHPAD_DUMP_FILE`, `${SCRATCHPAD_DUMP_FILE}`, `$F`, `${F}`.
    nonisolated static func commandReferencesDumpVar(_ s: String) -> Bool {
        if s.contains("$SCRATCHPAD_DUMP_FILE") { return true }
        if s.contains("${SCRATCHPAD_DUMP_FILE}") { return true }
        if s.contains("${F}") { return true }
        return containsBareDollarF(s)
    }

    /// Replace every supported dump-var reference in `s` with `replacement`.
    /// Order matters: `${SCRATCHPAD_DUMP_FILE}` and `${F}` must run before
    /// the bare `$SCRATCHPAD_DUMP_FILE` and `$F` rules, otherwise the
    /// trailing `}` would be left orphaned in the output.
    nonisolated private static func substituteDumpVar(
        in s: String,
        with replacement: String
    ) -> String {
        var out = s
        out = out.replacingOccurrences(of: "${SCRATCHPAD_DUMP_FILE}", with: replacement)
        out = out.replacingOccurrences(of: "${F}", with: replacement)
        out = out.replacingOccurrences(of: "$SCRATCHPAD_DUMP_FILE", with: replacement)
        out = replaceBareDollarF(in: out, with: replacement)
        return out
    }

    /// Word-aware check for `$F` — must NOT match `$FOO`, `$FILE`, etc.
    /// POSIX identifier chars after `F` mean it's a different variable.
    nonisolated private static func containsBareDollarF(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == UInt8(ascii: "$") && bytes[i + 1] == UInt8(ascii: "F") {
                if !isIdentByte(i + 2 < bytes.count ? bytes[i + 2] : nil) {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    /// Replace every word-boundary `$F` in `s` with `replacement`.
    /// Walks the string left-to-right so the replacement itself can't
    /// accidentally create a new `$F` sequence (the replacement starts
    /// with a single quote, not a `$`).
    nonisolated private static func replaceBareDollarF(
        in s: String,
        with replacement: String
    ) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            // Need at least `$F` plus the right boundary check.
            if i + 1 < chars.count, chars[i] == "$", chars[i + 1] == "F" {
                let nextChar: Character? = (i + 2 < chars.count) ? chars[i + 2] : nil
                let nextByte: UInt8? = nextChar.flatMap { $0.asciiValue }
                if !isIdentByte(nextByte) {
                    out.append(replacement)
                    i += 2
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    /// True iff `b` is a POSIX shell identifier byte: `[A-Za-z0-9_]`.
    /// nil (end of string) is treated as non-identifier so `$F` at the
    /// very end of the input matches as the alias.
    nonisolated private static func isIdentByte(_ b: UInt8?) -> Bool {
        guard let b else { return false }
        return (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
            || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
            || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
            || b == UInt8(ascii: "_")
    }

    // ── Shell quoting ────────────────────────────────────────────────────

    /// POSIX single-quote escape: wraps the string in `'...'` and replaces
    /// any embedded `'` with `'\''`. Reference idiom — same trick `printf %q`
    /// uses internally. Necessary so paths containing spaces, `$`, `;`,
    /// etc. are passed verbatim to the receiving shell.
    /// Ref: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_02_02
    nonisolated private static func singleQuoteShell(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "'", with: #"'\''"#)
        return "'\(escaped)'"
    }
}

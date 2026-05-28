// ClipboardHandoffTests — TASK-44 (post-pivot).
//
// What's covered:
//   1. `stageDump` produces a 0600 file containing the exact payload.
//   2. `clipboardCommand` rules:
//        - empty command → bare quoted path
//        - explicit $F / $SCRATCHPAD_DUMP_FILE → substituted with quoted path
//        - otherwise → command followed by quoted path
//   3. `clipboardPreview` follows the same rules using a placeholder.
//   4. `commandReferencesDumpVar` recognises the supported forms and
//      rejects `$FOO`, bare `F`, etc.
//   5. Path-quoting handles awkward chars (single quotes, spaces).
//
// What's NOT covered:
//   - NSPasteboard interaction — that lives in ContentView and is a
//     trivial three-line dance over AppKit.
//
// Refs:
//   - Swift Testing #expect: https://developer.apple.com/documentation/testing/expectations

import Foundation
import Testing
@testable import Scratchpad

// ── stageDump ────────────────────────────────────────────────────────────────

@Suite("ClipboardHandoff.stageDump")
struct StageDumpTests {

    @Test("Writes 0600 file with the exact payload")
    func writesFile() throws {
        let payload = Data("the quick brown fox\n".utf8)
        let path = try ClipboardHandoff.stageDump(payload: payload)
        defer { try? FileManager.default.removeItem(atPath: path) }

        // ── perms = 0600 ───────────────────────────────────────────────
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)

        // ── content round-trips ────────────────────────────────────────
        let back = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(back == payload)
    }

    @Test("Successive calls produce distinct paths")
    func uniquePaths() throws {
        let a = try ClipboardHandoff.stageDump(payload: Data("a".utf8))
        let b = try ClipboardHandoff.stageDump(payload: Data("b".utf8))
        defer {
            try? FileManager.default.removeItem(atPath: a)
            try? FileManager.default.removeItem(atPath: b)
        }
        #expect(a != b)
    }
}

// ── clipboardCommand ─────────────────────────────────────────────────────────

@Suite("ClipboardHandoff.clipboardCommand")
struct ClipboardCommandTests {

    @Test("Empty command copies bare quoted path")
    func emptyCommand() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "",
            dumpPath: "/tmp/dump-xyz"
        )
        #expect(cmd == "'/tmp/dump-xyz'")
    }

    @Test("Whitespace-only command treated as empty")
    func whitespaceOnly() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "   \t\n",
            dumpPath: "/tmp/dump-xyz"
        )
        #expect(cmd == "'/tmp/dump-xyz'")
    }

    @Test("Plain command: path appended as positional arg")
    func plainCommandAppendsPath() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "vim",
            dumpPath: "/tmp/dump-xyz"
        )
        #expect(cmd == "vim '/tmp/dump-xyz'")
    }

    @Test("Filter command: path appended")
    func filterAppendsPath() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "jq .",
            dumpPath: "/tmp/d"
        )
        #expect(cmd == "jq . '/tmp/d'")
    }

    @Test("$F is substituted with quoted path")
    func aliasSubstituted() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "cat $F | fzf",
            dumpPath: "/tmp/d"
        )
        #expect(cmd == "cat '/tmp/d' | fzf")
    }

    @Test("$SCRATCHPAD_DUMP_FILE is substituted")
    func explicitVarSubstituted() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "diff $SCRATCHPAD_DUMP_FILE other.txt",
            dumpPath: "/tmp/d"
        )
        #expect(cmd == "diff '/tmp/d' other.txt")
    }

    @Test("${F} braced form is substituted")
    func bracedAliasSubstituted() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "wc -c ${F}",
            dumpPath: "/tmp/d"
        )
        #expect(cmd == "wc -c '/tmp/d'")
    }

    @Test("${SCRATCHPAD_DUMP_FILE} braced form is substituted")
    func bracedExplicitVarSubstituted() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "wc -c ${SCRATCHPAD_DUMP_FILE}",
            dumpPath: "/tmp/d"
        )
        #expect(cmd == "wc -c '/tmp/d'")
    }

    @Test("$FOO is left untouched and path still appended")
    func unrelatedVarLeftAlone() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "echo $FOO",
            dumpPath: "/tmp/d"
        )
        // No substitution should happen on $FOO; since the command
        // doesn't reference our dump var, the path is appended.
        #expect(cmd == "echo $FOO '/tmp/d'")
    }

    @Test("Multiple $F references are all substituted")
    func multipleAliasReferences() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "diff $F $F.bak",
            dumpPath: "/tmp/d"
        )
        // First $F → '/tmp/d'. Second $F is at position where the
        // next char is '.', which is a non-identifier char, so it
        // also matches as the alias.
        #expect(cmd == "diff '/tmp/d' '/tmp/d'.bak")
    }

    @Test("Paths with spaces are quoted safely")
    func quotesSpaces() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "vim",
            dumpPath: "/tmp/has space/dump"
        )
        #expect(cmd == "vim '/tmp/has space/dump'")
    }

    @Test("Paths with single quotes are escaped POSIX-style")
    func escapesSingleQuotes() {
        let cmd = ClipboardHandoff.clipboardCommand(
            typedCommand: "vim",
            dumpPath: "/tmp/it's-mine"
        )
        // Classic POSIX close-quote / backslash-quote / reopen idiom.
        #expect(cmd == #"vim '/tmp/it'\''s-mine'"#)
    }
}

// ── clipboardPreview ─────────────────────────────────────────────────────────

@Suite("ClipboardHandoff.clipboardPreview")
struct ClipboardPreviewTests {

    @Test("Empty command shows just the placeholder")
    func emptyShowsPlaceholder() {
        #expect(ClipboardHandoff.clipboardPreview(command: "") == "‹dump-file›")
    }

    @Test("Plain command: placeholder appended")
    func plainAppendsPlaceholder() {
        #expect(ClipboardHandoff.clipboardPreview(command: "vim") == "vim ‹dump-file›")
    }

    @Test("$F is substituted with placeholder")
    func aliasSubstituted() {
        let prev = ClipboardHandoff.clipboardPreview(command: "cat $F | fzf")
        #expect(prev == "cat ‹dump-file› | fzf")
    }

    @Test("Custom placeholder respected")
    func customPlaceholder() {
        let prev = ClipboardHandoff.clipboardPreview(
            command: "vim",
            placeholder: "<FILE>"
        )
        #expect(prev == "vim <FILE>")
    }

    @Test("Preview shape matches what clipboardCommand would produce")
    func previewAndCommandAgree() {
        // The preview must not lie about what gets copied. Use a
        // quoted-path placeholder so the strings are directly
        // comparable; the rule shape is what matters.
        let cmd = "jq ."
        let placeholder = "'/tmp/example'"
        let prev = ClipboardHandoff.clipboardPreview(
            command: cmd,
            placeholder: placeholder
        )
        let actual = ClipboardHandoff.clipboardCommand(
            typedCommand: cmd,
            dumpPath: "/tmp/example"
        )
        #expect(prev == actual)
    }
}

// ── commandReferencesDumpVar ────────────────────────────────────────────────

@Suite("ClipboardHandoff.commandReferencesDumpVar")
struct DumpVarReferenceTests {

    @Test("Recognises every supported form")
    func recognised() {
        #expect(ClipboardHandoff.commandReferencesDumpVar("cat $SCRATCHPAD_DUMP_FILE"))
        #expect(ClipboardHandoff.commandReferencesDumpVar("cat ${SCRATCHPAD_DUMP_FILE}"))
        #expect(ClipboardHandoff.commandReferencesDumpVar("cat $F"))
        #expect(ClipboardHandoff.commandReferencesDumpVar("cat ${F}"))
        #expect(ClipboardHandoff.commandReferencesDumpVar("$F | fzf"))
        // $F at end of string with no trailing char.
        #expect(ClipboardHandoff.commandReferencesDumpVar("ls $F"))
    }

    @Test("Rejects unrelated variables and plain letters")
    func rejected() {
        #expect(!ClipboardHandoff.commandReferencesDumpVar("echo $FOO"))
        #expect(!ClipboardHandoff.commandReferencesDumpVar("grep -F pattern"))
        #expect(!ClipboardHandoff.commandReferencesDumpVar("find ."))
        #expect(!ClipboardHandoff.commandReferencesDumpVar(""))
        #expect(!ClipboardHandoff.commandReferencesDumpVar("$FILE"))
    }
}

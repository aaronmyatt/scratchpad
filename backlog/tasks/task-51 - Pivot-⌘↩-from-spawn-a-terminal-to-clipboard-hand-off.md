---
id: TASK-51
title: Pivot ⌘↩ from spawn-a-terminal to clipboard hand-off
status: Done
assignee:
  - '@aaron'
created_date: '2026-05-27 05:48'
updated_date: '2026-05-27 06:04'
labels:
  - retroactive
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - >-
    backlog/tasks/task-44 -
    Input-bar-Cmd-Enter-spawns-users-SHELL-in-a-real-terminal.md
  - >-
    backlog/decisions/decision-2 -
    Threat-model-and-safety-defaults-for-the-shell-input-bar.md
modified_files:
  - Sources/Scratchpad/ClipboardHandoff.swift
  - Sources/Scratchpad/ContentView.swift
  - Tests/ScratchpadTests/ClipboardHandoffTests.swift
priority: medium
ordinal: 62.5
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retroactive ticket capturing the architectural pivot made during the TASK-44 conversation.

## Motivation

TASK-44 v1 spawned a terminal app to host the user's $SHELL when they hit ⌘↩. That worked but bloated Scratchpad's scope considerably:

- Terminal-app detection (iTerm / Ghostty / Warp / Alacritty probing, `$TERMINAL_APP` env handling, Terminal.app fallback).
- Wrapper-script generation in the user's shell.
- `open -a` Process spawning + termination-status handling.
- Window hide/show orchestration on hand-off.
- `$F` / `$SCRATCHPAD_DUMP_FILE` shell-var exports inside the wrapper.

User testing revealed the spawn flow didn't feel right ("not very ergonomic"). The simpler model:

**⌘↩ stages the dump to a 0600 temp file and copies a ready-to-paste command line — with the file path inlined — to the system clipboard.** The user pastes into whatever terminal they already have open.

Net effect: Scratchpad does no spawning, owns no terminal-app logic, and the user retains complete control over where the command runs.

## Behaviour

When ⌘↩ fires:

1. The current dump (whatever event is displayed) is written to a fresh `mkstemp`-style file under `NSTemporaryDirectory()`, with 0600 perms.
2. The "effective command" is built per these rules and copied to `NSPasteboard.general`:
   - Empty input → bare quoted path (`'/tmp/scratchpad-dump-xyz'`) — usable as a paste-as-argument for a half-typed terminal command.
   - Input references `$F` / `${F}` / `$SCRATCHPAD_DUMP_FILE` / `${SCRATCHPAD_DUMP_FILE}` → each reference is substituted with the literal quoted path. (There's no wrapper script defining those vars anymore, so the copied command must be runnable in a vanilla shell with no setup.)
   - Otherwise → `<cmd> '<quoted-path>'` (path appended as last positional argument).
3. POSIX single-quote escaping on the path so awkward chars (spaces, apostrophes) are safe.
4. Scratchpad window is NOT hidden — user can compare what they typed against what got copied.

## What got deleted

- `TerminalLauncher.swift` (entire file) and its 15-test suite.
- Terminal-app detection, wrapper-script generation, `open -a` Process spawning, `WindowController.shared.hide()` call on hand-off.
- Shell-export of `$F` (no wrapper to do it in; substitution happens at clipboard-build time instead).

## What replaced it

`Sources/Scratchpad/ClipboardHandoff.swift` (≈210 lines, mostly comments) — pure-logic helper exposing `stageDump`, `clipboardCommand`, `clipboardPreview`, `commandReferencesDumpVar`. No SwiftUI / AppKit dependencies; testable without booting NSApplication.

## Threat model

decision-2 is preserved: dump BYTES are never substituted into shell syntax; only the file PATH is. The user's typed command is interpolated verbatim (they typed it). Same posture as the inline ShellRunner path.

## Refs

- TASK-44 (parent feature)
- TASK-50 (live invocation preview — surfaces the path-not-bytes asymmetry visibly)
- decision-2 (threat model, unchanged)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌘↩ copies a ready-to-paste command line to NSPasteboard.general; no terminal app is launched, no subprocess spawned
- [ ] #2 Dump is staged to a 0600 file under NSTemporaryDirectory() before the command is assembled
- [ ] #3 Empty input copies the bare quoted dump-file path on its own
- [ ] #4 Plain commands get the path appended as a positional arg: 'vim' → vim '/tmp/...'
- [ ] #5 $F / ${F} / $SCRATCHPAD_DUMP_FILE / ${SCRATCHPAD_DUMP_FILE} references in the typed command are substituted with the literal quoted path
- [ ] #6 Word-boundary detection on $F: $FOO / $FILE / grep -F are NOT mistaken for the alias
- [ ] #7 POSIX single-quote escaping handles paths containing spaces and apostrophes safely
- [ ] #8 Scratchpad window stays visible (no hide on ⌘↩) so the user can compare typed-input vs copied-output
- [ ] #9 TerminalLauncher.swift removed entirely; ClipboardHandoff.swift is its replacement and is dependency-free of AppKit / SwiftUI
- [ ] #10 Existing inline ↩ behaviour is unchanged
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## What was built

Replaced `TerminalLauncher` with `ClipboardHandoff`. The new module exposes:

- `stageDump(payload:) -> String` — writes the dump to a fresh 0600 temp file, returns the path. UUID-suffixed filename for collision resistance.
- `clipboardCommand(typedCommand:dumpPath:) -> String` — builds the effective command line per the rules above.
- `clipboardPreview(command:placeholder:) -> String` — preview variant for the input-bar caption (shared by TASK-50).
- `commandReferencesDumpVar(_:) -> Bool` — pure check used by both the preview and command builders, so they can't drift.
- Private helpers: `containsBareDollarF` / `replaceBareDollarF` for word-aware `$F` handling, `singleQuoteShell` for POSIX path quoting.

`ContentView.copyCommandToClipboard()` orchestrates: stage the dump, build the line, push to `NSPasteboard.general`, flash the inline indicator + banner. On error (e.g. tmp dir not writable), surfaces a fake `ShellRunner.Result` event so the failure is visible in the event store rather than silently lost.

## Why it matters

Massive scope reduction. ~470 lines of terminal-orchestration code (including its tests) deleted; replaced by ~250 lines of pure string manipulation + file write. Scratchpad now does ONE thing on ⌘↩: stage a file, copy a string. No subprocess management, no cross-terminal compatibility surface, no "did Gatekeeper block the spawn?" debugging.

User retains full control over where the command runs — they paste into whichever terminal they had open. That's the whole point.

## Test coverage

`ClipboardHandoffTests` (21 tests):
- `StageDumpTests` — 0600 perms, payload round-trip, unique paths across calls.
- `ClipboardCommandTests` — empty / whitespace-only / plain / filter / $F / explicit-var / ${F} / ${SCRATCHPAD_DUMP_FILE} / $FOO (negative) / multi-ref / spaces / single-quotes.
- `ClipboardPreviewTests` — symmetry with clipboardCommand (5 tests, see TASK-50).
- `DumpVarReferenceTests` — recognised forms vs rejected unrelated vars.

Full project suite 35/35 green.
<!-- SECTION:FINAL_SUMMARY:END -->

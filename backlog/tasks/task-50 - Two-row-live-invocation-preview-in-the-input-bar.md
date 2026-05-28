---
id: TASK-50
title: Two-row live invocation preview in the input bar
status: Done
assignee:
  - '@aaron'
created_date: '2026-05-27 05:47'
updated_date: '2026-05-27 06:04'
labels: []
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
  - Sources/Scratchpad/ContentView.swift
  - Sources/Scratchpad/ClipboardHandoff.swift
  - Tests/ScratchpadTests/ClipboardHandoffTests.swift
priority: medium
ordinal: 125
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retroactive ticket capturing work done during the TASK-44 conversation.

## Motivation

The input bar has two evaluation modes (↩ inline, ⌘↩ hand-off) and they wire the dump in differently:

- **↩ inline** runs `/bin/sh -c <cmd>` with the dump bytes on STDIN — equivalent to `‹dump› | <cmd>`.
- **⌘↩ hand-off** appends the dump-file PATH as a positional argument to the typed command — `<cmd> '<path>'`.

That asymmetry is invisible from looking at the input bar alone. A user typing `wc -c` might reasonably assume Scratchpad runs `wc -c '<dump-contents>'` (bytes as a literal arg) — but the bytes are NEVER substituted. Only the path is, and only in hand-off mode.

To make the mental model visible, render a live, non-interactive preview of how the typed text resolves in each mode.

## Behaviour

When the input bar is focused, render two caption rows beneath it:

```
↩   ‹dump› | <cmd>
⌘↩  <cmd> ‹dump-file›    → clipboard
```

- Placeholders use angle-quote characters (U+2039 / U+203A) so they can't be mistaken for shell `<` / `>` redirection.
- Empty input falls back to friendly placeholders (`type a command…` for the ↩ row, the bare dump-file placeholder for the ⌘↩ row).
- Commands referencing `$F` / `${F}` / `$SCRATCHPAD_DUMP_FILE` / `${SCRATCHPAD_DUMP_FILE}` substitute the placeholder where the variable appears, instead of appending. Word-boundary detection on `$F` so `$FOO`, `$FILE` etc. don't match.
- Preview must NOT lie: a unit test pins that the preview's substitution rule matches what `ClipboardHandoff.clipboardCommand` actually produces.
- Only visible when the input bar has keyboard focus — a permanent caption would feel noisy.

## Refs

- TASK-44 (umbrella feature)
- decision-2 (threat model — preview just describes what's happening, doesn't add new surface)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Input bar renders a two-row preview when focused, hidden otherwise
- [ ] #2 ↩ row shows '‹dump› | <typed-cmd>' (inline / stdin-pipe semantics)
- [ ] #3 ⌘↩ row shows '<typed-cmd> ‹dump-file›' with the path appended, OR the command verbatim with placeholder substituted in for $F/$SCRATCHPAD_DUMP_FILE references
- [ ] #4 Empty input renders helpful placeholders rather than a broken-looking empty preview
- [ ] #5 Preview uses angle-quote placeholders (‹›) not ASCII <> so it can't be confused with shell redirection
- [ ] #6 Preview matches the actual clipboard command 1:1 — verified by a sanity unit test that asserts preview output (with a quoted-path placeholder) equals what clipboardCommand emits
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## What was built

Added `ClipboardHandoff.clipboardPreview(command:placeholder:)` as a pure-string function and a sibling computed property `inlineInvocationPreview` in `ContentView`. Both feed into a new `previewRow(prefix:body:trailing:trailingColor:)` SwiftUI helper that renders one caption row in fixed-width prefix + monospaced body + trailing-affordance layout.

The two rows live in a `VStack` beneath the input field and are gated by `focused == .input`. Caching of the preview values is trivial (they're pure functions of `input`), so no @State plumbing is needed.

## Why it matters

Earlier the input bar had a single discoverability caption that didn't actually tell the user how their typed command would be evaluated. The new preview surfaces the inline-vs-hand-off asymmetry visibly and updates live as they type — closes a mental-model gap that came up directly in conversation ("is Scratchpad doing `wc -c 'wat'` internally?").

## Test coverage

`ClipboardPreviewTests` (5 tests) cover empty / plain / alias / custom-placeholder / preview-command-symmetry. The symmetry test is the load-bearing one: it asserts that the preview with a real quoted-path placeholder is byte-equal to what `clipboardCommand` outputs — guarding against future drift.
<!-- SECTION:FINAL_SUMMARY:END -->

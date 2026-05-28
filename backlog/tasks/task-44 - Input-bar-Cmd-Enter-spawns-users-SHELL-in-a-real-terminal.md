---
id: TASK-44
title: >-
  Input bar: Cmd-Enter copies effective command to clipboard for terminal
  hand-off
status: Done
assignee:
  - '@aaron'
created_date: '2026-05-25 13:21'
updated_date: '2026-05-27 06:04'
labels:
  - retroactive
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - >-
    backlog/decisions/decision-2 -
    Threat-model-and-safety-defaults-for-the-shell-input-bar.md
modified_files:
  - Sources/Scratchpad/ClipboardHandoff.swift
  - Sources/Scratchpad/ContentView.swift
  - Tests/ScratchpadTests/ClipboardHandoffTests.swift
priority: medium
ordinal: 250
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a `Cmd-Enter` keybinding on the input bar that escapes the inline-run model — instead of piping the current dump through the typed command and rendering the output in the Scratchpad window, it spawns the user's preferred `$SHELL` inside a real terminal window with the dump available as a temp file. Regular `Enter` keeps its current inline behaviour (no regression).

Motivates: any command that needs a tty — `vim`, `less`, `top`, `htop`, `fzf`, `nano`, `man`, `nvim`, `tmux`, anything ncurses — currently fails silently (or worse, hangs) when run via the input bar's `/bin/sh -c "..."`-with-captured-output model. Rather than auto-detect (heuristic and lossy), give the user an explicit, discoverable escape hatch.

## Design

### Shell detection (always succeeds)

`$SHELL` is essentially always set on macOS. Read it from `ProcessInfo.processInfo.environment["SHELL"]`. If missing for whatever reason (sandboxing oddity, mangled env), fall back to `/bin/zsh` — that's the macOS default since Catalina.

### Terminal app detection (preferred → Terminal.app fallback)

The shell needs a terminal window to host it. Order of preference:

1. Check `$TERMINAL_APP` env var (if user has explicitly set one).
2. Probe `/Applications/iTerm.app`, `/Applications/Ghostty.app`, `/Applications/Warp.app`, `/Applications/Alacritty.app` and pick the first that exists, if any.
3. Fall back to `Terminal.app` (always present on macOS, no probe needed).

A user-config knob ("prefer Terminal.app even if iTerm exists") is out of scope for v1 — revisit if anyone asks.

### The dump

Write the current dump to a 0600 temp file via `mktemp` *before* spawning, and expose its path via `SCRATCHPAD_DUMP_FILE` env var in the spawned shell. The temp file lives until macOS's `/var/folders/.../T/` cleanup kicks in — don't engineer beyond that.

### What runs in the spawned terminal

A small wrapper script written alongside the temp file. Conceptually:

```bash
#!/usr/bin/env <user's $SHELL>
export SCRATCHPAD_DUMP_FILE="/var/folders/.../scratchpad-dump.XXXX"
cd "$(mktemp -d -t scratchpad-session.XXXX)"   # fresh scratch dir
echo "💡 Dump available at \$SCRATCHPAD_DUMP_FILE"
echo "💡 cat \$SCRATCHPAD_DUMP_FILE | <your-command>"

# If user typed a command before hitting ⌘↩, run it first against the dump:
<user-typed-command-pipes-the-dump>

# Then drop into an interactive shell so they can keep exploring:
exec <$SHELL> -i
```

If the input bar was empty when ⌘↩ was pressed, skip the user-typed-command step — they just wanted a shell with the dump available.

The wrapper is what `open -a <TerminalApp> /path/to/wrapper.sh` runs (or `osascript -e 'tell app "Terminal" to do script "..."'`). `open -a` is simpler and works for every macOS terminal app without app-specific scripting.

### Input bar UI hint

When the input bar is focused, show a subtle subtitle under the `$ ` prompt:

```
↩ inline · ⌘↩ in <terminal app name>
```

Updates as terminal-app detection changes. Educates without nagging.

### Threat model

decision-2's reasoning (dumps passed via stdin / file, never interpolated into the command string) holds — `SCRATCHPAD_DUMP_FILE` is an env-var path, not a substitution. Spawning a fresh shell in a fresh scratch dir is *less* dangerous than the inline path (user is now in their own shell, not Scratchpad's `/bin/sh -c` child). No new threat-model surface.

### Out of scope for v1

- Auto-detection of "this command needs a tty" — explicit `⌘↩` is the whole point.
- Allowlist-driven nudges ("hey, `vim` won't work inline, try ⌘↩") — possible polish for v1.1; mention in implementation notes but don't build.
- Round-tripping output from the spawned terminal back into the Scratchpad window — terminal sessions are fire-and-forget by design; complicates the UX.
- Custom terminal-app preference UI in Scratchpad settings — read env var only for v1.

## Refs

- `NSEvent.modifierFlags` for detecting Cmd+Enter inside SwiftUI: https://developer.apple.com/documentation/appkit/nsevent/1535211-modifierflags
- `keyboardShortcut(_:modifiers:)` on a hidden Button as the SwiftUI-idiomatic way to add Cmd-Enter to a focused TextField: https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:)
- `Process` + `Pipe` for spawning `open`: https://developer.apple.com/documentation/foundation/process
- `mktemp(3)` man page (BSD): https://manpagez.com/man/3/mktemp/
- decision-2 (threat model the new path doesn't perturb): backlog/decisions/decision-2
- Related: TASK-9 (existing inline shell-pipe), TASK-10 (threat model + safety defaults)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cmd-Enter in the input bar copies a ready-to-paste command line to the system clipboard, without consuming/displacing the inline display of the current dump
- [x] #2 Regular Enter behaviour is unchanged (regression check)
- [x] #3 The current dump is written to a 0600 mktemp file before the command is built; the file path is embedded in the copied command
- [x] #4 If the input bar has a typed command, the copied line resolves the dump into it: $F / $SCRATCHPAD_DUMP_FILE references are substituted with the quoted file path; otherwise the path is appended as the last positional argument
- [x] #5 If the input bar is empty, the copied line is the quoted dump-file path on its own (so it can be pasted as an argument to whatever the user is typing in their terminal)
- [x] #6 Input bar shows a live two-row preview when focused: '↩ ‹dump› | <cmd>' for inline mode and '⌘↩ <cmd> ‹dump-file› → clipboard' for the hand-off, with a brief 'Copied!' confirmation after ⌘↩ fires
- [x] #7 Threat-model unchanged: dump bytes are never substituted into the command string; only the file PATH is, and the user's typed command is interpolated verbatim (same posture as decision-2)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Approach

Introduce a new pure-logic helper `TerminalLauncher` (sibling of `ShellRunner`) and wire a Cmd-Enter handler into `ContentView` that escapes the inline-run model into a real terminal window.

### 1. `Sources/Scratchpad/TerminalLauncher.swift` (new)

Pure-logic, `nonisolated` API. No SwiftUI/AppKit dependency, so it can be exercised by Swift Testing without booting NSApplication.

- `detectShell() -> String` — read `ProcessInfo.processInfo.environment["SHELL"]`; fall back to `/bin/zsh` (Catalina-onwards default).
- `detectTerminalApp() -> (bundlePath: String, displayName: String)` — order: `$TERMINAL_APP` (must point at an `.app` that exists) → probe `/Applications/{iTerm,Ghostty,Warp,Alacritty}.app` → fall back to `/System/Applications/Utilities/Terminal.app` (always present).
- `writeDumpAndWrapper(payload:command:) -> URL` — write the dump to a `mkstemp`-style file at 0600 perms; write a wrapper `.sh` to a sibling tmp path at 0700 perms. Wrapper exports `SCRATCHPAD_DUMP_FILE`, `cd`s into a fresh `mktemp -d` scratch session dir, prints two `💡` hints, conditionally pipes the dump through the user's typed command via `cat "$SCRATCHPAD_DUMP_FILE" | <cmd>`, then `exec $SHELL -i`.
- `launch(payload:command:) async throws -> String` — orchestrate the above, then `Process` -> `/usr/bin/open -n -a <bundlePath> <wrapper>`. Returns the terminal display name so the caller can confirm.

### 2. `Sources/Scratchpad/ContentView.swift` (modify)

- New `runInTerminal()` method: mirrors `runCommand()` shape, but does NOT clear input, does NOT push to EventStore (fire-and-forget per task spec), DOES append non-empty command to InputHistory.
- New invisible Button in `globalShortcuts` with `.keyboardShortcut(.return, modifiers: .command)` calling `runInTerminal()`. Works from anywhere in the window — matches the existing pattern for ⌘L/⌘[/⌘].
- New caption row rendered below the input field when `focused == .input`: `↩ inline · ⌘↩ in <terminal app name>`. Reads from `TerminalLauncher.detectTerminalApp().displayName`.
- @State `terminalAppName` cached once at view init so we don't re-probe on every render.

### 3. `Tests/ScratchpadTests/TerminalLauncherTests.swift` (new)

Swift Testing, `@MainActor`:
- `detectShell` honors `$SHELL`; falls back to `/bin/zsh` when unset (via a sandboxed env-snapshot helper since `unsetenv` is process-global).
- `detectTerminalApp` precedence: `$TERMINAL_APP` honored if path exists; otherwise picks a probed app or Terminal.app.
- Wrapper script content: contains `export SCRATCHPAD_DUMP_FILE=`, `cd "$(mktemp -d`, two `💡` lines, and (when command non-empty) the `cat "$SCRATCHPAD_DUMP_FILE" | <user-cmd>` snippet.
- Dump file perms are 0600.

The actual `open -a` invocation in `launch()` is not unit-tested — it would spawn terminal windows. Manual verification on the dev box covers it.

### Threat model preservation (AC#8)

- Dump bytes are written to a file; the file *path* (not contents) is exported as an env var.
- Wrapper script interpolates only the user's typed command — they typed it, so this is consistent with decision-2's "the command is code, the user typed it" principle.
- Dump enters the pipeline via `cat "$SCRATCHPAD_DUMP_FILE" | <cmd>`, identical posture to the inline-run model — stdin, never substitution.

### Files touched

- `Sources/Scratchpad/TerminalLauncher.swift` (new)
- `Sources/Scratchpad/ContentView.swift`
- `Tests/ScratchpadTests/TerminalLauncherTests.swift` (new)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Build clean. Full test suite green (24/24 incl. 10 new TerminalLauncher tests).

End-to-end smoke of the generated wrapper script confirmed: dump piped through `wc -c` produces correct byte count; both 💡 hints render with literal $SCRATCHPAD_DUMP_FILE shown.

AC#1 and AC#7 require manual GUI verification on the dev box — the `open -a` path and the SwiftUI focus-driven caption aren't unit-testable without booting an NSApplication and spawning real windows. To verify: launch Scratchpad, send a dump, focus the input bar, confirm the '↩ inline · ⌘↩ in <Terminal>' caption appears, then press ⌘↩ both with empty and non-empty input.

Post-review ergonomics pass (2026-05-27):

1. ⌘↩ now hides the Scratchpad window via WindowController.shared.hide() — handing off cleanly to the terminal rather than leaving the floating window pinned over it. Window state (frame, history) is preserved; menu-bar click brings it back.

2. Changed the typed-command execution model from stdin-pipe to positional-arg, because stdin-pipe defeated the whole point of ⌘↩: TTY commands (vim, less, fzf, nvim, top) can't accept stdin redirects. New rules:
   - If the user's command contains `$SCRATCHPAD_DUMP_FILE`, `${SCRATCHPAD_DUMP_FILE}`, `$F`, or `${F}` → run verbatim.
   - Otherwise → append `"$SCRATCHPAD_DUMP_FILE"` as the last positional argument.
   `$F` is a Scratchpad-exported shorthand alias so users can type `vim $F` instead of the 20-char mouthful.

   Word-boundary detection ensures `echo $FOO` is NOT mistaken for the alias (added test).

3. Tests grown 10 → 15; 5 new cases cover plain-cmd append, filter-cmd append, explicit-var passthrough, $F alias, $FOO non-match, ${F} braced form.

Mental-model clarification + live preview (2026-05-27):

User asked whether Scratchpad was running `wc -c 'wat'` internally (i.e. dump bytes as a literal arg). Clarified: NO. Inline ↩ runs `<cmd>` with dump bytes on STDIN. Terminal ⌘↩ runs `<cmd> "$DUMP_FILE_PATH"`. The dump bytes are NEVER substituted as an argument; only the file PATH is, in terminal mode.

To make this asymmetry visible, the input-bar caption was reworked from a single discoverability line into a two-row live preview:

  ↩    ‹dump› | <cmd>
  ⌘↩   <cmd> ‹dump-file›        in Terminal

The preview updates as the user types. For commands that reference $F or $SCRATCHPAD_DUMP_FILE, the terminal row shows the command verbatim (matching the wrapper's passthrough behaviour). Empty input renders helpful placeholders.

New helpers in TerminalLauncher:
  - `commandReferencesDumpVar(_:)` — pulled out of makeWrapperScript to be reused by the preview, ensuring preview/runtime stay in lockstep.
  - `terminalInvocationPreview(command:placeholder:)` — pure-string preview function.

A sanity test asserts that the preview, with the same placeholder makeWrapperScript uses, appears verbatim in the generated wrapper — guards against preview/runtime drift.

Tests: 29 → 37 (8 new: 6 covering terminalInvocationPreview branches, 2 covering commandReferencesDumpVar word-boundary detection).

Pivot away from spawning a terminal (2026-05-27):

User feedback: the spawn-a-terminal flow wasn't working well enough. Replaced it with a much simpler model — ⌘↩ stages the dump to a 0600 temp file and copies a ready-to-paste command line (with the file path inlined) to the system clipboard. User pastes into whatever terminal they already have open.

What got deleted (Scratchpad is now responsible for much less):
  - Terminal-app detection (iTerm/Ghostty/Warp/Alacritty probing, $TERMINAL_APP env handling, Terminal.app fallback)
  - Wrapper-script generation
  - `open -a` Process spawning
  - Window-hide-on-handoff logic
  - $F and $SCRATCHPAD_DUMP_FILE shell exports (no wrapper to export them now; instead we substitute them with the literal path at clipboard-build time)
  - `TerminalLauncher.swift` and its 15-test suite — renamed/replaced by `ClipboardHandoff.swift`.

Clipboard rules:
  - empty input → bare quoted path on its own (e.g. `'/tmp/scratchpad-dump-xyz'`)
  - input mentions $F / ${F} / $SCRATCHPAD_DUMP_FILE / ${SCRATCHPAD_DUMP_FILE} → substitute every reference with the quoted path
  - otherwise → `<cmd> '<path>'` (path appended as last positional arg)

POSIX single-quote escaping handles awkward path chars (spaces, apostrophes) safely.

UI: preview row updates from `⌘↩ <cmd> ‹dump-file› in Terminal` → `⌘↩ <cmd> ‹dump-file› → clipboard`. After ⌘↩ fires, the trailing tag flips to `Copied!` for 1.5s. Window is NOT hidden — user can compare what they typed against what got copied.

Tests: 21 in ClipboardHandoff (stageDump perms + uniqueness; clipboardCommand for empty/plain/alias/explicit-var/braced/$FOO/multi-ref/spaces/quotes; clipboardPreview for symmetry with clipboardCommand; commandReferencesDumpVar coverage). Full suite 35/35 green.

All original ACs reframed and now testable without GUI — ticked 1–7.

UI feedback pass for clipboard hand-off (2026-05-27):

1. Layout: the '→ clipboard' affordance label was moved from the far-right end of the preview row to immediately after the '⌘↩' prefix glyph. The keybinding and its consequence now read as a single unit: '⌘↩ → clipboard   wc -c ‹dump-file›'. Pre-flash trailing colour bumped from .tertiary to .secondary to make the label a bit more legible. `previewRow` now takes a `trailingColor` parameter so the call site can swap to .accentColor during the post-copy flash.

2. Notification: added a confirmation banner that slides in above the input bar when ⌘↩ fires. Shows '✓ Copied to clipboard: <copied-line>' with accent-tinted background and a 1px accent rule along the bottom. Holds ~2s, then fades out. SwiftUI `.transition(.opacity.combined(with: .move(edge: .bottom)))` for a soft animation. The banner shows the *actual* copied line (including the resolved dump-file path), which reassures the user that the right thing got copied — especially useful for empty input where the bare path is what lands on the clipboard.

3. Inline indicator strengthened: the in-row affordance swap is now '✓ Copied!' in the system accent colour (was 'Copied!' in .tertiary).

Files touched: ContentView.swift only. Tests unchanged (these are pure-view changes; the underlying ClipboardHandoff logic is the same).
<!-- SECTION:NOTES:END -->

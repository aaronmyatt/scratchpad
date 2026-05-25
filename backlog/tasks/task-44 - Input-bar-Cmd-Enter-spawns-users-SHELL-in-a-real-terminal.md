---
id: TASK-44
title: 'Input bar: Cmd-Enter spawns user''s $SHELL in a real terminal'
status: To Do
assignee: []
created_date: '2026-05-25 13:21'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - >-
    backlog/decisions/decision-2 -
    Threat-model-and-safety-defaults-for-the-shell-input-bar.md
priority: medium
ordinal: 42000
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
- [ ] #1 Cmd-Enter in the input bar spawns a new terminal window without consuming/displacing the inline display of the current dump
- [ ] #2 Regular Enter behaviour is unchanged (regression check)
- [ ] #3 Spawned terminal runs the user's $SHELL (read from environment; falls back to /bin/zsh if missing)
- [ ] #4 Preferred terminal-app detection order: $TERMINAL_APP env var → iTerm/Ghostty/Warp/Alacritty if present → Terminal.app fallback
- [ ] #5 Current dump is written to a 0600 mktemp file and exposed as $SCRATCHPAD_DUMP_FILE in the spawned shell
- [ ] #6 If input bar has a command typed when Cmd-Enter is pressed, that command runs against the dump first, then drops to interactive $SHELL; if input bar is empty, just opens the shell
- [ ] #7 Input bar shows a subtle subtitle 'cmd-Enter in <terminal app name>' so the feature is discoverable
- [ ] #8 Threat-model unchanged: dump never interpolated into a command string — passed only via env var path or stdin
<!-- AC:END -->

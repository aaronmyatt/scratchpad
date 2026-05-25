---
id: TASK-29
title: First-launch sp symlink onto user's PATH
status: Done
assignee: []
created_date: '2026-05-24 16:04'
updated_date: '2026-05-25 03:48'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-28
modified_files:
  - Sources/Scratchpad/PathInstaller.swift
  - Sources/Scratchpad/AppDelegate.swift
priority: high
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On first launch, offer to symlink Scratchpad.app/Contents/MacOS/sp onto the user's PATH so `sp` works from any terminal. Standard pattern, e.g. VS Code's "Shell Command: Install code in PATH" command.

Implementation sketch:
  - AppDelegate checks for an existing /usr/local/bin/sp on first run.
  - If absent and the user agrees (one-time dialog), creates a symlink.
  - If /usr/local/bin not writable (newer macOS), falls back to ~/bin/sp and prints PATH instructions.
  - Stores a "user declined / done" flag in UserDefaults so we never prompt twice.

Must handle the case where the user has an older /usr/local/bin/sp from manual setup — never overwrite, just point out the conflict.

Depends on TASK-28 (the bundle layout that puts sp inside the .app).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 First launch presents a one-time prompt offering to install sp on PATH
- [x] #2 Existing /usr/local/bin/sp is detected and not overwritten
- [x] #3 Falls back to ~/bin/sp with PATH guidance when /usr/local/bin isn't writable
- [x] #4 Decision is remembered across relaunches
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added Sources/Scratchpad/PathInstaller.swift — a single @MainActor enum with one public entry point `runIfNeeded()`. AppDelegate.applicationDidFinishLaunching gains one line that calls it after the HTTP and socket receivers are up.

Behaviour:
- Short-circuits via UserDefaults key `PathInstaller.didPromptOnFirstLaunch` (AC#4).
- Short-circuits when not running as a .app (e.g. `swift run`) so we never symlink a transient debug artifact.
- Defensive: bails silently if the bundled sp is missing from Contents/MacOS/.

Flow (AC#1, AC#3):
1. NSAlert offers Install (default) / Not Now.
2. On Install, try createSymbolicLink at /usr/local/bin/sp.
3. On EACCES, fall through to ~/bin (create dir if needed) + surface PATH guidance (`export PATH="$HOME/bin:$PATH"`) since ~/bin isn't on the default shell PATH.
4. If both fail, surface the exact `ln -s` command the user can run manually.

Collision handling (AC#2):
- If /usr/local/bin/sp already exists, never overwrite. Idempotent self-detection: if the existing entry is a symlink whose destination matches our current bundle's sp, treat as already-installed and show nothing. Otherwise alert the user that a foreign sp is in the way and show the `rm` command they'd use.

Focus discipline:
- No NSApp.activate() anywhere. The "no focus theft" project invariant applies to dump-window show paths; a first-launch setup dialog at applicationDidFinishLaunching is not a show path. NSAlert.runModal() brings the alert forward without our intervention. Rationale captured in the file header.

Verification:
- swift build is clean; scripts/build-app.sh rebuilds the .app with the new behaviour in place.
- On-screen UX smoke test is for the user (double-click build/Scratchpad.app on a fresh UserDefaults state; re-arm with `defaults delete com.aaronmyatt.scratchpad PathInstaller.didPromptOnFirstLaunch`).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PathInstaller wired in. First-launch flow: offer dialog → /usr/local/bin/sp → fallback to ~/bin/sp with PATH guidance → UserDefaults flag prevents re-prompt. Collisions detected and not overwritten. Re-arm for retesting with `defaults delete com.aaronmyatt.scratchpad PathInstaller.didPromptOnFirstLaunch`.
<!-- SECTION:FINAL_SUMMARY:END -->

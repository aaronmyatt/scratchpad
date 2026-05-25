---
id: TASK-26
title: 'Drop-in client: clients/sp.sh (source-able bash function)'
status: To Do
assignee: []
created_date: '2026-05-24 15:59'
updated_date: '2026-05-25 12:33'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
priority: medium
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Single-file shell-source-able function at clients/sp.sh. Define a `sp` function the user can call from any shell session after `source ./clients/sp.sh`, or paste straight into their shellrc.

Usage:
  echo hi | sp
  sp 'literal argument'
  sp < some_file

Behavior:
  - Resolves $SCRATCHPAD_SOCKET_PATH and $SCRATCHPAD_PORT exactly like the Swift sp binary.
  - If [ -S "$sock" ] tries nc -U; otherwise curl --data-binary @- to HTTP.
  - Silent no-op on failure (>/dev/null 2>&1).
  - No flags, no -m, no -h — the Swift binary covers that surface. This is for users who don't want to download a Swift binary or build from source.

Delibarate non-goals:
  - Not a replacement for the Swift sp; that one stays the canonical CLI.
  - Not handling weird filenames, IFS, or other deep shell-portability rabbit holes — bash + zsh on macOS is enough.

Update the Bash section of README.md to reference clients/sp.sh; keep the inline curl / nc one-liners.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 clients/sp.sh exists at repo root, < 30 lines, sources cleanly under bash and zsh
- [ ] #2 Defines a 'sp' function; pipe input and arg input both work
- [ ] #3 Tries UDS first, falls back to HTTP, silent no-op when neither is reachable
- [ ] #4 README Bash section updated to reference clients/sp.sh
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Archived 2026-05-25 as obsolete. The stated audience for clients/sp.sh was "users who don't want to download a Swift binary or build from source." With decision-3's distribution strategy now in place (brew tap TASK-32, curl|bash install.sh TASK-34, direct DMG download TASK-35), the Swift `sp` binary is one one-liner away from any user via any install path, and TASK-29's PathInstaller wires it onto PATH automatically on first launch. The bash function has no remaining audience — anyone who can `source ./clients/sp.sh` can also `curl -fsSL …/install.sh | bash` and get the canonical CLI. Revisit if a "transport-only without the .app" use case ever emerges (e.g. piping to a Scratchpad running on a remote machine), but that's speculative — no users requested it.
<!-- SECTION:FINAL_SUMMARY:END -->

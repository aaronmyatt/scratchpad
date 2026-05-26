---
id: TASK-49
title: 'sp: --version flag prints the installed version and exits'
status: To Do
assignee: []
created_date: '2026-05-26 12:14'
labels:
  - cli
  - ux
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - Sources/sp/main.swift
  - scripts/build-app.sh
  - /Applications/Scratchpad.app/Contents/Info.plist
priority: medium
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add `sp --version` (and the conventional `-V` short form) so a user can answer "which Scratchpad am I actually running?" without quitting the app or opening Finder → Get Info on the bundle.

Motivation: with the Cask + curl install paths both shipping the same binary, and with users likely to upgrade in-place over a still-running instance, version drift is easy to introduce and hard to debug. A one-line CLI probe is the cheapest possible diagnostic.

Two questions to resolve in implementation:

1. **Where does the version string come from?**
   - The .app bundle's Info.plist already carries `CFBundleShortVersionString` (set from `git describe --tags` by `scripts/build-app.sh:64`). `sp` lives at `Contents/MacOS/sp` inside the bundle so it can walk up to `../../Info.plist` and read it — no compile-time bake-in needed, and the version stays in lockstep with whatever the bundle says.
   - Fallback for `swift run sp` (dev builds, no enclosing bundle): print something like `dev (no bundle)` rather than crash.
   - Alternative: bake the version in at build time via a `-D` flag or a generated Swift constant. Simpler to read but duplicates the source of truth.

2. **Should `sp --version` also probe the running app?** Users might assume `sp` and Scratchpad.app are always the same version, but an in-place upgrade leaves the old app process running with the new sp on disk — exactly the drift scenario this flag is meant to catch. Suggest printing both:

   ```
   sp        v0.1.5   (bundle: /Applications/Scratchpad.app)
   running   v0.1.4   (pid 4821)   ← mismatch, quit + relaunch to upgrade
   ```

   Probing the running app requires a new transport endpoint (e.g. `GET /version` on the HTTP receiver) — meaningful scope creep. A v1 of this task could ship just the local-binary line and leave the runtime probe as a follow-up.

Output format suggestion (matching git, curl, jq idioms):
```
$ sp --version
sp 0.1.5
$ sp -V
sp 0.1.5
```

Plain stdout, no decoration, exit 0. Tested via `sp --version | grep -q '^sp [0-9]'` in CI.

Out of scope (deliberately): `sp --help` already exists and documents transports; don't duplicate the version there. JSON output (`--version --json`) is YAGNI until something actually consumes it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `sp --version` and `sp -V` both print a single line `sp <semver>` to stdout and exit 0.
- [ ] #2 When run from a bundled .app, the version matches `CFBundleShortVersionString` from the enclosing Info.plist.
- [ ] #3 When run from a dev `swift run` build (no enclosing .app), it prints a clearly-non-release marker (e.g. `sp dev`) and exits 0 — never crashes.
- [ ] #4 Bare `sp` (no args, terminal), `sp --help`, `sp -m ...`, `sp <file>`, and `echo x | sp` continue to behave exactly as today (regression-tested manually or via the bats suite from TASK-48).
- [ ] #5 README / install.sh next-steps mention `sp --version` as the verification one-liner.
<!-- AC:END -->

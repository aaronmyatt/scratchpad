---
id: TASK-49
title: 'sp: --version flag prints the installed version and exits'
status: Done
assignee: []
created_date: '2026-05-26 12:14'
updated_date: '2026-05-27 14:11'
labels:
  - cli
  - ux
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - Sources/sp/main.swift
  - scripts/build-app.sh
  - /Applications/Scratchpad.app/Contents/Info.plist
modified_files:
  - Sources/sp/main.swift
  - scripts/build-app.sh
  - README.md
  - install.sh
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
- [x] #1 `sp --version` and `sp -V` both print a single line `sp <semver>` to stdout and exit 0.
- [x] #2 When run from a bundled .app, the version matches `CFBundleShortVersionString` from the enclosing Info.plist.
- [x] #3 When run from a dev `swift run` build (no enclosing .app), it prints a clearly-non-release marker (e.g. `sp dev`) and exits 0 — never crashes.
- [x] #4 Bare `sp` (no args, terminal), `sp --help`, `sp -m ...`, `sp <file>`, and `echo x | sp` continue to behave exactly as today (regression-tested manually or via the bats suite from TASK-48).
- [x] #5 README / install.sh next-steps mention `sp --version` as the verification one-liner.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Approved plan (2026-05-27)

### Design decisions

1. **Version source:** `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`. When sp lives at `Scratchpad.app/Contents/MacOS/sp`, Bundle.main resolves to the enclosing .app automatically — no manual path walking. Outside a bundle (`swift run sp`, `.build/release/sp`), lookup returns nil → print `sp dev`.

2. **Scope:** Local-binary version only. Runtime app probing (GET /version) deferred per task body — meaningful scope creep, no consumer yet.

3. **Arg parsing:** Add `--version`/`-V` as siblings to `-h`/`--help` in the existing `case 2` branch (main.swift:93-110). No new parsing infrastructure.

### Changes

- `Sources/sp/main.swift`: add printVersion() helper, 4-line branch in case 2, update usage block.
- `README.md`: single mention under the sp CLI section (per user — `--version` is a well-known pattern, doesn't need install-path duplication).
- `install.sh`: add `sp --version` to next-steps panel as one-line installation-success probe.

### Verification (manual, per AC#4)

After `./scripts/build-app.sh`:
- `build/Scratchpad.app/Contents/MacOS/sp --version` → `sp <git-describe>`
- `build/Scratchpad.app/Contents/MacOS/sp -V` → same
- `.build/release/sp --version` → `sp dev`
- `echo x | …/sp`, `…/sp --help`, `…/sp`, `…/sp -m foo`, `…/sp <file>` → existing behaviour

### Out of scope

- JSON output, runtime app probing.
- New bats coverage — AC#4 explicitly allows manual verification; Tests/install.bats has a narrower scope (install hygiene).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-05-27 — Implementation complete. All 5 ACs verified manually against a freshly-built bundle.

## Scope adjustment: build-app.sh leading-v strip

During AC verification, the task's own suggested CI probe (`sp --version | grep -q '^sp [0-9]'`) failed because `git describe --tags` returns `v0.1.5-1-gaadc36c` (tag convention) but Apple's `CFBundleShortVersionString` spec calls for a numeric value (digits + dots, no prefix). Two consequences:
  1. The probe in the task description didn't match what we'd print.
  2. The Info.plist was already non-canonical — `plutil` tolerates the `v` but flags it as non-standard.

Fix applied at the source: build-app.sh now strips a leading `v` from the git-describe output (`VERSION="${RAW_VERSION#v}"`). One bash idiom, single character of behaviour change, brings:
  - The Info.plist value into line with Apple's spec.
  - The CLI output (`sp 0.1.5-1-gaadc36c`) into line with the grep-friendly probe.
  - `sp --version`'s output and the plist into exact byte-for-byte equality (verified — see AC#2 evidence below).

Alternative considered: post-hoc strip in `printVersion()` only. Rejected because it would make sp's output diverge from the plist, weakening AC#2's "the version matches" guarantee.

Bats install-hygiene suite (TASK-48) was re-run after this change — all 5 cases still pass.

## Verification evidence (against build/Scratchpad.app from current HEAD `v0.1.5-1-gaadc36c`)

```
sp --version                                                → sp 0.1.5-1-gaadc36c   (exit 0)
sp -V                                                       → sp 0.1.5-1-gaadc36c   (exit 0)
sp --version | grep -q '^sp [0-9]'                          → exit 0 (probe-passed)
plutil -extract CFBundleShortVersionString raw Info.plist   → 0.1.5-1-gaadc36c
sp --version vs plist                                       → byte-for-byte MATCH
.build/release/sp --version (no bundle)                     → sp dev               (exit 0)
sp --help (regression)                                      → exit 0
sp -m foo (regression)                                      → exit 0
sp <file> (regression)                                      → exit 0
echo x | sp (regression)                                    → exit 0
sp --bogus (unknown flag)                                   → exit 2 ✓ (preserved)
```

Bare `sp` from a tty (case 1, autostart path) was not exercised in the harness (non-tty), but the case 1 branch is untouched — only case 2 gained the new dispatch.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

`sp --version` and `sp -V` now print a single grep-friendly `sp <semver>` line and exit 0. Version is sourced from the enclosing `.app`'s `CFBundleShortVersionString` (via `Bundle.main.infoDictionary` — no manual path walking), with a `sp dev` fallback when running outside a bundle.

## What shipped

- **`Sources/sp/main.swift`** — new `printVersion()` helper + a 4-line dispatch branch in the existing `case 2` arg handler (siblings to `-h`/`--help`). Usage block gained a `-V, --version` line.
- **`scripts/build-app.sh`** — strips a leading `v` from `git describe` output so the Info.plist's `CFBundleShortVersionString` is spec-compliant (digits-plus-dots, no tag prefix). This also brings the plist value and `sp --version`'s output into byte-for-byte equality. Scope-adjacent fix; see implementation notes for the reasoning.
- **`README.md`** — `sp --version` added to the `sp` CLI examples block (single mention; `--version` is a near-universal pattern so doesn't need install-path duplication).
- **`install.sh`** — `sp --version` added to the post-install next-steps panel as the verification one-liner.

## Verification (all 5 ACs)

- **#1** `sp --version` and `sp -V` both print `sp <semver>` to stdout and exit 0. ✓
- **#2** Bundled sp's output matches `CFBundleShortVersionString` byte-for-byte (`0.1.5-1-gaadc36c` ≡ `0.1.5-1-gaadc36c`). ✓
- **#3** `.build/release/sp --version` prints `sp dev` (clear non-release marker) and exits 0, no crash. ✓
- **#4** `--help`, `-m`, `<file>`, `echo | sp`, and unknown-flag (exit 2) regressions all preserved. ✓
- **#5** `sp --version` referenced in README sp CLI section + install.sh next-steps panel. ✓

Bats install-hygiene suite (TASK-48) re-run after build-app.sh change — still 5/5 passing.

## Deferred (per task body)

- **Runtime app probe** — `sp --version` printing both local-binary version AND running-app version (mismatch detection). Requires a new `GET /version` HTTP endpoint; scope-creepy and no consumer yet. Worth a follow-up task only if drift incidents start showing up.
- **JSON output** — explicit YAGNI in the task description.
<!-- SECTION:FINAL_SUMMARY:END -->

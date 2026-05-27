---
id: TASK-48
title: 'bats: install-hygiene regression guards (quarantine + bundle seal)'
status: Done
assignee: []
created_date: '2026-05-26 04:20'
updated_date: '2026-05-27 13:29'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-39
modified_files:
  - Tests/install.bats
  - Tests/README.md
  - README.md
  - >-
    backlog/tasks/task-48 -
    bats-install-hygiene-regression-guards-quarantine-bundle-seal.md
priority: medium
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two correctness regressions slipped through between v0.1.0 and v0.1.3:

- **v0.1.1 → v0.1.2 (bundle sealing):** SwiftPM's linker-signed ad-hoc signature isn't enough on macOS Sequoia — the bundle itself needs `Contents/_CodeSignature/CodeResources`. Without it, Gatekeeper rejects with "Scratchpad is damaged" (no bypass). Fixed by adding `codesign --force -s -` calls to `scripts/build-app.sh`.
- **v0.1.2 → v0.1.3 (quarantine strip):** brew Cask defaulted to *adding* `com.apple.quarantine` to installed apps since ~2020 — not stripping, as our docs incorrectly claimed. macOS 15 then blocks first launch with "Apple could not verify Scratchpad…". Fixed by adding a `postflight` xattr-strip block to the Cask template, and by `install.sh`'s existing defensive `xattr -dr`.

Both fixes are easy to silently regress (someone refactors `build-app.sh` and drops the codesign block; the Cask template gets reformatted and the postflight block gets removed). Worth pinning with bats assertions that run as part of TASK-39's pre-release suite.

Test cases to add (all in `tests/install.bats` or similar — exact location depends on TASK-39's chosen layout):

1. **Build-output sealing.** After `./scripts/build-app.sh`, `codesign -dv build/Scratchpad.app` should print a line matching `Sealed Resources version=2` (or higher). Catches regression of v0.1.2's fix.

2. **Tarball preserves sealing.** After `./scripts/build-tarball.sh`, extract the tarball into a tmp dir; the extracted `Scratchpad.app` should still have `Sealed Resources version=2`. Catches a future tar-flag change that strips the `_CodeSignature/` directory.

3. **install.sh strips quarantine.** Run install.sh with `SCRATCHPAD_TARBALL_URL=file://…` against a tmp install dir; `xattr -p com.apple.quarantine` on the installed .app should return non-zero (no such xattr). Catches regression of install.sh's defensive `xattr -dr`.

4. **Cask template carries the postflight strip.** Pure grep-style assertion on `scripts/scratchpad.cask.rb.template` — must contain `postflight do` and `com.apple.quarantine` on adjacent lines. Catches the case where someone reformats the template and accidentally drops the postflight block. (Brew-install end-to-end would be more authoritative, but requires a real tap and brew env; this static assertion is the cheap proxy.)

Each test is ~10 lines of bats. Total file is well under 100 lines.

Refs:
- `xattr(1)`: https://ss64.com/mac/xattr.html
- `codesign -dv`: https://ss64.com/mac/codesign.html
- bats `run` + `[[ "$output" =~ ... ]]`: https://bats-core.readthedocs.io/en/stable/writing-tests.html
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tests/install.bats exists with five assertions: (1) build-app.sh produces a sealed bundle, (2) tarball preserves sealing, (3) install.sh strips quarantine when present (plant + re-install), (4) install.sh source contains 'xattr -dr com.apple.quarantine', (5) Cask template has postflight + com.apple.quarantine on adjacent lines
- [x] #2 All five bats cases pass against the current main branch
- [x] #3 Tests are runnable standalone (`bats tests/install.bats`); wiring into TASK-39's preflight-release.sh chain is deferred until TASK-39 ships and is tracked there
- [x] #4 Failure messages identify which install-hygiene regression has crept back in (don't just say 'expected X got Y' — say 'bundle missing Sealed Resources — see build-app.sh codesign block')
- [x] #5 README's Development section gets a one-line note pointing at the test suite
<!-- AC:END -->



## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Approved plan (2026-05-27)

Create `tests/install.bats` with **five** assertions (revised up from four during planning — test #3 split into a behavioural test + a grep-style test because the original wording was near-fictional on a dev host: `curl|file://` never sets `com.apple.quarantine`, so the assertion would pass even with the defensive line removed).

### Test cases

1. **Build-output sealing.** Run `scripts/build-app.sh`; assert `codesign -dv build/Scratchpad.app 2>&1` contains `Sealed Resources version=2`. Catches regression of v0.1.2's codesign block in `build-app.sh:206-217`.

2. **Tarball preserves sealing.** Run `scripts/build-tarball.sh`; extract into `mktemp -d`; assert extracted `Scratchpad.app` still reports `Sealed Resources version=2`. Catches a future tar-flag change stripping `_CodeSignature/`.

3. **install.sh strips quarantine when present.** Run install.sh with `SCRATCHPAD_TARBALL_URL=file://…build/Scratchpad-arm64.tar.gz` + `SCRATCHPAD_INSTALL_DIR=$(mktemp -d)`; plant `com.apple.quarantine` xattr on the installed `.app` (since `file://` doesn't set it naturally); re-run install.sh (overwrites + strips); assert `xattr -p com.apple.quarantine` exits non-zero.

4. **install.sh contains the defensive strip line** (static grep). `grep -q 'xattr -dr com.apple.quarantine' install.sh`. Symmetric with test #5 — catches the case where install.sh is refactored and the line silently dropped.

5. **Cask template carries the postflight strip** (static grep). `grep -A 5 'postflight do' scripts/scratchpad.cask.rb.template | grep -q 'com.apple.quarantine'`. Catches Cask reformat dropping the postflight block.

### Performance

`setup_file` builds the .app once and shares it across tests 1+2+3. Total runtime dominated by `swift build -c release` (~15-30s on warm cache).

### Failure messages (AC#4)

Each test ends with `|| fail "<specific regression note>"`, e.g. `"bundle missing Sealed Resources — see build-app.sh codesign block"`.

### Files

- `tests/install.bats` (new, ~120 lines)
- `tests/README.md` (new, ~15 lines — bats install + run instructions)
- `README.md` (one-line addition under Development section)

### Open items / known scope decisions

- **AC#3** explicitly notes wiring into `preflight-release.sh` is deferred to TASK-39 (which is To Do). Tests are written to be standalone-first.
- **bats install** requires `brew install bats-core` — user-side action; not run from this session.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-05-27 — Implementation complete. All 5 bats cases pass against current main (Bats 1.13.0, ~25s including swift build of release bundle on warm cache). Suite committed at Tests/install.bats; runner doc at Tests/README.md; README's Development block gained a `bats Tests/install.bats` line.

## Scope changes from original task description

1. **Test count: 4 → 5.** Split the original test #3 ("install.sh strips quarantine") into a behavioural test + a static grep test. Reason: `curl|file://` never sets `com.apple.quarantine`, so the original assertion would have passed even with the defensive `xattr -dr` line removed from install.sh. The behavioural test plants the xattr post-install, then re-invokes install.sh and asserts it's stripped — that exercises the actual command. The grep test is the cheap symmetric guard against the line being deleted during refactor.

2. **AC#3 (preflight wiring) deferred to TASK-39.** Original AC said "runnable standalone AND wired into TASK-39's preflight-release.sh chain." Standalone half is complete. TASK-39 (the chain itself) is still To Do — adding a `bats Tests/install.bats` line to `preflight-release.sh` is a one-line change that belongs in TASK-39's PR, not this one. AC#3 rewritten to make that split explicit; Tests/README.md flags the same to whoever picks up TASK-39.

## Location decision: Tests/install.bats (not tests/install.bats or scripts/tests/)

macOS filesystem is case-insensitive, so `tests/` and `Tests/` collide. Chose `Tests/install.bats` (sibling to ScratchpadTests/) because:
  - One tree for "all tests" — easier to find.
  - SwiftPM only registers `Tests/ScratchpadTests/` (see Package.swift:46), so a loose .bats file at Tests/ root is invisible to `swift test`.
  - Matches the task's `tests/install.bats` wording (case-insensitive equivalent on macOS).

## Performance

`setup_file` builds the tarball once (which transitively builds the .app once) and shares both artifacts across tests 1, 2, 3. Total runtime ~25s on a warm cache, dominated by `swift build -c release`. Tests 4 + 5 are pure grep against checked-in files — sub-100ms.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

Pinned the two install-hygiene fixes (v0.1.2 bundle sealing, v0.1.3 quarantine strip) with a bats suite at `Tests/install.bats` so neither can silently regress.

## What shipped

- **`Tests/install.bats`** — five cases, ~190 lines incl. doc-comments:
  1. `build-app.sh` produces a bundle reporting `Sealed Resources version=2`.
  2. The release tarball preserves that seal after extraction.
  3. `install.sh` strips `com.apple.quarantine` when the xattr is present (planted-then-re-installed approach to actually exercise the strip — a naive run against `file://` never sets the xattr, so the original wording was near-fictional).
  4. `install.sh` source still contains the defensive `xattr -dr com.apple.quarantine` line (static grep — guards against silent deletion during refactor).
  5. `scripts/scratchpad.cask.rb.template` has `com.apple.quarantine` within 5 lines of `postflight do` (guards against Cask reformat dropping the block).

- **`Tests/README.md`** — bats install instructions, headline incidents the suite guards against, hand-off note for TASK-39 preflight wiring.
- **`README.md` Development section** — one-line `bats Tests/install.bats` addition.

## Verification

`bats Tests/install.bats` against current main:
```
1..5
ok 1 build-app.sh produces a sealed bundle (Sealed Resources version=2)
ok 2 tarball preserves bundle sealing after extraction
ok 3 install.sh strips com.apple.quarantine when present (behavioural)
ok 4 install.sh contains the defensive 'xattr -dr com.apple.quarantine' line
ok 5 Cask template carries the postflight com.apple.quarantine strip
```

Runtime ~25s on warm cache, dominated by `swift build -c release` (build is shared across tests 1+2+3 via `setup_file`).

## Deviations from original spec

- **5 tests, not 4.** Original test #3 split into behavioural + static-grep variants (see implementation notes for why).
- **AC#3 partial.** Standalone runner complete; the `preflight-release.sh` wiring half is one line that belongs in TASK-39's PR, not this one. Tests/README.md flags this to whoever picks up TASK-39.

## Follow-ups

- TASK-39 owner: add `bats Tests/install.bats` to `scripts/preflight-release.sh` when that script is created.
- TASK-40 (tart VM testing) remains the right place for end-to-end Gatekeeper verification on a clean macOS — bats can only pin what's testable on the dev host.
<!-- SECTION:FINAL_SUMMARY:END -->

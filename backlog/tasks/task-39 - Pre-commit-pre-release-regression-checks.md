---
id: TASK-39
title: Pre-commit + pre-release regression checks
status: Done
assignee: []
created_date: '2026-05-25 10:34'
updated_date: '2026-05-27 15:44'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-34
references:
  - backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md
modified_files:
  - scripts/preflight-release.sh
  - scripts/build-app.sh
  - scripts/build-dmg.sh
  - scripts/build-tarball.sh
  - scripts/release.sh
  - lefthook.yml
  - backlog/docs/release-runbook.md
  - README.md
  - Tests/README.md
priority: medium
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wrap the existing build + test scripts into automation that runs at the right git/release moments so nothing ships with a broken artifact pipeline. Now that TASK-38 reinstated `swift test` and TASK-28/30/33 produce concrete release artifacts, there's enough surface to regress against.

Two scopes, one task (shared infrastructure):

**Pre-commit (cheap, runs on every commit):**
- `swift test` — fast feedback on logic regressions.
- `shellcheck scripts/*.sh install.sh` (once install.sh lands via TASK-34) — catches shell footguns in the artifact pipeline.
- `plutil -lint` on any Info.plist under version control.
- Implemented as either a plain git hook (`.git/hooks/pre-commit`) or a lefthook / pre-commit-framework config — pick one in the implementation notes; pre-commit-framework gives multi-language tooling, lefthook is faster, plain git hooks have zero deps. Default recommendation: lefthook (simple, fast, declarative `lefthook.yml`).

**Pre-release (heavier, runs before cutting a GitHub Release):**
- `scripts/preflight-release.sh` that chains: clean build dir → `swift test` → `scripts/build-app.sh` → `scripts/build-tarball.sh` → `scripts/build-dmg.sh` → verify tarball sha256 round-trips → verify DMG mounts cleanly → optionally exercise `install.sh` end-to-end against a tmp prefix.
- Runbook update: TASK-34's `backlog/docs/release-runbook.md` gets a "before `gh release create`, run `scripts/preflight-release.sh`" step at the top.

CI parallel: same checks should run on GitHub Actions for every PR. Out of scope for this task (no GitHub Actions yet), but the scripts must be CI-friendly (no interactive prompts, exit codes accurate, no assumptions about a logged-in `gh` cli).

Why now-but-later: writing this before TASK-34 (curl installer) lands would mean re-doing the script chaining; writing it after the v1 release would mean shipping the first cut without a safety net. Sweet spot is "after TASK-34 ships, before the first GitHub Release".

References:
- lefthook: https://github.com/evilmartians/lefthook
- pre-commit framework: https://pre-commit.com/
- shellcheck: https://www.shellcheck.net/
- decision-3 (release-artifact strategy this task regresses against): backlog/decisions/decision-3
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pre-commit hook (lefthook config or equivalent) runs `swift test` + shellcheck on every commit, with a one-line README note on how to install it
- [x] #2 scripts/preflight-release.sh chains swift test → build-app.sh → build-tarball.sh → build-dmg.sh → sha256 + DMG-mount verification, and exits non-zero on any failure
- [x] #3 Release runbook (backlog/docs/release-runbook.md) has a 'run preflight-release.sh' step at the top of the release-cut sequence
- [x] #4 Pre-commit hook respects `git commit --no-verify` (standard behaviour, but called out so future-us doesn't second-guess); preflight-release.sh has no skip flag
- [x] #5 Scripts produce no interactive prompts and have accurate exit codes so a future CI integration can call them unmodified
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Approved plan (2026-05-27)

### Part A: scripts/preflight-release.sh

Sequential chain, fails fast on any non-zero step. No interactive prompts (CI-friendly). No skip flag (per AC#4).

1. Clean `build/` (test from zero state).
2. `swift test` (pure-logic regressions).
3. `bats Tests/install.bats` (install-hygiene regression guards; 5 cases). Wires the TASK-48 deferral.
4. `scripts/build-app.sh`.
5. `scripts/build-tarball.sh`.
6. `scripts/build-dmg.sh`.
7. Tarball sha256 round-trip: `shasum -a 256 -c Scratchpad-arm64.tar.gz.sha256`.
8. DMG mount/detach via hdiutil (catches corrupt-DMG before publish).
9. `shellcheck scripts/*.sh install.sh` (default severity).

Each step prefixed with `==> step N/9: <name>`; failure prints the regressed step plus underlying tool stderr.

### Part B: lefthook.yml

```yaml
pre-commit:
  parallel: true
  commands:
    swift-test:
      run: swift test
    shellcheck:
      glob: "{scripts/*.sh,install.sh,lefthook.yml}"
      run: shellcheck {staged_files}
```

- Parallel: ~3-5s wall on warm cache.
- shellcheck only runs when shell scripts are staged (glob gate).
- `git commit --no-verify` bypasses (lefthook + git standard).

### Part C: release-runbook.md update

Replace section "0. Pre-flight (will become automated by TASK-39)" with a one-liner pointing at `./scripts/preflight-release.sh`. Keep the manual bullets as a fallback subsection for "when you need to debug a specific step."

### Files

- `scripts/preflight-release.sh` (new)
- `lefthook.yml` (new)
- `backlog/docs/release-runbook.md` (replace section 0)
- `README.md` (one line under Development: lefthook install instructions)
- `Tests/README.md` (note that bats is now wired into preflight, closing TASK-48 deferral)

### Deferred

- `plutil -lint` on Info.plist: no version-controlled plist exists (generated by build-app.sh).
- bats in pre-commit: ~25s; too slow for every-commit cadence. Lives in preflight only.
- install.sh end-to-end in preflight: already exercised by Tests/install.bats test #3 (chained as preflight step 3).
- GitHub Actions wiring: explicitly out of scope per task description.

### User-side prerequisites

`brew install lefthook shellcheck`, then `lefthook install` once to register the git hook.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-05-27 — Implementation complete. Preflight chain passes end-to-end (~60-90s wall on warm cache); lefthook pre-commit runs swift-test + shellcheck in parallel (~4s wall).

## Scope adjustment: pre-existing SC2295 fixes in 4 unrelated scripts

Shellcheck flagged `${VAR#${PREFIX}/}` patterns in build-app.sh, build-dmg.sh, build-tarball.sh, and release.sh — SC2295 (info-level): inner expansions inside `${..#..}` need to be quoted separately, otherwise they're treated as glob patterns. Latent bug if any project path ever contained shell glob characters. Fixed all 4 mechanically: `${VAR#${PREFIX}/}` → `${VAR#"${PREFIX}"/}`. Zero behaviour change for paths without glob chars.

Fix was in-scope because TASK-39's pre-commit gate requires the baseline to be shellcheck-clean — otherwise every future commit touching these files would fail the hook on issues that already existed. The alternative (per-file `# shellcheck disable=SC2295` annotations) would be louder noise for no behavioural benefit.

## Lefthook behavioural verification

- Hook registered at `.git/hooks/pre-commit` after `lefthook install`.
- Commands without a `glob` (swift-test) run when any file is staged; skip with "no matching staged files" when stage is empty (e.g. `lefthook run pre-commit` invoked manually with no changes). That's the desired behaviour — a commit always has staged files by definition.
- Glob-gated commands (shellcheck) only run when their glob matches a staged file. Confirmed: staging only docs doesn't trigger shellcheck; staging a `.sh` file does.
- Parallel execution: shellcheck (0.23s) and swift-test (4.02s) overlap; wall time = max of the two.
- `git commit --no-verify` bypasses (git-standard, lefthook-respected).

## Preflight step-by-step results (against current HEAD)

```
step 1/9: clean build/                  ✓ build/ removed
step 2/9: swift test                    ✓ 35 tests passed (~3s)
step 3/9: bats Tests/install.bats       ✓ 5/5 cases passed (~25s incl. release build)
step 4/9: scripts/build-app.sh          ✓ Scratchpad.app produced + sealed
step 5/9: scripts/build-tarball.sh      ✓ tarball + sha256 sidecar
step 6/9: scripts/build-dmg.sh          ✓ Scratchpad.dmg (240K)
step 7/9: tarball sha256 round-trip     ✓ sidecar matches
step 8/9: DMG mount/detach              ✓ contains Scratchpad.app, detaches cleanly
step 9/9: shellcheck                    ✓ clean (after baseline fixes)
```

First run caught real issues at step 9 (the SC2295s + two unused color vars I'd left in preflight-release.sh's else branch). All fixed; second run green end-to-end.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

Shipped both halves of the regression-check safety net: a fast pre-commit hook (lefthook) and a heavyweight pre-release chain (`scripts/preflight-release.sh`). Together they close the gap that let v0.1.1 → v0.1.3's install-hygiene regressions slip through.

## What shipped

- **`scripts/preflight-release.sh`** (~250 lines) — 9 sequential steps from a clean state: `rm -rf build/` → `swift test` → `bats Tests/install.bats` → `build-app.sh` → `build-tarball.sh` → `build-dmg.sh` → tarball sha256 round-trip → DMG mount/detach via hdiutil → `shellcheck` over all shell scripts. Fails fast at the regressed step with the step name + underlying tool stderr. No prompts, no skip flag — runs unmodified in CI.
- **`lefthook.yml`** — pre-commit hook running `swift test` + `shellcheck` (glob-gated to staged shell files) in parallel. ~4s wall time on warm cache. `git commit --no-verify` bypasses (called out per AC#4).
- **`backlog/docs/release-runbook.md`** — section 0 ("Pre-flight") replaced with a one-line `./scripts/preflight-release.sh` invocation. Manual steps kept as a fallback subsection for debugging.
- **`README.md`** — Development section gained `lefthook install` + `preflight-release.sh` lines, with prereq install notes.
- **`Tests/README.md`** — preflight-wiring section updated (closes TASK-48's deferred AC#3).
- **Pre-existing scripts (build-app.sh, build-dmg.sh, build-tarball.sh, release.sh)** — SC2295 fixes (`${VAR#${PREFIX}/}` → `${VAR#"${PREFIX}"/}`). In-scope baseline cleanup so the new shellcheck gate doesn't fire false-alarms on day one.

## Verification (all 5 ACs)

- **#1** lefthook config runs `swift test` + shellcheck on every commit; README documents the one-time `brew install lefthook shellcheck && lefthook install`. ✓
- **#2** preflight-release.sh chains all the named steps + sha256/DMG verification + the bats install-hygiene suite (closing the TASK-48 deferral); exits non-zero from whichever step regresses. Full chain run end-to-end, ~75s. ✓
- **#3** release-runbook.md section 0 starts with `./scripts/preflight-release.sh`. ✓
- **#4** `--no-verify` works (git/lefthook standard); preflight has no skip flag. ✓
- **#5** No interactive prompts; exit codes propagate accurately; no `gh` assumptions. ✓

## Deferred (per task body)

- **GitHub Actions wiring** — explicitly out of scope today. preflight-release.sh is written to drop into a future macOS-runner job unmodified (no prompts, accurate exit codes).
- **`plutil -lint`** — no version-controlled Info.plist exists; it's generated by `build-app.sh` from a heredoc.
- **bats in pre-commit** — ~25s including the release-mode swift build; too slow for every-commit cadence. Lives in preflight only.

## Follow-ups flagged

- TASK-40 (tart VM testing) is the right place for real-Gatekeeper-on-clean-macOS verification — preflight can only check artifact properties on the dev host.
- When GitHub Actions lands, `scripts/preflight-release.sh` is the single command to wire as a macOS-runner job.
<!-- SECTION:FINAL_SUMMARY:END -->

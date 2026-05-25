---
id: TASK-39
title: Pre-commit + pre-release regression checks
status: To Do
assignee: []
created_date: '2026-05-25 10:34'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-34
references:
  - backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md
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
- [ ] #1 Pre-commit hook (lefthook config or equivalent) runs `swift test` + shellcheck on every commit, with a one-line README note on how to install it
- [ ] #2 scripts/preflight-release.sh chains swift test → build-app.sh → build-tarball.sh → build-dmg.sh → sha256 + DMG-mount verification, and exits non-zero on any failure
- [ ] #3 Release runbook (backlog/docs/release-runbook.md) has a 'run preflight-release.sh' step at the top of the release-cut sequence
- [ ] #4 Pre-commit hook respects `git commit --no-verify` (standard behaviour, but called out so future-us doesn't second-guess); preflight-release.sh has no skip flag
- [ ] #5 Scripts produce no interactive prompts and have accurate exit codes so a future CI integration can call them unmodified
<!-- AC:END -->

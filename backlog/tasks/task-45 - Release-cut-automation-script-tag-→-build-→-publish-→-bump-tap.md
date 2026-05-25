---
id: TASK-45
title: Release-cut automation script (tag → build → publish → bump tap)
status: Done
assignee: []
created_date: '2026-05-25 13:46'
updated_date: '2026-05-25 13:50'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-32
  - TASK-34
modified_files:
  - scripts/release.sh
  - backlog/docs/release-runbook.md
priority: medium
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Single `scripts/release.sh` that walks the whole release-cut flow currently documented in `backlog/docs/release-runbook.md`. Eliminates the manual copy-paste of sha256 values between repos, the "did I remember to push the tag" gotcha, and the "wait did I create the GitHub Release yet" ambiguity.

Bridges TASK-32 (tap repo bump) and TASK-34 (release artifact pipeline). Distinct from TASK-39 (pre-commit + pre-release regression checks) which is about *correctness gates*; this task is about the *release sequencing workflow*.

The script must:
- Be idempotent at every step (re-runnable after a partial failure).
- Default to interactive confirmation; offer `--yes` for CI.
- Offer `--dry-run` for first-time / nervous runs.
- Find the tap repo via `SCRATCHPAD_TAP_DIR` env var (default `../homebrew-scratchpad`).
- Update the Cask formula in-place via sed (or equivalent), commit, push.
- Print a clear go/no-go summary at each stage.

The existing release runbook continues to document the manual flow as reference / fallback, with a "TL;DR: `./scripts/release.sh vX.Y.Z`" pointer at the top.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 scripts/release.sh exists, takes a version arg (e.g. v0.1.0), and walks the full flow
- [x] #2 Idempotent: re-running after a tag/release/cask-update already exists detects and skips that step rather than failing
- [x] #3 Preflight checks: clean working dir, gh authenticated, tap repo present at SCRATCHPAD_TAP_DIR (default ../homebrew-scratchpad)
- [x] #4 --dry-run prints the planned steps without executing
- [x] #5 --yes skips confirmation prompts (for CI use)
- [x] #6 Updates Casks/scratchpad.rb in the tap repo with the new version + sha256, commits, pushes
- [x] #7 Release runbook updated with the new TL;DR script-based flow at the top, manual steps retained below as reference
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## scripts/release.sh

Single ~280-line script walking the full release flow in six numbered steps with bold/dim/coloured progress headers:

| Step | What it does | Idempotency strategy |
|---|---|---|
| 1. Preflight | Working tree clean · current branch (warn-only on non-main) · gh authenticated · tap repo present at `SCRATCHPAD_TAP_DIR` · tap repo clean | All hard fails; nothing to be idempotent about |
| 2. Tag + push | `git tag -a vX.Y.Z` then `git push origin vX.Y.Z` | Existing tag at HEAD → skip. Existing tag at *different* SHA → hard fail (refuses to silently re-tag). Already on origin → skip the push |
| 3. Build artifacts | Calls `scripts/build-tarball.sh` and `scripts/build-dmg.sh` (both already idempotent) | Always rebuild — cheap on warm SwiftPM cache; previous build/ may be from a different commit if re-running after a partial failure |
| 4. Publish GH Release | `gh release create` with tarball + .sha256 + DMG, `--generate-notes` | `gh release view` as existence probe; if release exists, skip and print the `gh release upload --clobber` recipe for asset replacement |
| 5. Verify /latest/ redirect | `curl -sILo /dev/null -w '%{url_effective}'` on the `/releases/latest/download/` URL, asserts the resolved URL contains the new tag | Warn-only — GitHub occasionally takes a few seconds to update the latest-pointer |
| 6. Bump tap | `git pull --ff-only` in tap → sed-rewrites version + sha256 lines in `Casks/scratchpad.rb` → diffs the change for visual inspection → commits + pushes if anything changed | sed pattern is whitespace-flexible. Post-edit verification confirms new sha256 actually landed (catches a reformatted Cask that broke the regex). No commit if file unchanged |

Plus a final summary panel printing release URL, sha256, and the two smoke-test install commands.

### Design choices

- **`run` wrapper** — every shell command goes through `run "$@"` which either executes or prints (under `--dry-run`). Passes argv as separate args so quoting stays intact; `eval` would undo that.
- **`confirm` wrapper** — interactive `read -p` by default; bypassed by both `--yes` and `--dry-run` (no point asking when nothing executes).
- **`SCRATCHPAD_TAP_DIR` env var** — defaults to `${PROJECT_ROOT}/../homebrew-scratchpad` (matches what `gh repo clone aaronmyatt/homebrew-scratchpad` gives you when run from the Scratchpad parent dir).
- **GitHub repo coords** — derived via `gh repo view --json nameWithOwner` so a fork/rename works without env-var dance; falls back to `aaronmyatt/scratchpad` literal if gh fails (extremely defensive — gh is already checked in preflight).
- **BSD `sed -i ''`** — not GNU. We're macOS-only per decision-1.
- **Tap repo `git pull --ff-only`** before editing — refuses to merge unrelated work; safe because we already validated the tap repo was clean in preflight.

### What I did NOT do

- No automatic tag rollback on failure. If `gh release create` errors after the tag is pushed, the user is expected to investigate (a partial release is rarely a "delete the tag" situation). The idempotent re-run logic in step 2 means re-running the script is safe — the existing tag is detected and the script picks up at step 3.
- No `--skip-build` flag. SwiftPM's incremental build makes the second build cheap; adding the flag invites users to publish stale artifacts.
- No auto-rollback of the tap commit if the next step fails. The tap commit is the *last* step, so this can't actually happen.

### Smoke-testing limitations

- This dev environment's CWD isn't itself a git repo (per session context), so a "clone the repo and dry-run from there" test failed at the clone step. Verified instead via:
  - `bash -n` syntax check (clean)
  - `release.sh --help` output (correct usage + env default printed)
  - `release.sh v0.0.99 --dry-run --yes` against a synthetic tap (preflight correctly refused on this session's dirty working tree — AC#3 demonstrably enforces)
- The user can run `./scripts/release.sh v0.1.0 --dry-run` from a clean checkout against their real tap to verify end-to-end before the first real cut. The first real run is itself a low-stakes test — every step is rollback-able (`git tag -d` / `gh release delete` / `git revert` in tap) and re-runnable.

## backlog/docs/release-runbook.md

Added a "TL;DR — the one-liner" section right under the intro, calling out `./scripts/release.sh v0.1.0` as the 99%-case workflow. Documented `--dry-run`, `--yes`, and `SCRATCHPAD_TAP_DIR` env override. Existing manual steps retained below as reference / fallback for "what the script does under the hood" and one-off situations. Satisfies AC#7.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scripts/release.sh walks tag → push → build → publish → verify → tap-bump in six idempotent steps. Defaults to interactive confirmation; `--yes` for CI, `--dry-run` for a nervous first run. Tap repo via `SCRATCHPAD_TAP_DIR` (default `../homebrew-scratchpad`). Release runbook updated with the TL;DR script-based flow at the top, manual steps retained as reference.
<!-- SECTION:FINAL_SUMMARY:END -->

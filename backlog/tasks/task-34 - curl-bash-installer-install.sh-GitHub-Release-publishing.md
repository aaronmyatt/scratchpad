---
id: TASK-34
title: curl | bash installer (install.sh) + GitHub Release publishing
status: Done
assignee: []
created_date: '2026-05-25 07:29'
updated_date: '2026-05-25 10:39'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-33
references:
  - backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md
modified_files:
  - install.sh
  - backlog/docs/release-runbook.md
priority: high
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A self-contained `install.sh` users can run as `curl -fsSL <url> | bash` to install Scratchpad.app into `/Applications` (with a `~/Applications` fallback) without ever triggering Gatekeeper.

Why this works: `curl` does not set the `com.apple.quarantine` xattr (only browsers and a few sandboxed downloaders do), so the resulting `.app` launches with no Gatekeeper friction — same trick Homebrew itself, rustup, deno, and bun use. See decision-3 for the full rationale.

Deliverable:
- `install.sh` at the repo root (so users can inspect it with `curl ... | less` before piping to bash). Logic:
  1. Detect arch (`uname -m`); error out with a useful message on x86_64 for now (decision-1 narrowed v1 to Apple Silicon; revisit later).
  2. Resolve the latest GitHub Release tag via `gh api` if available, otherwise via `curl https://api.github.com/repos/aaronmyatt/scratchpad/releases/latest`.
  3. Fetch the tarball + the `.sha256` sidecar produced by TASK-33.
  4. Verify the checksum (`shasum -a 256 -c` against the sidecar). Abort on mismatch with a clear error.
  5. Extract into `/Applications` if writable, otherwise `~/Applications` (creating the dir if needed). Never use sudo automatically.
  6. Print a one-line "open Scratchpad.app to finish setup (you'll be offered to install `sp` on PATH)" — leveraging TASK-29's PathInstaller for the CLI shortcut.
- A short release-cut runbook at `backlog/docs/release-runbook.md` describing the steps:
    1. `scripts/build-tarball.sh` + `scripts/build-dmg.sh` to produce artifacts.
    2. `gh release create vX.Y.Z build/Scratchpad-arm64.tar.gz build/Scratchpad-arm64.tar.gz.sha256 build/Scratchpad.dmg`.
    3. Bump the version pinned at the top of `install.sh` if we choose to pin instead of always-latest.

Security/trust mitigations baked in:
- install.sh always verifies the sha256 before extracting; tampered artifacts fail loudly.
- Script header includes its own README pointer so a `curl … | less` reader sees the rationale up front.

Depends on TASK-33 (the tarball + sha256 sidecar must exist on every release).

References:
- Quarantine xattr behaviour: https://eclecticlight.co/2024/10/24/the-life-and-death-of-quarantine-attributes/
- gh release API: https://cli.github.com/manual/gh_release_create
- decision-3: backlog/decisions/decision-3
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 install.sh fetches the latest GitHub Release tarball and extracts Scratchpad.app into /Applications (or ~/Applications fallback)
- [x] #2 install.sh verifies the .sha256 sidecar and aborts on mismatch
- [x] #3 Running install.sh end-to-end produces a launchable .app with no Gatekeeper prompt (quarantine xattr not set)
- [x] #4 install.sh refuses to run on x86_64 with a helpful error pointing at the Apple Silicon scope
- [x] #5 backlog/docs/release-runbook.md captures the build → publish → bump-install.sh flow
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
install.sh shipped at the repo root (~12KB, well-commented per CLAUDE.md). Self-contained — depends only on macOS-bundled tools (curl, tar, shasum, xattr, pgrep, mv). Same artifact (TASK-33's tarball + sidecar) feeds this and the brew Cask (TASK-32), so the two install paths can't drift.

Architecture highlights:
- **Default URL strategy**: GitHub's `/releases/latest/download/<asset>` redirect. Means install.sh never has to parse JSON from the GitHub API to find the "latest" tag — a curl -L follows the 302 server-side. Pinning via `SCRATCHPAD_VERSION=v0.1.0` switches to the `/releases/download/<tag>/<asset>` pattern.
- **Test/CI seam**: `SCRATCHPAD_TARBALL_URL` env var overrides the URL entirely. Primary use: smoke-test install.sh against a local `file://` artifact before publishing a release (this script was verified end-to-end via that seam against TASK-33's tarball).
- **Install dir picker**: explicit `SCRATCHPAD_INSTALL_DIR` wins; otherwise `/Applications` if writable; otherwise `~/Applications` (created if missing). Never sudo.
- **Defence-in-depth quarantine strip**: `xattr -dr com.apple.quarantine` post-extract. curl doesn't set the attribute, but a corporate proxy or future curl version could. Cost is microseconds, saves a footgun.
- **Friendly errors**: arch refusal points at decision-1; checksum mismatch is loud and aborts before extract; pretty-prints with ANSI only when stdout is a tty (preserves grep-able CI logs).

Verification (run against TASK-33's local tarball):

  AC#1 (extract to install dir): ✓ tarball downloaded, Scratchpad.app landed at the configured dir.
  AC#2 (sha256 verification, positive): ✓ "checksum OK" printed.
  AC#2 (sha256 verification, negative): ✓ tampered tarball → "shasum: WARNING: 1 computed checksum did NOT match" → "Checksum mismatch — refusing to install" → exit 1 → no install at target.
  AC#3 (no Gatekeeper prompt): ✓ `xattr -p com.apple.quarantine` on installed .app returns "No such xattr".
  AC#4 (x86_64 refusal): ✓ verified via a uname shim — printed the friendly multi-line error pointing at decision-1.

backlog/docs/release-runbook.md captures the full cut-a-release flow:
  0. Preflight (manual until TASK-39).
  1. git tag + push (build scripts pull version from `git describe`).
  2. scripts/build-tarball.sh + scripts/build-dmg.sh.
  3. gh release create with all three artifacts.
  4. Cask bump in the homebrew-scratchpad tap repo (TASK-32 territory).
  5. install.sh — no edit needed for normal releases; SCRATCHPAD_VERSION lets users pin from the one-liner.
  6. Sanity test on a clean account (rm app + defaults delete + run the one-liner).

Notes on choices:
- Tarball as default artifact (not DMG) because tar+shasum can chain in one shell pipeline; DMG would need hdiutil attach/detach inside install.sh.
- No `--unsafe`-style escape hatch on the checksum check. The whole point of curl|bash is users trusting we verify — adding a skip flag would invite a "well, I'll just skip it" footgun in the runbook.
- `pgrep -x Scratchpad` before rm: not a blocker, but we surface a "quit and relaunch to pick up the new build" warning when relevant — macOS unlinks running binaries silently, so the user otherwise gets surprised that their old binary keeps running until quit.
- Did not introduce shellcheck linting yet — shellcheck isn't installed on this machine; TASK-39 (pre-commit hooks) will add it as a dependency.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
install.sh shipped at the repo root with a SCRATCHPAD_TARBALL_URL test seam (used to verify all four programmable ACs against TASK-33's local tarball: extract works, tampered checksum aborts cleanly with exit 1, no quarantine xattr ends up on the installed .app, x86_64 hard-fails with a friendly pointer at decision-1). Release runbook published at backlog/docs/release-runbook.md, covering preflight → tag → build → publish → Cask bump → sanity-test on clean account.
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-33
title: Tarball artifact + sha256 publish (shared by brew + curl installers)
status: Done
assignee: []
created_date: '2026-05-25 07:28'
updated_date: '2026-05-25 07:37'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md
modified_files:
  - scripts/build-tarball.sh
priority: high
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Produce the canonical distribution artifact: `build/Scratchpad-arm64.tar.gz`, a gzipped tarball of `Scratchpad.app` plus a sidecar `Scratchpad-arm64.tar.gz.sha256` file. This artifact is the single source of truth that both the Homebrew Cask (TASK-32) and the curl|bash installer (TASK-34) point at — there must be exactly one place a release artifact is produced.

Why a tarball and not just the DMG:
- A tarball can be extracted with one `tar xz -C /Applications` line inside a shell installer; DMG requires the `hdiutil attach` / `cp` / `hdiutil detach` dance.
- Homebrew Casks support both `.dmg` and `.zip`/`.tar.gz` URLs; either works for brew. The tarball is smaller (no HFS+ overhead) and faster to fetch.
- The DMG (TASK-30) remains the artifact for the direct-download channel — visual drag-to-Applications matters there.

Per decision-3, no signing/notarization is performed; ad-hoc signing from `swift build` is sufficient for Apple Silicon launch.

Deliverable:
- `scripts/build-tarball.sh` that:
  1. Calls `scripts/build-app.sh` (idempotent, builds the bundle).
  2. Detects host arch (`uname -m`) and names the output accordingly (`Scratchpad-arm64.tar.gz` for now; cross-arch deferred).
  3. Runs `tar -czf build/Scratchpad-arm64.tar.gz -C build Scratchpad.app` (the `-C build` keeps the archive root clean — extraction yields `Scratchpad.app` directly, no nested path).
  4. Writes `build/Scratchpad-arm64.tar.gz.sha256` via `shasum -a 256`.
  5. Prints final sizes + the sha256 so the values can be pasted into the Cask formula / install.sh.

The script must be runnable from a clean checkout with no third-party tooling (tar, shasum ship with macOS).

References:
- shasum(1) on macOS: ships with /usr/bin/shasum
- BSD tar: ships with /usr/bin/tar
- decision-3 (skip-notarization rationale): backlog/decisions/decision-3
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 scripts/build-tarball.sh produces build/Scratchpad-arm64.tar.gz from a clean checkout
- [x] #2 Tarball extracts to a single Scratchpad.app directory (no nested wrapper path)
- [x] #3 Sidecar build/Scratchpad-arm64.tar.gz.sha256 file is written and matches `shasum -a 256` of the tarball
- [x] #4 Script prints the sha256 hex string to stdout for easy copy-paste into Cask / install.sh
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
scripts/build-tarball.sh wraps scripts/build-app.sh, then produces a tarball + sha256 sidecar in build/.

Key decisions baked into the script:
- Arch detection via `uname -m`. arm64 → Scratchpad-arm64.tar.gz. x86_64 → hard fail with a useful message (per decision-1 we're Apple Silicon only; silently mis-naming an Intel tarball would create a footgun for TASK-32/34).
- `tar -czf <out> -C build Scratchpad.app` — the `-C` flag is what keeps the archive root clean (extraction yields `Scratchpad.app` directly, not `build/Scratchpad.app`). Verified: `tar -tzf` lists `Scratchpad.app/` as the first entry, 8 entries total.
- Round-trip sanity check (`tar -tzf <out> >/dev/null`) right after creation so a corrupt gzip stream fails the build, not the release.
- sha256 sidecar written from inside the build/ dir so the filename in the sidecar is bare — that's what `shasum -a 256 -c` expects when run alongside the tarball during install. Format follows the standard `<hex>  <filename>` shasum convention.
- Script picks sha256 (not sha512/BLAKE3) deliberately — Homebrew Cask's `sha256` stanza dictates the algorithm. Single algorithm across Cask + install.sh + runbook keeps things consistent.
- We deliberately don't add xattr-preservation flags. macOS BSD tar preserves the executable bit on Mach-O binaries by default; pulling extended-attribute round-tripping into install.sh / the Cask would mean extra `xattr` commands on the consumer side, which we don't want.

Output of a fresh run:
- build/Scratchpad-arm64.tar.gz (164K)
- build/Scratchpad-arm64.tar.gz.sha256
- sha256 printed twice on stdout: once raw, once formatted as `sha256 "..."` ready to paste into the Cask formula.

Verification:
- `shasum -a 256 -c build/Scratchpad-arm64.tar.gz.sha256` → "Scratchpad-arm64.tar.gz: OK".
- Archive listing confirms `Scratchpad.app/` as the root entry, no nested `build/` wrapper.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scripts/build-tarball.sh produces build/Scratchpad-arm64.tar.gz (164K) and a matching .sha256 sidecar from a clean checkout. Archive root is `Scratchpad.app/` so install.sh can do `tar xz -C /Applications` directly. Script prints the sha256 hex twice — raw and formatted as `sha256 "..."` for paste into the Cask formula. Refuses to build for x86_64 with a useful error pointing at decision-1.
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-30
title: DMG packaging script (Scratchpad.dmg with /Applications shortcut)
status: Done
assignee: []
created_date: '2026-05-24 16:04'
updated_date: '2026-05-25 03:44'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-28
modified_files:
  - scripts/build-dmg.sh
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/build-dmg.sh that takes the assembled Scratchpad.app and produces Scratchpad.dmg with the standard drag-to-Applications layout. Uses `hdiutil` (no third-party deps).

Depends on TASK-28. Used by the Homebrew formula (TASK-32) as the binary artifact.

Reference: https://el-tramo.be/blog/mountain-lion-makefile/
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 scripts/build-dmg.sh produces Scratchpad.dmg from Scratchpad.app
- [x] #2 DMG opens with the standard Applications-shortcut layout
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
scripts/build-dmg.sh wraps scripts/build-app.sh and hdiutil:

1. Calls build-app.sh first so a clean checkout → DMG is one command.
2. Stages Scratchpad.app plus an `Applications -> /Applications` symlink in a mktemp dir (trap-cleaned on exit) so the DMG layout is deterministic and doesn't accidentally pick up stale files from build/.
3. `hdiutil create -volname Scratchpad -srcfolder <stage> -format UDZO -fs HFS+ -ov` produces a compressed read-only image that mounts on every supported macOS.
4. `hdiutil verify` runs immediately so a bad image never ships.

No third-party deps — hdiutil ships with macOS, important because TASK-31 / GitHub Actions should be able to call this from a clean runner.

Verified by mounting the result: /Volumes/Scratchpad/ contains Scratchpad.app + Applications -> /Applications symlink, which Finder renders with the special folder badge — i.e. the standard drag-to-Applications layout. Final DMG ~200K (compressed).

Output: build/Scratchpad.dmg.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Done. scripts/build-dmg.sh produces build/Scratchpad.dmg using only macOS-built-in hdiutil. Bundle layout includes the standard `/Applications` shortcut. Verified by mounting + listing contents. TASK-31 will wrap this script with codesign + notarytool.
<!-- SECTION:FINAL_SUMMARY:END -->

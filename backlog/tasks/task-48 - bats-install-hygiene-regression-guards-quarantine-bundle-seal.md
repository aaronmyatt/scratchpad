---
id: TASK-48
title: 'bats: install-hygiene regression guards (quarantine + bundle seal)'
status: To Do
assignee: []
created_date: '2026-05-26 04:20'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-39
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
- [ ] #1 tests/install.bats (or chosen path under TASK-39's layout) exists with the four assertions above
- [ ] #2 All four bats cases pass against the current main branch
- [ ] #3 Tests are runnable standalone (`bats tests/install.bats`) AND wired into TASK-39's preflight-release.sh chain
- [ ] #4 Failure messages identify which install-hygiene regression has crept back in (don't just say 'expected X got Y' — say 'bundle missing Sealed Resources — see build-app.sh codesign block')
- [ ] #5 README's Development section gets a one-line note pointing at the test suite
<!-- AC:END -->

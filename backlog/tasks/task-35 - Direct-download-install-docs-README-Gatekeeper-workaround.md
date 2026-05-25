---
id: TASK-35
title: Direct-download install docs (README + Gatekeeper workaround)
status: To Do
assignee: []
created_date: '2026-05-25 07:29'
updated_date: '2026-05-25 12:29'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-30
references:
  - backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md
modified_files:
  - README.md
  - backlog/docs/install/direct-download.md
priority: medium
ordinal: 25500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document the third distribution channel: users download `Scratchpad.dmg` from the GitHub Releases page in their browser, drag the app into `/Applications`, and on first launch hit Gatekeeper because the app is unsigned (per decision-3). The README and the docs site need a clear, short workaround section.

Scope is documentation only — no new code. The DMG itself is already produced by TASK-30; this task just adds the user-facing instructions.

Deliverable:
- A "Direct download" section in the README that:
  1. Links to the latest GitHub Release.
  2. Calls out that brew and curl|bash are the friction-free options and should be preferred (one short paragraph).
  3. Documents the Gatekeeper workaround:
     - macOS 14: right-click → Open (one extra click).
     - macOS 15+ (Sequoia removed right-click → Open for unsigned apps): System Settings → Privacy & Security → scroll to the Scratchpad warning → "Open Anyway".
     - Terminal alternative: `xattr -dr com.apple.quarantine /Applications/Scratchpad.app`.
  4. Briefly explains *why* the warning happens (browsers set the quarantine xattr; brew/curl don't) so the user understands they're not bypassing security theatre arbitrarily.
- Same content adapted for the GitHub Pages site (TASK-36 will own the site itself; this task only commits to having the source content ready as a Markdown file under `backlog/docs/install/direct-download.md` that the Pages site can include).

References:
- Quarantine + Gatekeeper background: https://eclecticlight.co/2024/06/16/gatekeeper-changes-in-sequoia/
- xattr(1): https://ss64.com/mac/xattr.html
- decision-3 (why we're unsigned): backlog/decisions/decision-3
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README has a 'Direct download' section linking to the latest GitHub Release
- [x] #2 README documents the macOS 14 right-click → Open path and the macOS 15+ System Settings path
- [x] #3 README documents the xattr -dr terminal alternative
- [x] #4 Section explicitly recommends brew/curl as friction-free alternatives before showing the workaround
- [x] #5 backlog/docs/install/direct-download.md mirrors the content for reuse by the docs site (TASK-36)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
README restructured: added a new "Install" section above the existing dev-build instructions, listing all three install paths in order of recommended preference (brew → curl → direct download). Old "Run it" section renamed to "Development" and expanded with a pointer to the release-artifact build scripts (build-app.sh / build-tarball.sh / build-dmg.sh).

The "Install" section was sized to read top-to-bottom in priority order:
1. **Homebrew** — one-liner, marked as "lands with TASK-32" so it doesn't mislead before the tap exists.
2. **curl | bash** — one-liner using the canonical install.sh URL on main, links to local install.sh so a reader can `curl … | less` first.
3. **Direct download** — the substantive section this task owns. Leads with a heads-up callout pointing at decision-3 and gently redirecting users to brew/curl, *then* documents the three Gatekeeper workarounds (macOS 14 right-click → Open, macOS 15+ System Settings, terminal xattr -dr), *then* a one-paragraph "why the warning happens" explainer.

This ordering satisfies AC#4's "recommends brew/curl before showing the workaround" without burying the workaround so deep that direct-download users have to hunt for it.

The xattr -dr documentation (AC#3) is framed as "this is exactly what Homebrew does for you" rather than a security-bypass — keeps the trust narrative consistent.

backlog/docs/install/direct-download.md mirrors the README content but slightly expanded:
- Includes the "prefer brew/curl first" rationale as a first-class section rather than a callout box.
- Adds an "After install" section pointing at the PathInstaller first-launch prompt (helpful for users coming from the direct path who won't see the rest of the README install flow).
- Adds extra reference links (eclecticlight quarantine deep-dive, Sequoia changes).

The doc lives at backlog/docs/install/direct-download.md (new directory). TASK-36 (GitHub Pages) will pick it up as the source for the docs site's install/direct.md page — by mirroring rather than transcluding, both the README section and the standalone doc can evolve independently as needed, with this file as the canonical reference.

Out of scope (deliberately): the brew (TASK-32) and curl (TASK-34) detail docs at backlog/docs/install/brew.md and install/curl.md — those should land with their respective tasks rather than being pre-empted here.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
README has a new "Install" section presenting brew, curl, and direct-download paths in priority order. Direct download gets the full Gatekeeper workaround (macOS 14 right-click, macOS 15+ System Settings, terminal xattr -dr) plus a "why" explainer. backlog/docs/install/direct-download.md mirrors the content as the canonical source for TASK-36's docs site. Old "Run it" section renamed to "Development" and expanded with the release-artifact build scripts.
<!-- SECTION:FINAL_SUMMARY:END -->

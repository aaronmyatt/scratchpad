---
id: decision-3
title: Skip Apple notarization for v1; distribute via brew + curl + direct DMG
date: '2026-05-25'
status: accepted
---
## Context

TASK-37 (originally TASK-14, renumbered by Backlog.md after a Draft round-trip) lumped "signed + notarized .app + DMG" into the packaging
slice, on the assumption that distribution-quality builds must clear Gatekeeper
silently. After TASK-28/29/30 landed (unsigned .app, sp PathInstaller, DMG
script), revisiting the cost-vs-friction tradeoff for v1 surfaced three
distribution paths that don't require Apple notarization:

1. **Homebrew tap (Cask):** Our Cask's `postflight` block strips the
   `com.apple.quarantine` xattr after install, so Gatekeeper never enters the
   picture for `brew install`ed artifacts. (Note: brew Cask itself defaults
   to *quarantining* installed apps since ~2020; the strip is something our
   Cask actively does, not a brew default — this was a documentation
   misunderstanding fixed during the v0.1.3 release.) The main
   `homebrew/cask` repo rejects this pattern and requires signed apps; a
   personal tap (e.g. `github.com/aaronmyatt/homebrew-scratchpad`) has no
   such policy and the postflight strip is the accepted norm there.
2. **curl | bash installer:** `curl` does not set the quarantine xattr (only
   browsers and a few sandboxed downloaders do). A shell installer that fetches
   a tarball and copies it into `/Applications` produces an app launchable
   without Gatekeeper interaction. Standard pattern used by Homebrew itself,
   rustup, deno, bun, etc.
3. **Direct DMG download:** Browsers *do* set quarantine, so Gatekeeper blocks
   on first open. Workarounds: right-click → Open (removed in macOS 15 Sequoia
   for unsigned apps), System Settings → Privacy & Security → "Open Anyway",
   or `xattr -dr com.apple.quarantine /Applications/Scratchpad.app`. Friction-
   heavy but acceptable for a dev-tool audience.

Apple Developer Program enrollment is $99/yr plus the notarization workflow
overhead. Scratchpad's MVP audience is developers — the bar for tolerating
unsigned-software warnings is materially different than for consumer software.

## Decision

For v1, distribute Scratchpad as an **unsigned** application via three
channels in order of recommended preference:

  1. Homebrew tap (`brew install aaronmyatt/scratchpad/scratchpad`)
  2. curl | bash installer (`curl -fsSL <url>/install.sh | bash`)
  3. Direct DMG download from a GitHub Release, with Gatekeeper-workaround
     instructions in the README and on the docs site.

A single shared artifact — `Scratchpad-arm64.tar.gz` (and `Scratchpad.dmg` for
channel 3) — is produced by `scripts/build-tarball.sh` / `scripts/build-dmg.sh`
and published to a GitHub Release. The brew Cask and the curl installer both
point at the same tarball / sha256 so there is one source of truth.

Ad-hoc signing (`codesign --sign -`) is *required* on Apple Silicon for the
binary to launch at all; SwiftPM already applies this automatically during
`swift build`, so no extra step is needed.

References:
- LaunchServices quarantine: https://eclecticlight.co/2024/10/24/the-life-and-death-of-quarantine-attributes/
- Homebrew Cask quarantine handling: https://docs.brew.sh/Cask-Cookbook#stanza-quarantine
- Apple Notarization (when/if we revisit): https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Gatekeeper changes in Sequoia: https://eclecticlight.co/2024/06/16/gatekeeper-changes-in-sequoia/

## Consequences

**Positive**
- Zero recurring cost; no Developer Program enrollment needed for v1.
- TASK-31 (signing + notarization) drops off the critical path — it remains in
  the backlog as an optional future enhancement but no other task blocks on it.
- The brew + curl install paths produce a fully Gatekeeper-free first run,
  which is competitive with signed-app UX.
- Single artifact pipeline (tarball) feeds both automated install channels —
  less to maintain than separate signed/notarized variants.

**Negative / accepted tradeoffs**
- Direct-download users hit Gatekeeper friction on first launch. Mitigation:
  README and docs site lead with brew/curl; only document the workaround as a
  fallback. macOS 15 Sequoia tightened this path (removed right-click → Open
  for unsigned apps), which we accept.
- "Unsigned app from the internet" carries a perception cost with non-developer
  users. v1's audience is developers; revisit if/when that changes.
- `curl | bash` carries a security-stigma cost — partially mitigated by
  hosting install.sh in the repo (users can `curl … | less` first) and by the
  installer verifying a sha256 of the tarball before extracting.

**Follow-ups**
- TASK-33: `scripts/build-tarball.sh` (shared artifact).
- TASK-34: `install.sh` + GitHub Release publishing flow.
- TASK-32: revise so the Cask points at the unsigned tarball and remove the
  TASK-31 dependency.
- TASK-35: direct-download README section with Gatekeeper workarounds.
- TASK-36: GitHub Pages docs site aggregating all three install paths.
- TASK-31: leave in backlog as deferred / optional; revisit if v2 targets
  non-developer audiences.

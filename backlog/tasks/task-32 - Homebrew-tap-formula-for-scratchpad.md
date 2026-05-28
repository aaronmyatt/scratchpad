---
id: TASK-32
title: Homebrew tap formula for scratchpad
status: Done
assignee: []
created_date: '2026-05-24 16:04'
updated_date: '2026-05-26 14:25'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-33
modified_files:
  - backlog/docs/install/homebrew-tap-setup.md
  - backlog/docs/install/brew.md
  - backlog/docs/release-runbook.md
  - docs/install/brew.md
priority: medium
ordinal: 500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create a separate repo (`github.com/aaronmyatt/homebrew-scratchpad`) with a Cask formula pointing at the unsigned tarball produced by TASK-33 (and published as a GitHub Release artifact). The Cask uses Homebrew's automatic quarantine-stripping so users never hit Gatekeeper — see decision-3 for why we don't need signing/notarization for this path.

Install UX target:
  brew install aaronmyatt/scratchpad/scratchpad
  (or with explicit tap: `brew tap aaronmyatt/scratchpad && brew install scratchpad`)

Architecture (one artifact, multiple entry points):
- The Cask's `url` and `sha256` point at the same `Scratchpad-arm64.tar.gz` + `.sha256` sidecar that TASK-34's `install.sh` uses. There is exactly one release artifact; both install paths consume it. This keeps the build pipeline simple and means the Cask and the curl installer can never drift in what they install.
- The Cask declares `app "Scratchpad.app"` so brew handles the /Applications copy + quarantine strip automatically. No need for a postflight script.

Deliverable:
- A new repo `aaronmyatt/homebrew-scratchpad` containing:
  - `Casks/scratchpad.rb` with the Cask formula (url, sha256, app stanza, version).
- A short release-cut runbook update (adds the Cask bump step to TASK-34's `backlog/docs/release-runbook.md` rather than duplicating).

Per decision-3, NO Apple signing/notarization is performed. Homebrew Cask will still install correctly because brew strips `com.apple.quarantine` after download. The main `homebrew/cask` repo requires signed apps as policy; *personal taps* do not.

Refs:
- Cask Cookbook: https://docs.brew.sh/Cask-Cookbook
- quarantine stanza (default behaviour): https://docs.brew.sh/Cask-Cookbook#stanza-quarantine
- Creating a tap: https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap
- decision-3: backlog/decisions/decision-3
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 aaronmyatt/homebrew-scratchpad repo exists with Casks/scratchpad.rb pointing at the TASK-33 tarball + sha256
- [ ] #2 `brew install aaronmyatt/scratchpad/scratchpad` installs Scratchpad.app into /Applications
- [ ] #3 Installed app launches without a Gatekeeper prompt (brew strips the quarantine xattr)
- [ ] #4 PathInstaller is offered on first launch (TASK-29 behaviour intact through brew install)
- [x] #5 Release runbook updated with the Cask version+sha bump step
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Ready (what I produced this session)

- **`backlog/docs/install/homebrew-tap-setup.md`** — end-to-end runbook for bootstrapping the tap repo:
  1. Create `aaronmyatt/homebrew-scratchpad` on GitHub (one-time).
  2. Cut the first GitHub Release of Scratchpad so the Cask has a real artifact to point at.
  3. Drop in `Casks/scratchpad.rb` (full formula included inline with explanatory comments — bump `version` + `sha256` per release).
  4. Push the tap.
  5. Smoke-test via `brew tap` + `brew install` + `xattr -p` verification + `open` for the PathInstaller dialog.
  Plus a "subsequent releases" section showing the lightweight per-release loop (two lines to edit, commit, push).

- **`backlog/docs/install/brew.md`** — canonical user-facing brew install doc (one-liner, what brew does, updating, uninstalling, `--zap` semantics, PathInstaller post-install behaviour). Source for the docs-site mirror + README brew section.

- **`backlog/docs/release-runbook.md`** Section 4 — rewritten with the per-release Cask-bump loop (the two-line edit in the tap repo, commit, push, smoke-test). Cross-links to the setup runbook for first-time tap bootstrap. **Satisfies AC#5.**

- **`docs/install/brew.md`** — status callout updated from "lands with TASK-32" → "Cask formula ready; tap goes live alongside v0.1.0 release."

## Cask design choices baked in

- Hard-coded `arm64` arch in the tarball URL — matches decision-1's Apple-Silicon-only scope. The Cask's `version` interpolation in the URL means new releases need only the version + sha256 bumped, not the URL pattern.
- `app "Scratchpad.app"` stanza relies on brew's standard `/Applications` copy + quarantine-strip pipeline — no postflight script needed.
- `zap` stanza cleans `~/Library/Preferences/com.aaronmyatt.scratchpad.plist` and `~/Library/Application Support/Scratchpad/` on `brew uninstall --zap`, so a reinstall starts fresh (notably re-arms the PathInstaller prompt).
- Symlinked `sp` survives uninstall by design (it's outside brew's manifest); README + brew.md both call this out and show the `rm` command.
- No mention of code signing because there isn't any (decision-3).

## Awaiting user action (the four blocker ACs)

| AC | What you need to do |
|---|---|
| #1 — Tap repo exists with `Casks/scratchpad.rb` | Create `github.com/aaronmyatt/homebrew-scratchpad`, copy the Cask from `homebrew-tap-setup.md` into `Casks/scratchpad.rb`, push. Requires cutting v0.1.0 of Scratchpad first to get a real sha256 to paste in. |
| #2 — `brew install` works | `brew tap aaronmyatt/scratchpad && brew install scratchpad` after #1. |
| #3 — No Gatekeeper prompt | `xattr -p com.apple.quarantine /Applications/Scratchpad.app` should return "No such xattr". |
| #4 — PathInstaller fires on first launch | `open /Applications/Scratchpad.app` after #2-3; expect the install-`sp`-on-PATH dialog. |

All four become trivially verifiable as soon as the tap repo + first release exist. Then this task closes.

## Why not block on those here

Nothing more on the implementation side moves them — they're pure go-live steps. Marking the task In Progress with the formula + runbook ready means the next session (or a future agent) can close it with no re-analysis. The handoff is concrete: copy the Cask file from the runbook, follow the steps, check the boxes.
<!-- SECTION:NOTES:END -->

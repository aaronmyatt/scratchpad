---
id: doc-5
title: Homebrew tap setup runbook
created_date: 2026-05-25
---

# Homebrew tap setup (one-time)

> Owned by TASK-32. The Cask formula in this doc is the source of truth —
> when bumping versions, edit it here, then sync to the tap repo.

A "tap" is just a public GitHub repo that Homebrew knows how to find via
naming convention: `homebrew-<name>` under your user/org. Once tapped,
brew installs Casks from it like any other formula.

Target install UX (after this setup is complete):

```bash
brew install aaronmyatt/scratchpad/scratchpad
```

---

## 1. Create the tap repo

On GitHub: create a new **public** repo named exactly
`homebrew-scratchpad` under `aaronmyatt`
(`https://github.com/aaronmyatt/homebrew-scratchpad`). Repo can be
empty — Homebrew bootstraps the layout.

```bash
# Clone the empty repo locally
gh repo clone aaronmyatt/homebrew-scratchpad
cd homebrew-scratchpad

# Casks live under Casks/ by convention
mkdir Casks
```

Why a separate repo (not a folder inside `scratchpad/`): Homebrew's
auto-tap convention is hardcoded to `homebrew-<name>` repos. There's no
way to point it at a subfolder of another repo. The tap repo can stay
tiny — just the Cask formula and a README.

---

## 2. Cut the first release of Scratchpad

Before publishing the Cask, there needs to be a real GitHub Release of
Scratchpad that the Cask can point at. Follow
[`backlog/docs/release-runbook.md`](../release-runbook.md) end-to-end:

1. `git tag v0.1.0 && git push origin v0.1.0`
2. `./scripts/build-tarball.sh` — produces `Scratchpad-arm64.tar.gz`
   and `.sha256` under `build/`
3. `./scripts/build-dmg.sh` — produces `Scratchpad.dmg`
4. `gh release create v0.1.0 build/Scratchpad-arm64.tar.gz \
       build/Scratchpad-arm64.tar.gz.sha256 build/Scratchpad.dmg \
       --title "v0.1.0" --generate-notes`

Note the sha256 it prints — you'll paste it into the Cask in step 3.

---

## 3. Write the Cask

Create `Casks/scratchpad.rb` in the tap repo with this content. Bump
`version` and `sha256` on each release.

```ruby
# Homebrew Cask formula for Scratchpad.
#
# Cask DSL reference: https://docs.brew.sh/Cask-Cookbook
#
# Why a Cask and not a Formula:
#   - Casks distribute pre-built macOS .app bundles via brew's
#     /Applications copy + quarantine-strip pipeline.
#   - Formulas build from source — overkill for a binary distribution.
#
# Why this is in a personal tap, not homebrew/cask main:
#   - The main cask repo requires Apple signing + notarization, which
#     v1 deliberately skips (see decision-3 in the scratchpad repo).
#   - Personal taps have no such policy; brew's standard quarantine
#     strip still gives users a Gatekeeper-free install.

cask "scratchpad" do
  # Bump on each release. `arch` is intentionally hard-coded to arm64
  # for v1 (Apple-Silicon-only per decision-1); add Intel by switching
  # to a universal tarball later.
  version "0.1.0"
  sha256  "PASTE_SHA256_FROM_BUILD_TARBALL_SH_OUTPUT_HERE"

  url      "https://github.com/aaronmyatt/scratchpad/releases/download/v#{version}/Scratchpad-arm64.tar.gz"
  name     "Scratchpad"
  desc     "Pinned, menu-bar-resident dump receiver for macOS"
  homepage "https://github.com/aaronmyatt/scratchpad"

  # The `app` stanza handles:
  #   - Copying Scratchpad.app into /Applications
  #   - Stripping the com.apple.quarantine xattr (the friction-free
  #     Gatekeeper bypass that justifies this whole install path)
  #   - Tracking the install in brew's manifest for clean uninstalls
  app "Scratchpad.app"

  # First-launch behaviour (PathInstaller, TASK-29 in the scratchpad
  # repo) handles the `sp` CLI on PATH — no postflight needed here.

  # Uninstall: brew handles app removal automatically via the `app`
  # stanza; we just clean up UserDefaults so a reinstall starts fresh.
  zap trash: [
    "~/Library/Preferences/com.aaronmyatt.scratchpad.plist",
    "~/Library/Application Support/Scratchpad",
  ]
end
```

Substitute `PASTE_SHA256_FROM_BUILD_TARBALL_SH_OUTPUT_HERE` with the
sha256 printed by `./scripts/build-tarball.sh` in step 2.

---

## 4. Push the tap

```bash
git add Casks/scratchpad.rb
git commit -m "Scratchpad v0.1.0"
git push
```

Tap is live the moment the push lands. No GitHub Pages, no Actions, no
publishing step.

---

## 5. Verify on a clean install

```bash
# In a fresh terminal (so the tap is fetched from scratch):
brew tap aaronmyatt/scratchpad
brew install scratchpad

# Verify
ls /Applications/Scratchpad.app                                          # → exists
xattr -p com.apple.quarantine /Applications/Scratchpad.app 2>&1 | head -1
# → "No such xattr: com.apple.quarantine" (brew stripped it)

open /Applications/Scratchpad.app
# → menu-bar icon appears; first-launch PathInstaller dialog offers
#   to install sp on PATH (TASK-29 behaviour)
```

Test the upgrade path too:

```bash
brew update
brew upgrade scratchpad   # no-op when already at latest
```

---

## Subsequent releases (the lightweight loop)

Once the tap exists, every release follows this rhythm:

1. Tag + build + publish the release in the scratchpad repo (steps in
   [`release-runbook.md`](../release-runbook.md)).
2. Edit `Casks/scratchpad.rb` in the tap repo:
   - Bump `version` to the new tag (without the leading `v`).
   - Replace `sha256` with the value printed by `build-tarball.sh`.
3. `git commit -m "Scratchpad vX.Y.Z" && git push` in the tap repo.

That's the entire release loop for the brew install path. The curl |
bash installer (TASK-34) requires zero changes per release — it
resolves the latest tag via GitHub's `/releases/latest/download/`
redirect.

---

## Renaming the tap to live under a different GitHub org

If you ever move the canonical repo:

1. Update `homepage` and `url` in the Cask (the `aaronmyatt` slug).
2. Update the install one-liner in:
   - the scratchpad repo's `README.md`
   - `docs/install/brew.md`
   - `backlog/docs/install/brew.md` (this is the source for the docs
     site mirror)
3. Tell users on the next release notes; previous tap installs keep
   working as long as the old repo still exists.

---

## References

- Homebrew Cask Cookbook: https://docs.brew.sh/Cask-Cookbook
- Creating and maintaining a tap: https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap
- decision-3 (why Scratchpad is unsigned + how brew bypasses Gatekeeper anyway):
  [`backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md`](../../decisions/decision-3%20-%20Skip-Apple-notarization-for-v1.md)

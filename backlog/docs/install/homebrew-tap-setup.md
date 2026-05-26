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
empty — `scripts/release.sh` populates the Cask file from a template
the first time it runs.

### Local clone layout

We clone the tap *inside* the scratchpad repo at `./tap` (gitignored).
This keeps the tap clone next to `scripts/release.sh` that operates on
it, without the two repos' git histories interfering. The convention
is just "where contributors expect to find it" — nothing structural
depends on the path, and `SCRATCHPAD_TAP_DIR` overrides it.

```bash
# From the root of the scratchpad checkout:
git clone git@github.com:aaronmyatt/homebrew-scratchpad.git tap
```

That's the whole bootstrap. The first `./scripts/release.sh vX.Y.Z`
run renders `tap/Casks/scratchpad.rb` from
[`scripts/scratchpad.cask.rb.template`](../../../scripts/scratchpad.cask.rb.template),
commits it to the tap, and pushes — no hand-copy step needed.

Why a separate GitHub repo (even though the local clone is nested):
Homebrew's auto-tap convention is hardcoded to look for
`github.com/<user>/homebrew-<name>` when you `brew tap user/name`.
There's no way to point it at a subfolder of another repo, no way to
use a non-`homebrew-` prefix. The tap repo can stay tiny — just the
generated Cask formula and a README.

---

## 2. Cut the first release

One command does everything: tags, builds, publishes the GitHub
Release, *and* populates the tap from the Cask template.

```bash
./scripts/release.sh v0.1.0
```

The script's step 6 renders
[`scripts/scratchpad.cask.rb.template`](../../../scripts/scratchpad.cask.rb.template)
into your nested `tap/Casks/scratchpad.rb`, commits, and pushes to the
homebrew-scratchpad repo. First-run output includes the full additive
diff for the newly-created Cask file — review it, confirm, done.

See [`release-runbook.md`](../release-runbook.md) for the full
breakdown of what each step does, or run with `--dry-run` first to
preview without executing.

---

## 3. The Cask formula (template + render)

The Cask's canonical source lives in *this* repo at
[`scripts/scratchpad.cask.rb.template`](../../../scripts/scratchpad.cask.rb.template),
not in the tap. `scripts/release.sh` renders the template into
`tap/Casks/scratchpad.rb` on every release, substituting two
placeholders:

- `{{VERSION}}` → the bare semver (e.g. `0.1.0`)
- `{{SHA256}}` → the sha256 of the published `Scratchpad-arm64.tar.gz`

Why a template-render rather than editing the tap's Cask in place:

- **No bootstrap step** — an empty tap clone is a valid starting state.
  Step 1's `git clone` is everything you need before running
  `release.sh`.
- **No fragile sed regex** — the placeholders are unique strings,
  resistant to formatting changes that would break an in-place
  `version "..."` / `sha256 "..."` rewrite.
- **Single source of truth** — formula structure lives version-
  controlled alongside the rest of the project. The tap is downstream;
  hand-edits to the tap's Cask get overwritten on the next release
  (intentionally — change the template, not the rendered output).

To evolve the formula (add stanzas, change URL pattern, adjust zap
targets), edit the template. The next release picks up the change.

---

## 4. Verify on a clean install

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

Once the tap exists, every release is a single command:

```bash
./scripts/release.sh vX.Y.Z
```

The script handles the tap bump in step 6 (see
[`release-runbook.md`](../release-runbook.md) for the full breakdown):
it `git pull --ff-only`s the tap, sed-rewrites the `version` and
`sha256` lines in `tap/Casks/scratchpad.rb`, shows the diff, and
commits + pushes — all without leaving the scratchpad checkout.

The curl | bash installer (TASK-34) requires zero changes per release
— it resolves the latest tag via GitHub's `/releases/latest/download/`
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

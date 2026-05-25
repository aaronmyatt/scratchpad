---
id: doc-2
title: Release runbook
created_date: 2026-05-25
---

# Release runbook

How to cut a Scratchpad release end-to-end. Owned by TASK-34; updated by
TASK-32 (Cask bump step) and TASK-39 (preflight regression checks) as
those land.

Per [decision-3](../decisions/decision-3 - Skip-Apple-notarization-for-v1.md)
v1 is **unsigned**. There is no notarization step, no Apple Developer
Program enrolment, no Gatekeeper staple. Both the Homebrew Cask path
(TASK-32) and the curl|bash installer (`install.sh`) consume the same
release artifact — so cutting a release is a single tarball-build cycle.

---

## 0. Pre-flight (will become automated by TASK-39)

Until TASK-39 ships a `scripts/preflight-release.sh`, run these by hand:

```bash
# Test suite is green
swift test

# Build pipeline is healthy (these are idempotent)
./scripts/build-app.sh
./scripts/build-tarball.sh
./scripts/build-dmg.sh

# Smoke-test install.sh against the local artifact before publishing
SCRATCHPAD_TARBALL_URL="file://$(pwd)/build/Scratchpad-arm64.tar.gz" \
  SCRATCHPAD_INSTALL_DIR="$(mktemp -d)" \
  ./install.sh
```

If any of the above is red, fix it before tagging — a bad tag is much
more annoying to retract than to never push.

---

## 1. Tag the commit

The build scripts pull the version from `git describe --tags --always`, so
tagging is what actually sets the version embedded in `Info.plist`.

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

Choose the version per [semver](https://semver.org/):
- v0.x.y while we're pre-1.0; bump y for fixes, x for features.
- v1.0.0 when the docs site (TASK-36) is live and the install paths are
  exercised by external users.

---

## 2. Build the artifacts

Both scripts are idempotent — running them in a clean checkout produces
the same files. They live under `build/`, gitignored.

```bash
./scripts/build-tarball.sh    # produces Scratchpad-arm64.tar.gz + .sha256
./scripts/build-dmg.sh        # produces Scratchpad.dmg
```

Note the sha256 it prints — you'll paste it into the Cask formula
(step 4). Sample output:

```
==> Built build/Scratchpad-arm64.tar.gz (164K)
    sha256: 5a16f013c14c5f3ace7bb11fd69248bb3ce55ef152f346e5233e023bb6ea3b3c

    Paste into Cask (TASK-32):
      sha256 "5a16f013c14c5f3ace7bb11fd69248bb3ce55ef152f346e5233e023bb6ea3b3c"
```

---

## 3. Publish the GitHub Release

`install.sh` resolves the `latest` tag via the GitHub
`/releases/latest/download/<asset>` redirect, so the `latest` label has
to point at the right release. `gh release create` sets it
automatically.

```bash
gh release create v0.1.0 \
    build/Scratchpad-arm64.tar.gz \
    build/Scratchpad-arm64.tar.gz.sha256 \
    build/Scratchpad.dmg \
    --title "v0.1.0" \
    --notes-file CHANGELOG.md   # or --generate-notes
```

Verify the auto-redirect works before announcing the release:

```bash
# Should HTTP-302 to https://.../releases/download/v0.1.0/Scratchpad-arm64.tar.gz
curl -sI https://github.com/aaronmyatt/scratchpad/releases/latest/download/Scratchpad-arm64.tar.gz \
    | head -3
```

Refs:
- `gh release create`: https://cli.github.com/manual/gh_release_create
- GitHub Release linking: https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases

---

## 4. Bump the Homebrew Cask

First-time setup of the tap repo is documented in
[`install/homebrew-tap-setup.md`](install/homebrew-tap-setup.md) — do
that once before the first release. The per-release loop below assumes
the tap already exists.

In the separate `aaronmyatt/homebrew-scratchpad` repo, edit
`Casks/scratchpad.rb`:

```bash
cd /path/to/homebrew-scratchpad
```

Two lines to change in `Casks/scratchpad.rb`:

```ruby
  version "0.1.0"          # → bump to the new tag (without leading "v")
  sha256  "5a16f013…"      # → paste the value `scripts/build-tarball.sh` printed
```

Commit + push:

```bash
git commit -am "Scratchpad vX.Y.Z"
git push
```

Smoke-test on the host you cut the release on:

```bash
brew update
brew upgrade scratchpad      # no-op if already at latest
xattr -p com.apple.quarantine /Applications/Scratchpad.app 2>&1 | head -1
# → "No such xattr: com.apple.quarantine"  (brew stripped it)
```

A cleaner smoke test is on a fresh user account or VM
([TASK-40 tart workflow](vm-testing.md)) where there's no prior install
to mask issues.

---

## 5. install.sh

By default `install.sh` already resolves the `latest` tag, so step 3 is
enough — no edit to `install.sh` itself is required for a typical release.

If you want a release where the one-liner pins a specific version (e.g.
for a runbook, blog post, or CI), users can set the env var:

```bash
SCRATCHPAD_VERSION=v0.1.0 \
  curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | bash
```

The default `SCRATCHPAD_VERSION=latest` keeps the one-liner short for the
README + docs site.

---

## 6. Sanity test on a clean account

The most reliable way to catch installer regressions is a clean macOS
user account. The shorter version:

```bash
# Wipe a previous install + UserDefaults
rm -rf /Applications/Scratchpad.app ~/Applications/Scratchpad.app
defaults delete com.aaronmyatt.scratchpad 2>/dev/null || true

# Run the published one-liner exactly as a new user would
curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | bash

# Verify
open /Applications/Scratchpad.app   # menu-bar icon should appear; PathInstaller prompt
echo "hello" | sp                   # should display in the Scratchpad window
```

Any prompt about "Apple cannot check this app" means quarantine got set
somehow — usually a corporate proxy or a curl version that adds the
attribute. `install.sh` already strips it defensively, so this should
not happen in practice.

---

## Open items (links to where they'll land)

- **Automated preflight** — TASK-39 will replace step 0 with a single
  `scripts/preflight-release.sh`.
- **Universal binary** — Intel support requires a `lipo`-merged
  `Scratchpad-universal.tar.gz`; `install.sh` already plumbs `ARCH_TAG`
  through so this is a build-script change, not an installer change.

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

## TL;DR — the one-liner

99% of releases:

```bash
./scripts/release.sh v0.1.0
```

The script walks every step below in sequence: preflight → tag + push →
build → publish GitHub Release → verify the `/latest/` redirect → bump
the homebrew tap. Every step is idempotent — re-run after any failure
and it picks up where it left off. Add `--dry-run` to print the planned
steps without executing, or `--yes` to skip the confirmation prompts
(intended for CI).

Tap repo location: defaults to `./tap` (a gitignored nested clone of
`aaronmyatt/homebrew-scratchpad` inside this repo). Bootstrap once with:

```bash
git clone git@github.com:aaronmyatt/homebrew-scratchpad.git tap
```

Override the path via `SCRATCHPAD_TAP_DIR=/path/to/tap` if you keep the
clone elsewhere.

The manual steps below are kept as reference for understanding what the
script does, and as a fallback when something genuinely needs a one-off.

---

## 0. Pre-flight

Single command, runs every release-blocking check from a clean state:

```bash
./scripts/preflight-release.sh
```

The script chains:

1. `rm -rf build/` (test from zero state)
2. `swift test` (pure-logic regressions)
3. `bats Tests/install.bats` (install-hygiene regression guards — bundle
   sealing, quarantine strip, Cask template integrity)
4. `scripts/build-app.sh`
5. `scripts/build-tarball.sh`
6. `scripts/build-dmg.sh`
7. tarball sha256 round-trip (`shasum -c`)
8. DMG mount + detach via `hdiutil` (catches corrupt DMG before publish)
9. `shellcheck scripts/*.sh install.sh`

Failure at any step prints the regressed step name and the underlying
tool's stderr; exit code is non-zero so CI/scripts can chain it. No
interactive prompts. No skip flag — if you genuinely need to bypass a
step, comment it out locally and own the regression.

**Prereqs** (one-time): `brew install bats-core shellcheck`. The full
suite takes ~60–90 s on a warm cache (dominated by the two `swift build
-c release` cycles inside steps 3 and 4).

### Fallback — running individual steps by hand

When you need to debug a specific failure, the underlying commands are
all callable independently:

```bash
swift test
bats Tests/install.bats
./scripts/build-app.sh
./scripts/build-tarball.sh
./scripts/build-dmg.sh

# Manual smoke-test of install.sh against the local artifact
SCRATCHPAD_TARBALL_URL="file://$(pwd)/build/Scratchpad-arm64.tar.gz" \
  SCRATCHPAD_INSTALL_DIR="$(mktemp -d)" \
  ./install.sh
```

A bad tag is much more annoying to retract than to never push — fix any
red here before tagging.

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

In the tap repo clone (conventionally at `./tap` inside the scratchpad
checkout):

```bash
cd tap   # or wherever your SCRATCHPAD_TAP_DIR points
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

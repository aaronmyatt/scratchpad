---
id: doc-6
title: Install via Homebrew (canonical source)
created_date: 2026-05-25
---

# Install via Homebrew

> Canonical source for the README's brew install snippet and the docs
> site's [`/install/brew`](https://aaronmyatt.github.io/scratchpad/install/brew)
> page. Keep these three in sync.

## One-liner

```bash
brew install aaronmyatt/scratchpad/scratchpad
```

Or explicitly (does the same thing — just shows you what brew does
under the hood):

```bash
brew tap aaronmyatt/scratchpad
brew install scratchpad
```

## What this does

1. Adds the `aaronmyatt/scratchpad` tap — a tiny GitHub repo
   ([`github.com/aaronmyatt/homebrew-scratchpad`](https://github.com/aaronmyatt/homebrew-scratchpad))
   that contains nothing but the Cask formula pointing at the latest
   release artifact.
2. Downloads the latest `Scratchpad-arm64.tar.gz` from
   [`github.com/aaronmyatt/scratchpad/releases/latest`](https://github.com/aaronmyatt/scratchpad/releases/latest).
3. Verifies the sha256 against the value pinned in the Cask formula.
4. Extracts `Scratchpad.app` into `/Applications`.
5. **Strips the `com.apple.quarantine` extended attribute** — this is
   the standard brew install behaviour and what makes the app launch
   with no Gatekeeper prompt.

## Updating

```bash
brew update
brew upgrade scratchpad
```

## Uninstalling

```bash
brew uninstall scratchpad

# Also removes UserDefaults via the Cask's `zap` stanza:
brew uninstall --zap scratchpad
```

The `--zap` form additionally removes:

- `~/Library/Preferences/com.aaronmyatt.scratchpad.plist` — your saved
  preferences (notably the PathInstaller "didPrompt" flag, so a
  reinstall re-offers to install `sp` on PATH).
- `~/Library/Application Support/Scratchpad/` — the input-bar command
  history.

If you ever installed `sp` on PATH manually, the symlink survives the
uninstall — remove it yourself if you no longer want it:

```bash
rm -f /usr/local/bin/sp ~/bin/sp
```

## After install

On first launch, Scratchpad offers to install the small `sp` CLI on
your PATH so you can pipe text from any terminal:

```bash
echo "hello" | sp
```

Accept the prompt — by default it installs to `/usr/local/bin/sp` (or
`~/bin/sp` if `/usr/local/bin` isn't writable, with PATH guidance).

## Why brew is the friction-free path

Homebrew downloads release artifacts via curl (not via a browser), so
the `com.apple.quarantine` extended attribute that triggers Gatekeeper
never gets attached. Plus, brew explicitly strips the attribute on
install as belt-and-braces.

The [direct DMG download path](direct-download.md) hits Gatekeeper
because browsers *do* attach the attribute — workarounds are
documented there for users who prefer the visual install experience.

See
[`decision-3`](../../decisions/decision-3%20-%20Skip-Apple-notarization-for-v1.md)
for the full distribution-strategy rationale.

## Setting up the tap (maintainer reference)

If you're a maintainer cutting a new release or bootstrapping the tap
repo: see [`homebrew-tap-setup.md`](homebrew-tap-setup.md) for the
end-to-end setup + per-release loop.

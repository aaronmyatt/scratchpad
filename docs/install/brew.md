---
layout: default
title: Install via Homebrew
description: Install Scratchpad via the aaronmyatt/scratchpad tap.
---

> **Status:** Cask formula is written and ready; tap repo goes live
> alongside the first GitHub Release (v0.1.0). Until then, use
> [curl | bash]({{ '/install/curl' | relative_url }}) or the
> [direct download]({{ '/install/direct' | relative_url }}).

## One-liner

```bash
brew install aaronmyatt/scratchpad/scratchpad
```

Or explicitly:

```bash
brew tap aaronmyatt/scratchpad
brew install scratchpad
```

## What this does

1. Adds the `aaronmyatt/scratchpad` tap (a third-party Homebrew repo).
2. Downloads the latest `Scratchpad-arm64.tar.gz` release artifact from
   [github.com/aaronmyatt/scratchpad/releases](https://github.com/aaronmyatt/scratchpad/releases/latest).
3. Verifies the sha256 against the value pinned in the Cask formula.
4. Extracts `Scratchpad.app` into `/Applications`.
5. Strips the `com.apple.quarantine` extended attribute as part of brew's
   standard install flow — so the app launches with no Gatekeeper prompt.

## Updating

```bash
brew update
brew upgrade scratchpad
```

## Uninstalling

```bash
brew uninstall scratchpad
brew untap aaronmyatt/scratchpad   # optional
```

## After install

On first launch, Scratchpad offers to install the small `sp` CLI on your
PATH so you can pipe text from any terminal:

```bash
echo "hello" | sp
```

Accept the prompt — by default it installs to `/usr/local/bin/sp` (or
`~/bin/sp` if `/usr/local/bin` isn't writable, with PATH guidance).

---

## Why brew is the friction-free path

Homebrew downloads release artifacts via curl (not via a browser), so the
`com.apple.quarantine` extended attribute that triggers Gatekeeper never
gets attached. Plus, our Cask explicitly strips the attribute on install
via a `postflight` block — brew Cask doesn't do this by default since
~2020, so the formula carries the strip itself.

The
[direct DMG download path]({{ '/install/direct' | relative_url }})
hits Gatekeeper because browsers do attach the attribute — workarounds are
documented there for users who prefer the visual install experience.

See
[decision-3](https://github.com/aaronmyatt/scratchpad/blob/main/backlog/decisions/decision-3%20-%20Skip-Apple-notarization-for-v1.md)
for the full distribution-strategy rationale (why Scratchpad isn't
notarized for v1 and why brew/curl bypass that gracefully).

---
layout: default
title: Install via curl
description: One-line install via curl | bash. Verifies sha256 before extracting.
---

## One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | bash
```

That's it — `Scratchpad.app` lands in `/Applications` (or `~/Applications`
if `/Applications` isn't writable), with no Gatekeeper prompt on first
launch.

## Inspect first

If you're (rightly) cautious about `curl … | bash` patterns, read it first:

```bash
curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | less
```

Or just open
[install.sh](https://github.com/aaronmyatt/scratchpad/blob/main/install.sh)
on GitHub.

## What the script does

1. Refuses to run on anything but Apple Silicon macOS (decision-1).
2. Fetches the latest `Scratchpad-arm64.tar.gz` + `.sha256` sidecar from
   the latest GitHub Release.
3. Verifies the checksum. **Aborts with exit 1 if the tarball is tampered
   or corrupt** — never extracts a mismatched file.
4. Extracts into `/Applications` if writable, otherwise creates and uses
   `~/Applications`. Never uses `sudo`.
5. Defensively strips `com.apple.quarantine` — curl doesn't set it in the
   first place, but a corporate proxy or future curl version could. Costs
   microseconds, saves a footgun.
6. Prints a "next steps" panel pointing you at the first-launch
   PathInstaller prompt for the `sp` CLI.

## Environment overrides

For advanced users, CI, or testing:

| Variable | Default | Purpose |
|---|---|---|
| `SCRATCHPAD_VERSION` | `latest` | Pin a specific release tag, e.g. `v0.1.0`, for reproducible installs. |
| `SCRATCHPAD_INSTALL_DIR` | `/Applications` or `~/Applications` | Override the install target dir entirely. |
| `SCRATCHPAD_TARBALL_URL` | (computed) | Override the tarball URL — primarily used to test the installer against a `file://` local artifact before publishing a release. |
| `SCRATCHPAD_REPO` | `aaronmyatt/scratchpad` | Override the GitHub repo (forks). |

Example: pin to a specific version in a CI lockfile.

```bash
SCRATCHPAD_VERSION=v0.1.0 \
  curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | bash
```

## Why curl is the friction-free path

Unlike browsers, `curl` doesn't attach the `com.apple.quarantine` extended
attribute to downloaded files. The same trick is how Homebrew itself,
rustup, deno, and bun all install on macOS — well-understood and
universally relied upon.

The [direct DMG download path]({{ '/install/direct' | relative_url }})
*does* hit Gatekeeper because browsers attach the attribute; workarounds
are documented there if you prefer the visual install experience.

See
[decision-3](https://github.com/aaronmyatt/scratchpad/blob/main/backlog/decisions/decision-3%20-%20Skip-Apple-notarization-for-v1.md)
for the full distribution-strategy rationale.

## Updating

Re-run the same one-liner. The script replaces the existing
`Scratchpad.app` in place. If Scratchpad was running during the upgrade,
quit and relaunch it to pick up the new build (macOS keeps the old binary
mapped in any process that's already running).

## Uninstalling

```bash
rm -rf /Applications/Scratchpad.app ~/Applications/Scratchpad.app
defaults delete com.aaronmyatt.scratchpad 2>/dev/null  # forget PathInstaller flag
rm -f /usr/local/bin/sp ~/bin/sp                       # remove the sp symlink
```

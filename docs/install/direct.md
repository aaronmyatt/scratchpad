---
layout: default
title: Direct DMG download
description: Download the DMG and work around the Gatekeeper prompt.
---

> **Prefer [brew]({{ '/install/brew' | relative_url }}) or
> [curl]({{ '/install/curl' | relative_url }}) if you can** — both bypass
> Gatekeeper entirely and produce the same app.

## Download flow

1. Open the
   [latest GitHub Release](https://github.com/aaronmyatt/scratchpad/releases/latest).
2. Download `Scratchpad.dmg`.
3. Double-click the DMG to mount it.
4. Drag `Scratchpad.app` into `/Applications`.
5. Double-click `Scratchpad` in `/Applications`. On first launch,
   Gatekeeper will block it — see workarounds below.

## Gatekeeper workaround (one of three)

### macOS 14 (Sonoma): right-click → Open

The friendliest path. Right-click `Scratchpad` in `/Applications`, choose
**Open**, then confirm in the dialog. macOS remembers the exemption;
subsequent launches don't prompt.

### macOS 15+ (Sequoia): System Settings → Open Anyway

Apple removed the right-click → Open shortcut for unsigned apps in
Sequoia. Replacement flow:

1. Double-click `Scratchpad` in `/Applications`. You'll see
   *"Scratchpad Not Opened"*.
2. Open **System Settings**.
3. Navigate to **Privacy & Security**.
4. Scroll down to the **Security** subsection — there'll be a note saying
   *"Scratchpad was blocked from use because it is not from an identified
   developer."*
5. Click **"Open Anyway"**. macOS may prompt for your admin password.

![Sequoia 'Open Anyway' button in System Settings]({{ '/assets/screenshots/gatekeeper-sequoia.png' | relative_url }})

### Terminal: strip the quarantine flag yourself

Fastest path for anyone comfortable with a terminal. This is exactly what
Homebrew does for you on the brew path — no magic, no extra risk:

```bash
xattr -dr com.apple.quarantine /Applications/Scratchpad.app
```

After this, the app launches normally with no further prompts.

## Why this happens

macOS attaches `com.apple.quarantine` to anything a browser downloads.
Gatekeeper checks that attribute on first launch and blocks unsigned
software from the internet by default — sensible behaviour.

The brew and curl install paths avoid the warning not by bypassing the
security check but by using a download mechanism that doesn't set the
quarantine flag in the first place. Exactly how rustup, deno, bun, and
Homebrew itself install on macOS.

See
[decision-3](https://github.com/aaronmyatt/scratchpad/blob/main/backlog/decisions/decision-3%20-%20Skip-Apple-notarization-for-v1.md)
for the full distribution-strategy rationale (and why v1 doesn't sign +
notarize).

## After install

On first launch, Scratchpad offers to install a small `sp` CLI shortcut
so you can pipe text into the app from any terminal:

```bash
echo "hello" | sp
```

Accept the prompt to add `sp` to `/usr/local/bin` (or `~/bin` if the
former isn't writable). You can decline and install it manually later via:

```bash
ln -s /Applications/Scratchpad.app/Contents/MacOS/sp /usr/local/bin/sp
```

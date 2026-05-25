---
id: doc-3
title: Direct download install (DMG + Gatekeeper workaround)
created_date: 2026-05-25
---

# Direct download install

> Source of truth for the README's "Direct download" section and the
> matching page on the GitHub Pages site (TASK-36). Keep this file and
> the README section in sync.

Three install paths exist for Scratchpad (see
[decision-3](../../decisions/decision-3 - Skip-Apple-notarization-for-v1.md)
for the distribution-strategy rationale):

1. **Homebrew tap** — `brew install aaronmyatt/scratchpad/scratchpad` (TASK-32)
2. **curl | bash** — `curl -fsSL …/install.sh | bash` (TASK-34, shipped)
3. **Direct download** — the topic of this doc

The first two paths bypass Gatekeeper entirely; the third does not.

---

## Prefer brew or curl when possible

Scratchpad is **unsigned** for v1 (no Apple Developer Program enrolment, no
notarization). The Homebrew and curl paths both produce a launchable app
with no Gatekeeper warning because:

- **Homebrew** strips the `com.apple.quarantine` extended attribute after
  download as part of its standard install flow.
- **curl** never sets `com.apple.quarantine` in the first place — only
  browsers (and a handful of sandboxed download tools) do. `install.sh`
  also runs a defensive `xattr -dr` post-extract.

If you have either tool installed, prefer them. The direct-download path
below exists for users who can't or won't use a CLI installer.

---

## Direct download flow

1. Open
   [the latest GitHub Release](https://github.com/aaronmyatt/scratchpad/releases/latest).
2. Download `Scratchpad.dmg`.
3. Double-click the DMG to mount it.
4. Drag `Scratchpad.app` into `/Applications`.
5. Double-click `Scratchpad` in `/Applications`. On first launch, Gatekeeper
   will block it (see workarounds below).

---

## Gatekeeper workaround (one of three, pick whichever you trust)

### macOS 14 (Sonoma): right-click → Open

The friendliest path. Right-click `Scratchpad` in `/Applications`, choose
**Open**, then confirm in the dialog that appears. macOS remembers the
exemption; subsequent launches don't prompt.

### macOS 15+ (Sequoia): System Settings → Open Anyway

Apple removed the right-click → Open shortcut for unsigned apps in
Sequoia. The replacement flow:

1. Double-click `Scratchpad` in `/Applications`. You'll see *"Scratchpad
   Not Opened"* or similar.
2. Open **System Settings**.
3. Navigate to **Privacy & Security**.
4. Scroll down to the **Security** subsection — there'll be a note saying
   *"Scratchpad was blocked from use because it is not from an identified
   developer."*
5. Click **"Open Anyway"** next to that note. macOS may prompt for your
   admin password.

### Terminal: strip the quarantine flag manually

The fastest path for anyone comfortable with a terminal. This is exactly
what Homebrew does for you on the brew install path — no magic, no extra
risk:

```bash
xattr -dr com.apple.quarantine /Applications/Scratchpad.app
```

After this, the app launches normally with no further prompts.

References:
- `xattr(1)` on macOS: https://ss64.com/mac/xattr.html
- Gatekeeper changes in Sequoia (background reading on why the right-click
  trick was removed): https://eclecticlight.co/2024/06/16/gatekeeper-changes-in-sequoia/

---

## Why the warning happens

macOS attaches the `com.apple.quarantine` extended attribute to anything a
browser downloads. On first launch, Gatekeeper looks at that attribute and
checks whether the binary is signed and notarized by Apple. Scratchpad is
neither for v1, so Gatekeeper blocks it.

This is sensible default behaviour for unsigned software from the internet.
The Homebrew and curl install paths avoid it not by bypassing the security
check but by using a download mechanism that doesn't set the quarantine
flag in the first place — exactly how rustup, deno, bun, and Homebrew
itself install on macOS.

See the
[full background on quarantine attributes](https://eclecticlight.co/2024/10/24/the-life-and-death-of-quarantine-attributes/)
if you want the deeper dive.

---

## After install

On first launch, Scratchpad offers to install a small `sp` CLI shortcut so
you can pipe text into the app from any terminal:

```bash
echo "hello" | sp
```

Accept the prompt to add `sp` to `/usr/local/bin` (or `~/bin` if the former
isn't writable). You can decline and install it manually later via:

```bash
ln -s /Applications/Scratchpad.app/Contents/MacOS/sp /usr/local/bin/sp
```

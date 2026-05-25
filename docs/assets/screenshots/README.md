# Screenshots — shopping list

> These are referenced by the docs site at `/docs/index.md`,
> `/docs/install/direct.md`, `/docs/use/quickstart.md`. Drop PNGs into
> this directory matching the filenames below.
>
> Recommended capture sizes: **2x retina** (e.g. 2400 × 1500 logical px),
> PNG, optionally optimised via `pngquant` or `oxipng`. The CSS
> follow-up tasks will add `max-width` + dark-mode handling — for now,
> ship plain PNGs and the markdown renders them at natural width inside
> cayman's content column.
>
> Source files (originals at full res, .sketch / .figma / `.app`
> screen-recorded) live in `_originals/` and are gitignored — don't
> commit them.

## Hero — `hero.png`
Scratchpad window receiving a real-looking JSON dump (something
realistic like an HTTP request log or a stripped-down API payload).
Window is the pinned/floating size we ship by default. Menu bar visible
at top of frame to convey "menu-bar-resident" identity. Avoid showing
any sensitive paths in the menu bar.

## Input bar — `input-bar.png`
Same window as the hero, but with the bottom `$ ` input bar focused and
a command like `jq .data.users[]` partially typed (or just executed —
either reads). The displayed area should clearly show pretty-printed
JSON output. Demonstrates the "pipe-the-dump-through-shell" identity.

## History search — `history-search.png`
The Ctrl-R history overlay open over the input bar, with a search
string and 2-3 matching previous commands visible. Optional but useful.

## Menu bar — `menu-bar.png`
Tight close-up of just the menu bar showing the Scratchpad icon, with
the right-click menu open (Show / Hide / Quit items visible). 1:1 retina
ideal so the icon stays crisp at native size.

## Gatekeeper Sequoia — `gatekeeper-sequoia.png`
The "Open Anyway" button in System Settings → Privacy & Security after
double-clicking the unsigned app on macOS 15. Only used on the direct-
download install page; can ship a placeholder until someone tests the
DMG path on a clean Sequoia VM (TASK-40).

---

## Capture tips

- Hide personal items from the menu bar before screenshotting (icons
  rearrange in System Settings → Control Center).
- For window-only shots, use `Cmd-Shift-4` then space to capture a
  single window with macOS's drop shadow.
- For full-frame shots that include the menu bar, use `Cmd-Shift-5`
  → Capture Entire Screen and crop after.
- Run Scratchpad in light mode for the v1 assets; dark-mode assets land
  with the dark-mode CSS task.

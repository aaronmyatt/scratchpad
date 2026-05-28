---
id: TASK-52
title: >-
  Clipboard hand-off confirmation feedback — adjacent affordance label + banner
  notification
status: Done
assignee:
  - '@aaron'
created_date: '2026-05-27 05:49'
updated_date: '2026-05-27 06:04'
labels:
  - retroactive
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - >-
    backlog/tasks/task-44 -
    Input-bar-Cmd-Enter-spawns-users-SHELL-in-a-real-terminal.md
  - backlog/tasks/task-50 - Two-row-live-invocation-preview-in-the-input-bar.md
  - >-
    backlog/tasks/task-51 -
    Pivot-⌘↩-from-spawn-a-terminal-to-clipboard-hand-off.md
modified_files:
  - Sources/Scratchpad/ContentView.swift
priority: medium
ordinal: 31.25
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retroactive ticket capturing the final UI feedback pass on the ⌘↩ clipboard hand-off.

## Motivation

After TASK-51 landed (⌘↩ now copies to clipboard), two issues surfaced from direct UX review:

1. **Discoverability:** the `→ clipboard` affordance label sat at the far right end of the preview row, separated from the `⌘↩` glyph by the body text. Reading it required eye-tracking from the prefix all the way across the row — not at-a-glance comprehension.

2. **Confirmation:** when the user hit ⌘↩, the only feedback was a quiet text swap from `→ clipboard` → `Copied!` in tertiary colour. Easy to miss. The user explicitly asked: "Can we notify the user in some way?"

This ticket addresses both.

## Behaviour

### Layout: bring the affordance label adjacent to the prefix

`previewRow` was restructured so `trailing` renders immediately after `prefix`, with the body following. The ⌘↩ row now reads as a unit:

```
↩    ‹dump› | wc -c
⌘↩   → clipboard    wc -c ‹dump-file›
```

`trailing` got a `minWidth: 80` so the body text columns of the two rows still line up roughly. Trailing colour bumped from `.tertiary` to `.secondary` so the affordance is more legible without being shouty.

### Notification: confirmation banner

A new `handoffBanner` view sits between the display area's divider and the `searchOverlay` / `inputBar`. When ⌘↩ fires, it slides in showing the *actual* copied line:

```
✓ Copied to clipboard: vim '/var/folders/9k/.../scratchpad-dump-...'
```

- Background: `Color.accentColor.opacity(0.12)`.
- Bottom accent rule: 1px `Color.accentColor.opacity(0.4)`.
- Checkmark icon: SF Symbol `checkmark.circle.fill`, accent-tinted.
- Truncation: middle-truncation on the command body so long paths don't break layout.
- Transition: `.opacity.combined(with: .move(edge: .bottom))`.
- Lifetime: 2s visible, then fades out.

In parallel, the inline `→ clipboard` row label swaps to `✓ Copied!` in `Color.accentColor` for the same window, giving the user two simultaneous indicators in different parts of the window.

Animation: `withAnimation(.easeOut(duration: 0.18))` for show, `.easeIn(duration: 0.25)` for hide.

## Refs

- TASK-44 (umbrella)
- TASK-50 (preview rows the affordance label lives on)
- TASK-51 (clipboard hand-off this confirms)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The '→ clipboard' affordance label renders immediately to the right of the '⌘↩' prefix, not at the far end of the preview row
- [ ] #2 Pre-flash trailing colour is .secondary (more legible than the prior .tertiary)
- [ ] #3 On ⌘↩: the inline label swaps to '✓ Copied!' in the system accent colour for ~1.5s
- [ ] #4 On ⌘↩: a confirmation banner slides in above the input bar showing '✓ Copied to clipboard: <copied-line>'
- [ ] #5 Banner uses accent-tinted background + 1px accent bottom rule for visual distinction without being shouty
- [ ] #6 Banner shows the actual resolved command (including the temp-file path) so the user can verify what got copied — especially valuable for empty-input ⌘↩ where only the bare path lands on the clipboard
- [ ] #7 Banner truncates the command body with middle-ellipsis so long paths don't break layout
- [ ] #8 Banner uses an opacity + move-from-bottom SwiftUI transition with `withAnimation` for a soft fade in/out
- [ ] #9 Banner auto-dismisses after ~2s; the inline label flash uses ~1.5s (slight stagger feels intentional, not buggy)
- [ ] #10 Banner display does NOT shift any other UI — displayArea above and input bar below stay anchored
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## What was built

### Layout fix
`previewRow(prefix:body:trailing:trailingColor:)` was restructured so the trailing affordance renders adjacent to the prefix instead of at the far right. The `trailingColor` parameter (new) lets the call site swap to `.accentColor` during the post-copy flash. Pre-flash colour bumped from `.tertiary` → `.secondary` for legibility.

### Notification banner
New `handoffBanner` ViewBuilder + `@State private var lastCopiedCommand: String?` in `ContentView`. When non-nil, the banner renders between the display divider and the input bar; when nil, it conditionally compiles to nothing. The transition `.opacity.combined(with: .move(edge: .bottom))` gives a slide-up entrance and matching fade-out exit.

`copyCommandToClipboard()` was updated to set both `handoffFlash = true` and `lastCopiedCommand = clipboardLine` inside a `withAnimation`, then schedule a 2s sleep that clears both within another `withAnimation`.

## Why it matters

Direct response to user feedback ("It needs to be more obvious to the user what happens once ⌘-enter is hit. Can we notify the user in some way?"). The combination of:

1. Affordance label visible at-a-glance before pressing.
2. Inline label flash on press.
3. Banner with the actual copied content on press.

…makes the hand-off impossible to miss. The banner specifically surfaces the *resolved* command (including the temp-file path), which is the only place the user can confirm the right thing got copied — particularly important for empty-input ⌘↩ where the clipboard contents are otherwise invisible until they paste somewhere.

## Test coverage

This ticket is pure-view changes; no logic to test. The underlying `ClipboardHandoff` module (covered by TASK-51's 21 tests) is the source of truth for what lands on the clipboard. Manual verification: `swift run Scratchpad`, send a dump, focus the input bar, hit ⌘↩ — banner appears, label flashes, both auto-dismiss after ~2s.

Full project suite remained 35/35 green after this pass.
<!-- SECTION:FINAL_SUMMARY:END -->

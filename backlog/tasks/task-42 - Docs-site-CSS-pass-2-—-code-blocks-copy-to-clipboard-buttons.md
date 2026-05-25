---
id: TASK-42
title: Docs site CSS pass 2 — code blocks + copy-to-clipboard buttons
status: To Do
assignee: []
created_date: '2026-05-25 12:38'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-41
priority: medium
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second CSS iteration: make the docs site's many code blocks first-class citizens.

**1. Rouge syntax highlighting palette**
- Cayman ships a serviceable default but it's a bit washed out and doesn't match the Scratchpad palette (TASK-41 sets that).
- Pick a Rouge theme that matches — `monokai`, `github`, `solarized-dark`, etc. — or write a small custom one. Generate with `rougify style <theme> > docs/assets/css/syntax.scss` and `@import` from `style.scss`.

**2. Click-to-copy buttons on `<pre>` blocks**
- Every code block (especially the install one-liners) gets a small "Copy" button in the top-right corner that copies the block's text to clipboard.
- Tiny vanilla JS — no Clipboard.js dependency. The Web Clipboard API (`navigator.clipboard.writeText`) handles 99% of cases.
- Show "Copied!" state for ~1.5s on success; fall back to `document.execCommand('copy')` for old Safari if we care (probably skip — Pages users self-select for modern browsers).
- Script lives at `docs/assets/js/copy-buttons.js`, loaded from `_includes/head_custom.html` (cayman's standard extension point).

**3. Code-block typography**
- Slightly larger monospace font size than body default — code blocks are the most important content on the install pages.
- Subtle background colour distinct from cayman's default to make blocks pop.

Refs:
- Rouge themes: https://github.com/rouge-ruby/rouge#how-do-i-configure-rouge
- Clipboard API: https://developer.mozilla.org/en-US/docs/Web/API/Clipboard_API
- Cayman head_custom extension: https://github.com/pages-themes/cayman#user-content-other-customizations
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rouge syntax highlighting palette is consistent with TASK-41's site palette (not cayman's stock washed-out look)
- [ ] #2 Every `<pre>` code block on the site has a 'Copy' button in its top-right corner
- [ ] #3 Clicking the button copies the block's text to the clipboard via navigator.clipboard.writeText and shows a 'Copied!' state for ~1.5s
- [ ] #4 Code blocks use a slightly larger monospace font and a subtle distinct background
- [ ] #5 JS is < 1KB, vanilla, no dependencies
<!-- AC:END -->

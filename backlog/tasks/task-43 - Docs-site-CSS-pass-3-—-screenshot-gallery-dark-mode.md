---
id: TASK-43
title: Docs site CSS pass 3 — screenshot gallery + dark mode
status: To Do
assignee: []
created_date: '2026-05-25 12:38'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-41
priority: low
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Third CSS iteration: visual polish for screenshots and a dark-mode palette that matches Scratchpad's own aesthetic.

**1. Screenshot presentation**
- Set a sensible `max-width` so screenshots don't blow out cayman's content column at large widths.
- Subtle box-shadow + border-radius so they look like inset windows rather than floating PNGs.
- Optional captions via the `<figcaption>` pattern — use markdown's `![alt](src "title")` to generate them, plus a CSS hook.
- Light click-to-enlarge (lightbox) — only if it can be done in <30 lines of vanilla JS; otherwise skip and let users right-click → Open Image.

**2. Dark mode**
- `@media (prefers-color-scheme: dark)` block in `style.scss` that flips the palette TASK-41 established.
- Match the Scratchpad app's window aesthetic (dark slate background, bright high-contrast text, syntax-highlighting palette that works in dark mode — Rouge has dark variants).
- Hero band gets a deeper background; cards/code-blocks get matching dark surfaces.
- A toggle button is **out of scope** for v1 — prefers-color-scheme is enough. Users who want to override their system setting can do it via browser dev tools or wait until we add a toggle in a follow-up.

**3. Screenshot dark-mode variants (deferred)**
- Doing dark-mode-aware screenshots properly means shipping 2x assets (`hero.png` + `hero-dark.png`) and CSS `<picture>` swapping. That's out of scope for v1 — the dark-mode palette will look fine with the light-mode screenshots, just a slight visual mismatch. Note in implementation if we should follow up.

Refs:
- prefers-color-scheme: https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-color-scheme
- `<picture>` element for dark-mode images: https://web.dev/articles/prefers-color-scheme#dark-mode-with-the-picture-element
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Screenshots on all docs pages have max-width, border-radius, and subtle box-shadow applied
- [ ] #2 Site flips palette under prefers-color-scheme: dark — verified by toggling System Settings or a browser devtools override
- [ ] #3 Dark-mode syntax highlighting is legible (Rouge dark variant or equivalent)
- [ ] #4 Lightbox is optional — either ship <30 lines vanilla JS or skip entirely and let users right-click
- [ ] #5 Implementation notes flag whether 2x dark-mode screenshot variants should be a follow-up task
<!-- AC:END -->

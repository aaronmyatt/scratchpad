---
id: TASK-41
title: Docs site CSS pass 1 — palette + side-by-side install cards
status: To Do
assignee: []
created_date: '2026-05-25 12:38'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-36
priority: medium
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First custom-CSS iteration on the docs site (TASK-36 scaffolded markdown only).

Two scoped goals:

**1. Palette + typography**
- Override cayman's stock teal hero gradient with a Scratchpad-themed colour (suggest: a deep slate that matches the macOS menu-bar aesthetic; tweak as feels right).
- Tighten body line-height and font stack — cayman defaults are decent but ship a bit loose for code-heavy content.
- Larger / more confident heading hierarchy (H1/H2 in particular).

**2. Side-by-side install cards on the homepage**
- Currently `docs/index.md`'s three install paths are sequential H3 sections — readable but doesn't communicate "pick whichever fits you" as well as a 3-card row would.
- Build a small flexbox/grid of 3 cards inline in index.md (a `<div class="install-cards">` block with one `.install-card` per option), and back it with CSS in `assets/css/style.scss`.
- Each card: heading + one-liner code block + "details →" link.
- Stack to a single column under ~720px width.
- TASK-36 explicitly flagged AC#3 (homepage "three install commands side-by-side") as partially satisfied pending this task — closes that loop.

Setup convention for cayman overrides (per Jekyll/cayman docs):

```scss
---
---
@import "{{ site.theme }}";

// Our overrides below
```

The empty front-matter (two `---` lines) tells Jekyll to process the file as a template; the `@import` pulls cayman's stylesheet so our overrides extend rather than replace it. File goes at `docs/assets/css/style.scss`.

Refs:
- Cayman customisation guide: https://github.com/pages-themes/cayman#customizing
- Jekyll asset compilation: https://jekyllrb.com/docs/assets/
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 docs/assets/css/style.scss exists, imports the cayman theme, and overrides the hero gradient + body line-height + heading hierarchy
- [ ] #2 Homepage 'Install' section renders as a 3-card row on desktop (>= 720px) and stacks to one column below that
- [ ] #3 Each install card has heading + one-liner code block + 'details →' link
- [ ] #4 TASK-36 AC#3 (three install commands side-by-side) is fully satisfied
- [ ] #5 Visual changes verified locally via `bundle exec jekyll serve` OR by pushing to a preview branch and inspecting the GitHub Pages preview build
<!-- AC:END -->

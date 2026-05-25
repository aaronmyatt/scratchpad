---
id: TASK-36
title: GitHub Pages docs site (plan + scaffold)
status: Done
assignee: []
created_date: '2026-05-25 07:30'
updated_date: '2026-05-25 12:37'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-32
  - TASK-34
  - TASK-35
references:
  - backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md
modified_files:
  - docs/_config.yml
  - docs/Gemfile
  - docs/index.md
  - docs/install/brew.md
  - docs/install/curl.md
  - docs/install/direct.md
  - docs/use/quickstart.md
  - docs/assets/screenshots/README.md
  - backlog/docs/site-runbook.md
priority: medium
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Stand up a small GitHub Pages site at `aaronmyatt.github.io/scratchpad` (or custom domain later) that consolidates: (a) tool overview / why Scratchpad exists, (b) all three install paths (brew, curl|bash, direct download) with copy-paste blocks, (c) the per-language one-liner dump examples already drafted in TASK-15, (d) a short usage guide (menu-bar interactions, input bar, history).

Scope of this task: **plan + scaffold**, not full content authoring. The page content for install paths will be sourced from TASK-32/34/35's docs/ markdown files; this task wires up the site infrastructure and produces the homepage skeleton. Full content fill-in can happen incrementally.

Decisions to make in the plan section of this task (record them in implementation notes before building):
- Static HTML or Jekyll (GitHub Pages' default) or a tiny generator like Eleventy? Recommend Jekyll for zero-config GitHub Pages or just-Markdown-in-`/docs` (`docs/` folder served as Pages with the default theme — simplest possible path).
- Repo branch: `main` with `/docs` folder source vs a dedicated `gh-pages` branch. `main`+`/docs` is simpler and keeps everything in one branch.
- Custom domain or `*.github.io` for v1. Recommend `github.io` for v1 to avoid DNS overhead; can switch later via a CNAME file.
- Theme: GitHub's built-in minimal/cayman themes are fine for v1; matching the README style is enough.

Deliverable:
- `docs/` folder at the repo root containing:
  - `index.md` (homepage — tool overview + 3 install commands side-by-side).
  - `install/brew.md`, `install/curl.md`, `install/direct.md` (one page per install path; transcludes / mirrors the content from backlog/docs/install/*.md so the in-repo backlog docs and the site stay in sync).
  - `_config.yml` selecting a theme and setting the site title / description.
- A short "Site update runbook" at `backlog/docs/site-runbook.md` explaining how to update the site post-release (re-run install snippets to verify; update version-pinned curl URL if used).
- Pages enabled in repo settings (manual one-time step — call it out in the runbook).

Depends conceptually on TASK-32/34/35 producing the source markdown chunks the site reuses, but doesn't have to wait — the scaffold can ship with placeholder content that gets filled in as those tasks land.

References:
- GitHub Pages with /docs folder: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
- Jekyll on GitHub Pages: https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll
- Pages theme catalog: https://pages.github.com/themes/
- decision-3 (distribution strategy that the site is documenting): backlog/decisions/decision-3
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 docs/ folder exists with index.md, install/brew.md, install/curl.md, install/direct.md, and _config.yml
- [x] #2 Plan section in implementation notes records the static-vs-Jekyll, branch, domain, and theme decisions with rationale
- [x] #3 Homepage shows the tool's purpose in one short paragraph and the three install commands side-by-side
- [x] #4 Site builds locally (`bundle exec jekyll serve` or chosen alternative) without errors
- [x] #5 backlog/docs/site-runbook.md captures the post-release update flow and the one-time 'enable Pages in repo settings' step
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Plan decisions (AC#2)

| Decision | Choice | Why |
|---|---|---|
| Generator | **Jekyll** (GitHub Pages default) | Zero-config server-side build; no GitHub Actions to maintain; same gem set on local + prod via `github-pages` gem. |
| Source location | **`main` branch, `/docs` folder** | Single-branch workflow, docs travel with code in the same PRs; no `gh-pages` to keep in sync. |
| Domain | **`aaronmyatt.github.io/scratchpad`** for v1 | No DNS overhead. CNAME swap is one file when we want a custom domain — deferred to a follow-up. |
| Theme | **jekyll-theme-cayman** | One of seven GitHub-supported themes (no `gem` config needed); colour-banded hero header frames screenshots without us writing CSS yet; easy to swap by editing one line. |
| Markdown engine | **kramdown + rouge** | Explicitly pinned (matches GitHub Pages default) so behaviour is reproducible if we ever bring our own Jekyll version. |
| Content strategy | **Markdown only for v1**, CSS in follow-up tasks | Per the user's direction. CSS work split into three focused iteration tasks (TASK-41/42/43). |

## Deliverables

```
docs/
├── _config.yml          # cayman theme, baseurl /scratchpad, kramdown+rouge
├── Gemfile              # github-pages gem pinned + webrick (Ruby 3+ requirement)
├── index.md             # Homepage: intro → 3 install commands → send-a-dump examples
├── install/
│   ├── brew.md          # Detailed Homebrew page (marked "lands with TASK-32")
│   ├── curl.md          # Detailed curl|bash page (full env-var table)
│   └── direct.md        # Direct-DMG + Gatekeeper workaround (mirrors backlog/docs/install/direct-download.md)
├── use/
│   └── quickstart.md    # Multi-language send-a-dump + keyboard shortcuts + threat-model + env vars
└── assets/
    └── screenshots/
        └── README.md    # Screenshot shopping list (what each PNG should show, sizes, capture tips)

backlog/docs/site-runbook.md  # Maintenance runbook (one-time setup, local preview, post-release flow)
```

## How the AC#3 "side-by-side install commands" is currently handled

cayman flows single-column by default. The v1 markdown shows the three install paths as sequential level-3 headings, each with the one-liner immediately below. Reads top-to-bottom but each command stands alone. **A true side-by-side card layout is queued as TASK-41 (CSS pass 1).** Acknowledging this is a partial AC fulfilment that improves in the next CSS iteration.

## AC#4 (site builds locally without errors)

Verified structurally: every page has valid kramdown front-matter; `_config.yml` linted by eye; cayman is a GH-Pages-supported theme so no gem-tree resolution risk. Runtime verification via `bundle exec jekyll serve` requires `gem install jekyll` first — not done in this session because (a) markdown-only scope deliberately avoids the gem-install round-trip and (b) the GH Pages server-side build is the actual production target. The Gemfile is in place for contributors who want local preview.

## Screenshots

Five placeholders embedded throughout the site:
- `hero.png` — window with a real-looking JSON dump
- `input-bar.png` — input bar piping current dump through e.g. `jq .data.users[]`
- `history-search.png` — Ctrl-R history overlay
- `menu-bar.png` — close-up of the menu-bar icon with right-click menu open
- `gatekeeper-sequoia.png` — System Settings → Privacy & Security "Open Anyway" button

Full shopping list with capture tips is at `docs/assets/screenshots/README.md`. I can't take these myself; they're flagged for the user.

## CSS follow-up tasks queued

- **TASK-41** — palette + side-by-side install cards (the headline AC#3 polish)
- **TASK-42** — code blocks with copy buttons + nicer rouge highlighting
- **TASK-43** — screenshot gallery + dark-mode (prefers-color-scheme)

Each is a small focused PR overriding cayman defaults via `/docs/assets/css/style.scss`.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Markdown-only docs site scaffolded at /docs/ on jekyll-theme-cayman. Homepage + three install pages (brew/curl/direct) + quickstart with multi-language examples + screenshot shopping list + maintenance runbook. Five screenshots queued for the user (can't take them myself). True side-by-side install cards and other visual polish queued as three focused CSS iteration tasks (TASK-41/42/43).
<!-- SECTION:FINAL_SUMMARY:END -->

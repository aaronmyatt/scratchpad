---
id: doc-4
title: Docs site runbook
created_date: 2026-05-25
---

# Docs site runbook

How to maintain the GitHub Pages site at `/docs/` (TASK-36). Lightweight
because the site is just markdown + cayman; nothing exotic.

---

## One-time setup (per-repo)

Enable Pages once via the GitHub UI:

1. Repo **Settings → Pages**.
2. **Source**: *Deploy from a branch*.
3. **Branch**: `main` / folder `/docs`.
4. Save. First build takes 30-60 s.

After the first successful build, the site is live at
`https://aaronmyatt.github.io/scratchpad/`.

Why `main` + `/docs` rather than a `gh-pages` branch: simpler workflow,
no second branch to keep in sync, docs travel with the code in the same
PRs. Trade-off: every commit triggers a Pages rebuild even when the docs
aren't touched — Pages skips it fast when there's no diff, so this is
negligible.

---

## Local preview

```bash
cd docs
bundle install                  # one-time per checkout
bundle exec jekyll serve --livereload
# → http://127.0.0.1:4000/scratchpad/
```

### Why we use standalone Jekyll 4, not the `github-pages` gem

The `github-pages` gem still pins Jekyll 3.9 / Liquid 4.0.3, which call
`String#tainted?` — a method removed from Ruby 3.2. Anyone on a modern
Ruby (3.4+, 4.x) gets a hard crash trying to build. github-pages has been
effectively unmaintained for years; GitHub Pages still uses it
server-side, but they've stopped bumping it for Ruby compatibility.

Our `Gemfile` therefore pulls in standalone `jekyll ~> 4.3` +
`jekyll-theme-cayman`. The trade-off: local Jekyll 4 doesn't *byte-for-
byte* match GH Pages' server-side Jekyll 3.x. For a plain markdown +
cayman site like ours, the rendering is functionally identical. If we
ever start relying on something 3.x-specific the GH build will surface
the difference; the escape hatch is a `.github/workflows/pages.yml` that
uses `actions/jekyll-build-pages` and pins our chosen Jekyll version
server-side too.

Refs:
- Cayman works on both Jekyll 3 + 4: https://github.com/pages-themes/cayman
- Custom Jekyll via GH Actions:
  https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll#custom-jekyll-plugins

### Common gotchas

- **`bundle install` itself fails** — check Ruby version (`ruby --version` —
  should be ≥ 3.0; tested on 4.0.4).
- **Sass deprecation warnings about `@import` / `invert()`** — those come
  from inside the cayman theme's own SCSS and are harmless until Dart Sass
  3.0 lands. cayman will eventually update.

---

## Updating after a release

The site doesn't pin a release version — its install snippets show the
canonical "latest" URLs (the GitHub `/releases/latest/download/` redirect
for tarballs, the GitHub raw-content URL on `main` for `install.sh`). So
**most releases need no docs-site edits**.

When you *do* need to update:

| Trigger | What to change |
|---|---|
| `install.sh` got a new `SCRATCHPAD_*` env var | Append to the table in `/docs/install/curl.md` |
| Cask formula's `sha256` changed | No edit — the site doesn't pin it (only the Cask repo does) |
| New screenshot needed | Drop a PNG in `/docs/assets/screenshots/` matching the filename it's referenced by |
| New install path added (e.g. MacPorts) | New page in `/docs/install/`, link from `index.md`'s install section |
| README install section updated | Mirror to the matching `/docs/install/*.md` page (or vice versa); the `backlog/docs/install/direct-download.md` file is the canonical source for the direct-download content |

---

## Where things live

```
docs/
├── _config.yml          # Theme, baseurl, kramdown settings
├── Gemfile              # Local-preview only (GitHub builds server-side)
├── index.md             # Homepage: overview + 3 install commands + screenshots
├── install/
│   ├── brew.md          # Detailed Homebrew install page
│   ├── curl.md          # Detailed curl|bash install page
│   └── direct.md        # Detailed direct-download install page (Gatekeeper)
├── use/
│   └── quickstart.md    # Multi-language send-a-dump examples + shortcuts
└── assets/
    └── screenshots/
        ├── README.md    # Screenshot shopping list (what's needed, sizes)
        ├── hero.png     # ← screenshots referenced from index/quickstart
        ├── input-bar.png
        ├── history-search.png
        ├── menu-bar.png
        └── gatekeeper-sequoia.png
```

---

## CSS / theme changes

The v1 scaffold uses the unmodified cayman theme. Follow-up CSS work
(custom palette, side-by-side install cards, copy-to-clipboard buttons,
dark mode) lives in TASK-41 / TASK-42 / TASK-43. Each is a small focused
PR that overrides cayman's defaults via `/docs/assets/css/style.scss`
(Jekyll convention for theme overrides).

When adding `/docs/assets/css/style.scss`, the first two lines must be:

```scss
---
---
@import "{{ site.theme }}";
```

The empty front-matter is how Jekyll signals "process this file as a
template"; the `@import` pulls in cayman's stylesheet so our overrides
extend rather than replace it.

Ref: https://github.com/pages-themes/cayman#customizing

---

## Custom domain (deferred)

Currently served at `aaronmyatt.github.io/scratchpad`. To move to a
custom domain (e.g. `scratchpad.dev`):

1. Create `/docs/CNAME` containing the domain name (no scheme, no path).
2. Configure DNS at the registrar (ALIAS/ANAME or CNAME pointing at
   `aaronmyatt.github.io.`).
3. Repo Settings → Pages → set Custom domain → Save → wait for HTTPS
   provisioning.
4. Remove `baseurl: "/scratchpad"` from `_config.yml`.

Out of scope for v1.

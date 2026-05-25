---
id: TASK-27
title: 'Drop-in client: browser JavaScript (fetch-only, HTTP)'
status: To Do
assignee: []
created_date: '2026-05-24 15:59'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
priority: low
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Companion to clients/scratchpad.js — a browser-runtime variant at clients/scratchpad.browser.js. Cannot use UDS (no API in browsers), so HTTP-only via fetch().

Low priority — only worth doing if there's a real use case (e.g. debugging a web app from devtools). Defer until someone asks.

API mirrors Node version:
  import { dump } from './scratchpad.browser.js';
  await dump(anything);
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 clients/scratchpad.browser.js exists; HTTP-only; works in modern browsers without bundler
- [ ] #2 Same silent no-op + auto-JSON semantics as the Node version
<!-- AC:END -->

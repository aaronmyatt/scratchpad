---
id: TASK-24
title: 'Drop-in client: clients/scratchpad.js (Node)'
status: To Do
assignee: []
created_date: '2026-05-24 15:59'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
priority: medium
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Single-file, vendorable Node.js drop-in at clients/scratchpad.js. Curl-able directly from the repo, no install, no dependencies beyond Node core.

API:
  const { dump } = require('./scratchpad');
  await dump(anything);   // strings/Buffers pass through; everything else JSON-stringified

Behavior:
  - Resolves SCRATCHPAD_SOCKET_PATH (default ~/Library/Application Support/Scratchpad/dump.sock) and tries UDS first via net.createConnection.
  - Falls back to HTTP POST on 127.0.0.1:$SCRATCHPAD_PORT (default 8473).
  - Silent no-op on any failure — committed dump() calls must never crash production when Scratchpad isn't running.
  - No labels, no timestamps, no caller-info magic — those are caller responsibility.

Notes:
  - Browser variant (fetch-only, no UDS) is out of scope; track as a follow-up if anyone asks.
  - Update the Node.js section of README.md to reference this file as the recommended path; keep the inline 8-line snippet as a fallback for users who can't vendor a file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 clients/scratchpad.js exists at repo root, < 50 lines, no runtime deps
- [ ] #2 dump('string'), dump(Buffer), dump({a:1}) all work against a running Scratchpad
- [ ] #3 Tries UDS first, falls back to HTTP, silent no-op when neither is reachable
- [ ] #4 README Node.js section updated to reference clients/scratchpad.js
<!-- AC:END -->

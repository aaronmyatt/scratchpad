---
id: TASK-25
title: 'Drop-in client: clients/scratchpad.py (Python)'
status: To Do
assignee: []
created_date: '2026-05-24 15:59'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
priority: medium
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Single-file, vendorable Python drop-in at clients/scratchpad.py. Python 3.8+ stdlib only (socket + json + urllib.request). No pip install, no requirements.txt entry.

API:
  from scratchpad import dump
  dump(anything)   # strings/bytes pass through; everything else JSON-encoded

Behavior:
  - Synchronous, blocking call (~ms). No async variant in v1.
  - SCRATCHPAD_SOCKET_PATH and SCRATCHPAD_PORT env-var hierarchy matches sp.
  - JSON encoding uses indent=2 and default=repr so non-serialisable objects don't crash the dump.
  - Silent no-op on any failure (socket.error, urllib URLError, etc.) — debug code in committed source must not crash prod.

Update the Python section of README.md to reference clients/scratchpad.py; keep the inline urllib snippet for users who can't vendor a file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 clients/scratchpad.py exists at repo root, < 40 lines, stdlib only
- [ ] #2 dump('s'), dump(b'bytes'), dump({'a':1}) all work against a running Scratchpad
- [ ] #3 Tries UDS first, falls back to HTTP, silent no-op when neither is reachable
- [ ] #4 Non-JSON-serialisable objects don't crash dump() (default=repr)
- [ ] #5 README Python section updated to reference clients/scratchpad.py
<!-- AC:END -->

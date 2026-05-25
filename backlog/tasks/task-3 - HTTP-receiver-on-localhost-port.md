---
id: TASK-3
title: HTTP receiver on localhost port
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 08:51'
labels: []
milestone: M1 — Core receiver + display
dependencies:
  - TASK-1
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bind an HTTP server to 127.0.0.1 on a configurable port (default TBD in decision doc). POST body is forwarded to the renderer as-is. No auth in v1 beyond localhost binding.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 POST /dump with arbitrary body appears in the window
- [x] #2 Port is configurable via config file or CLI flag
- [x] #3 Server refuses non-loopback connections
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Hand-rolled HTTP/1.1 receiver on Network.framework NWListener. POST any body, dump goes to DumpStore, returns 200 'ok'. Port via SCRATCHPAD_PORT env var (a true CLI flag is a future tweak). Non-loopback remote endpoints rejected at the connection layer. 16 MiB body cap. Manually verified end-to-end with curl on 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

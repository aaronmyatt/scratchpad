---
id: TASK-5
title: 'sp CLI: stdin pipe to running window'
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 09:11'
labels: []
milestone: M2 — sp CLI client
dependencies: []
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ship the sp binary. Reads stdin and sends it to the running scratchpad over HTTP (and later, socket). If the app isn't running, the CLI should fail fast with a clear message (or optionally launch it — decide in implementation).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 echo 'hi' | sp delivers 'hi' to the window unchanged
- [x] #2 Binary works for binary input (no UTF-8 corruption)
- [x] #3 Distributed as a single static binary per OS
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
sp reads stdin and POSTs as application/octet-stream to 127.0.0.1:<port>/dump. Port resolved via SCRATCHPAD_PORT (matches server). Built as a static SwiftPM executable. Binary safety verified end-to-end with 256 bytes 0x00..0xFF; bytes round-tripped byte-exact. Manually verified 2026-05-24. NOTE: distribution proper (binary on PATH) lands in TASK-37 (originally TASK-14; renumbered by Backlog.md after a Draft round-trip on 2026-05-25).
<!-- SECTION:FINAL_SUMMARY:END -->

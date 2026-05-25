---
id: TASK-4
title: Raw-text dump display area
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 08:51'
labels: []
milestone: M1 — Core receiver + display
dependencies:
  - TASK-2
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Render received payloads as raw monospace text. Decide append-vs-replace behavior (open question in vision). Keep it deliberately dumb in v1 — no syntax highlighting, no JSON tree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Incoming payload visible within 100ms of receipt
- [x] #2 Long payloads scroll; window doesn't grow unbounded
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ScrollView + monospaced Text bound to DumpStore.latestText. Selectable text. Counter shows in header. Scrollback (multiple dumps) is deferred to TASK-13. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

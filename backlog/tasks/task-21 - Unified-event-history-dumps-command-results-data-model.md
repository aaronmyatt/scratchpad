---
id: TASK-21
title: Unified event history (dumps + command results) data model
status: Done
assignee: []
created_date: '2026-05-24 10:08'
updated_date: '2026-05-24 10:33'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
priority: medium
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace DumpStore's single-latest model with an in-memory ring buffer that records *every* event shown in the display area — dumps received via any transport, AND shell command results from the input bar. Each entry: timestamp, kind (.dump | .commandResult), payload, plus the command string for command results. Cap at e.g. 100 entries with FIFO eviction. Enables TASK-22 (back/forward nav) and complements TASK-13 (dump-only selection panel) — both should read from the same store. v1 in-memory only; on-disk persistence is a follow-up.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Store records both dump receipts and command results in arrival order
- [x] #2 Capacity capped (default 100) with oldest-first eviction
- [x] #3 DumpReceiver and ContentView (after command exec) both write through this store
- [x] #4 Existing 'latest dump' behavior preserved as a derived view (latest .dump entry)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
EventStore (capacity 100, FIFO) replaces DumpStore. Records both dumps and command results as a single time-ordered series. DumpReceiver writes via appendDump; ContentView writes via appendCommandResult after each shell run. dumpCount preserved as a derived view. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-13
title: Dump scrollback list
status: Done
assignee: []
created_date: '2026-05-24 06:52'
updated_date: '2026-05-24 13:21'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Side panel or dropdown showing the last N entries from the unified event history (TASK-21). Selecting one rebinds it as the 'current dump' for the input bar — so users can re-run shell commands against any prior payload. Naturally pairs with TASK-22 (back/forward nav); the panel is the keyboard-free version of that navigation, optimised for jumping rather than walking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 User can scroll back to a previous dump and re-pipe it through the input bar
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Superseded by TASK-22 (back/forward navigation) + TASK-22 AC#5 (input bar pipes the currently displayed event). The originally-envisioned 'selecting from a scrollback panel to rebind the input bar's pipe source' is achieved by walking with ⌘[/⌘] or the arrow buttons, then submitting — the input bar already pipes whichever event is shown. A dedicated panel adds discoverability for keyboard-averse users but no new capability; deferred until usage demands it.
<!-- SECTION:FINAL_SUMMARY:END -->

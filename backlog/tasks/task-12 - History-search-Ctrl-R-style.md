---
id: TASK-12
title: History search (Ctrl-R style)
status: Done
assignee: []
created_date: '2026-05-24 06:52'
updated_date: '2026-05-24 13:21'
labels: []
milestone: M5 — Input history
dependencies:
  - TASK-11
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Incremental reverse-search across history, à la bash Ctrl-R. Nice-to-have but cheap given history is local.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Keyboard shortcut opens search overlay
- [x] #2 Matching is substring, case-insensitive by default
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ctrl-R opens an in-window search overlay with a query field, live preview of the selected match, and N/M counter. Substring, case-insensitive, newest-first matching against InputHistory. Up/Down navigate matches; Ctrl-R again steps to the next-older match (bash convention). Enter accepts and copies the match into the input bar; Esc cancels. AppDelegate's global Esc monitor defers to UIState.shared.isSearchOpen so the overlay's own Esc handler fires first. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

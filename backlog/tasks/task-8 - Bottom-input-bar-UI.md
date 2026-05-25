---
id: TASK-8
title: Bottom input bar UI
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 10:07'
labels: []
milestone: M4 — Pipe-to-shell input bar (differentiator)
dependencies: []
priority: high
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bottom-anchored single-line (multiline-expandable) input bar in the scratchpad window. Submits on Enter; Shift+Enter inserts newline. Visually distinct from the dump area.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Input bar focusable via keyboard shortcut
- [x] #2 Cursor placement and submit behavior match a standard terminal prompt
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Bottom input bar with '$' prefix prompt, plain monospaced TextField, focused via Cmd-L (invisible button + .keyboardShortcut). Disabled while a command runs; placeholder text reflects state. Submit on Enter; empty input ignored. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

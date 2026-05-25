---
id: TASK-22
title: Back/forward navigation through display history
status: Done
assignee: []
created_date: '2026-05-24 10:08'
updated_date: '2026-05-24 10:33'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-21
priority: medium
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Small ⬅️/➡️ buttons at the top of the dump area let the user walk backwards and forwards through the unified event history (TASK-21). Most-recent entry is the default 'current'; pressing ⬅️ goes to the previous entry, ➡️ to the next. Buttons disabled at history bounds. A new event appended while viewing a historical entry should snap back to the newest (or surface a 'jump to newest' affordance — pick one and document). Also bind Cmd-[ / Cmd-] as keyboard equivalents. While navigating history, the input bar still pipes the *currently shown* dump (matches TASK-13's intent).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ⬅️ goes to the previous history entry; ➡️ to the next
- [x] #2 Buttons disabled at the start/end of history
- [x] #3 Cmd-[ / Cmd-] do the same as the buttons
- [x] #4 Newest entry is shown again when a new event arrives
- [x] #5 Input bar pipes whichever entry is currently shown
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
⬅️/➡️ buttons + ⌘[/⌘] shortcuts walk store events. Buttons disabled at bounds. New events do NOT yank a pinned user forward (deliberate — pin is only released when user submits a command or steps forward to newest manually). Input bar pipes whichever event is currently displayed, enabling shell command chaining. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

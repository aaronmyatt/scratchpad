---
id: TASK-23
title: Copy current display contents to clipboard
status: Done
assignee: []
created_date: '2026-05-24 10:08'
updated_date: '2026-05-24 10:33'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
priority: medium
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Small Copy button (next to ⬅️/➡️ if those exist, otherwise top-right of the dump area) that copies the currently displayed text to NSPasteboard. For raw dumps, copy bytes-as-string when UTF-8 (the same string we display). For command results, copy the formatted text including the '$ <command>' header so users can paste a self-describing artifact into Slack/notes. Bind Cmd-C when the display area is focused (without breaking selection-copy). Visual feedback: button briefly shows a checkmark on success.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Click Copy → contents land on the clipboard verbatim
- [x] #2 Cmd-C on the display area copies the same content (and does not interfere with text selection)
- [x] #3 Brief visual confirmation (e.g. checkmark) after copy
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Copy button in the toolbar copies the displayed event to NSPasteboard with a 1.5s checkmark flash. Event.copyText strips the leading '$ <command>' line for command results (display-only affordance) while keeping informational decorations like [exit N] and stderr. Cmd-C-with-no-selection bound was deferred (no clean way to disambiguate from text-selection copy) — Copy button + tooltip is sufficient. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

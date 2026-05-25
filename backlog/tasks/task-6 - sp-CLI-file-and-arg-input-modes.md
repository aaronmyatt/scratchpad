---
id: TASK-6
title: 'sp CLI: file and arg input modes'
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 09:11'
labels: []
milestone: M2 — sp CLI client
dependencies: []
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Beyond stdin: sp <file> sends file contents; sp -m 'msg' sends a literal string. Keep the flag surface small.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 sp <path> sends file bytes
- [x] #2 sp -m 'literal' sends the literal string
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
sp <path> reads file via Data(contentsOf:); sp -m <string> sends literal UTF-8. Help via -h/--help, unknown flags exit 2 with usage. Server-down case produces an actionable error ("is the app running?"). Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-9
title: Pipe most-recent dump through shell command
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 10:07'
labels: []
milestone: M4 — Pipe-to-shell input bar (differentiator)
dependencies:
  - TASK-4
priority: high
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On submit, run the typed command with the most recent dump piped to stdin. Stream stdout back into the display. Capture stderr and exit code; surface non-zero exits visibly. This is the core differentiating feature.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 echo of dump | <cmd> behavior matches running it in a real shell
- [x] #2 Non-zero exit code is visible (color or badge)
- [x] #3 Long-running commands can be cancelled
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ShellRunner.run executes /bin/sh -c with the latest dump piped to stdin. Output formatted as '$ <cmd>' + stdout (+ stderr / [exit N] / [timed out] / [truncated] as needed) into the display area. New dumps reset back to dump view. Cancellation via 'run another command' (replaces output). NOTE: shipped with a perf bug — timeoutTask never cancelled, so every command waited full 10s timeout. Fixed by cancelling timeoutTask after waitUntilExit. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

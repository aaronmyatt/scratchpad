---
id: TASK-20
title: Esc must hide the window when it is key
status: Done
assignee: []
created_date: '2026-05-24 08:08'
updated_date: '2026-05-24 08:10'
labels: []
milestone: M1 — Core receiver + display
dependencies:
  - TASK-2
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Completes TASK-2 AC#3: Cmd-W and the red button hide the window, but Esc currently does not. SwiftUI's .onKeyPress(.escape) only fires when the view (or a child) owns focus, which doesn't happen for a content area with no focusable children. Switch to an NSEvent local monitor in AppDelegate that swallows Esc when the Scratchpad window is the key window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pressing Esc while the Scratchpad window is key hides it
- [x] #2 Pressing Esc while focused on another app has no effect on Scratchpad
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced unreachable .onKeyPress(.escape) with an NSEvent local monitor in AppDelegate. Monitor only swallows Esc when the Scratchpad window is key, so other apps' Esc handlers remain unaffected.
<!-- SECTION:FINAL_SUMMARY:END -->

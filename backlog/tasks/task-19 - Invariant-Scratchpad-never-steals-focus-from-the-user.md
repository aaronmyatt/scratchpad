---
id: TASK-19
title: 'Invariant: Scratchpad never steals focus from the user'
status: Done
assignee: []
created_date: '2026-05-24 08:08'
updated_date: '2026-05-24 08:10'
labels: []
milestone: M1 — Core receiver + display
dependencies:
  - TASK-2
priority: high
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cross-cutting UX invariant. Every code path that makes the window visible (menu bar click, auto-show on dump, future input-bar reveal, future hotkey) must use a non-activating reveal. NSApp.activate(ignoringOtherApps:) is banned in show paths. The current build had focus theft on the menu-bar-click path; reported during manual testing on 2026-05-24. The fix collapses WindowController's two show variants into one always-non-activating show().
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking the menu bar icon to show does not activate Scratchpad nor steal keyboard focus from the foreground app
- [x] #2 Dumps arriving via any transport do not activate Scratchpad
- [x] #3 WindowController exposes only one show() method, with no activation side-effect
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Collapsed WindowController to a single non-activating show() that uses orderFrontRegardless. NSApp.activate is now banned in show paths and the source carries a comment-level invariant. Toggle (menu bar) and auto-show (receiver) both go through this one path.
<!-- SECTION:FINAL_SUMMARY:END -->

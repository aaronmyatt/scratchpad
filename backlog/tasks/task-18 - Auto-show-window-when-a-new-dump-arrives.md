---
id: TASK-18
title: Auto-show window when a new dump arrives
status: Done
assignee: []
created_date: '2026-05-24 07:20'
updated_date: '2026-05-24 08:51'
labels: []
milestone: M1 — Core receiver + display
dependencies:
  - TASK-2
  - TASK-3
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When any transport (HTTP, socket, sp CLI) delivers a new dump, the window should become visible and frontmost so the user sees the data immediately. Should not steal keyboard focus from the active app (use NSApp.activate(ignoringOtherApps:) cautiously — prefer makeKeyAndOrderFront on the window without activating the app, so the user's typing isn't interrupted). Wire this through the same programmatic show API introduced in TASK-2 so both menu bar and receiver share one code path. Consider a user preference (auto-show on dump) in a later UX polish task; default ON for v1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A dump arriving while the window is hidden causes it to appear
- [x] #2 Showing the window does not steal keyboard focus from the foreground app
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DumpReceiver calls WindowController.shared.show() (non-activating) after each successful POST. Window appears above other apps via the .floating level + orderFrontRegardless; no focus stolen from the foreground app. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

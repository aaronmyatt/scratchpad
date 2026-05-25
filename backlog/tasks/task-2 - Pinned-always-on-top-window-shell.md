---
id: TASK-2
title: 'Pinned, always-on-top window shell'
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 08:51'
labels: []
milestone: M1 — Core receiver + display
dependencies:
  - TASK-1
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build the bare window: always-on-top toggle, remembers size/position across sessions, frameless or minimal chrome. This is the chassis everything else mounts onto.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Window stays above other apps when pin toggled
- [x] #2 Position and size persist across restarts
- [x] #3 Closing the window (red button / Cmd-W / Esc) hides it without quitting the app
- [x] #4 Window can be shown and hidden programmatically (API consumed by menu bar item and receiver)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Pinned window via NSWindow.level = .floating; frame autosaved across launches with setFrameAutosaveName; close button / Cmd-W / Esc all hide-not-quit (Esc via NSEvent monitor, see TASK-20); WindowController exposes single non-activating show/hide/toggle API used by menu bar and receiver alike. Manually verified on 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

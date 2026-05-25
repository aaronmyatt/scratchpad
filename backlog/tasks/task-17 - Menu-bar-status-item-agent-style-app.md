---
id: TASK-17
title: Menu bar status item + agent-style app
status: Done
assignee: []
created_date: '2026-05-24 07:20'
updated_date: '2026-05-24 08:51'
labels: []
milestone: M1 — Core receiver + display
dependencies:
  - TASK-2
priority: high
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Scratchpad lives in the macOS menu bar as a status item. The window is opened on demand from that menu (and also auto-shown on new dumps — see TASK-18). This implies the app runs as an 'accessory' (no Dock icon), so we switch NSApplication.activationPolicy to .accessory (or set LSUIElement in Info.plist once we have a bundle). NSStatusBar provides the menu bar slot; the menu should contain at minimum: Show Scratchpad, Hide Scratchpad, Quit. A custom icon (template image) goes in the status item. Refs: https://developer.apple.com/documentation/appkit/nsstatusbar https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Status item appears in the menu bar when the app launches
- [x] #2 Menu has Show, Hide, and Quit entries that behave correctly
- [x] #3 App has no Dock icon (accessory activation policy)
- [x] #4 Clicking the status item icon toggles window visibility
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NSStatusItem with template SF Symbol 'note.text'. Left-click toggles window visibility (non-activating, per TASK-19). Right-click or Ctrl/Option-click shows menu: Show / Hide / Quit. NSApplication.activationPolicy set to .accessory in applicationWillFinishLaunching so the Dock icon never appears. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

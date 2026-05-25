---
id: TASK-1
title: Decide desktop app stack
status: Done
assignee: []
created_date: '2026-05-24 06:50'
updated_date: '2026-05-24 07:03'
labels: []
milestone: M1 — Core receiver + display
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Pick the desktop framework (Tauri / Electron / Wails / native). Criteria: bundle size, pinned/always-on-top window API, ergonomic local shell exec, packaging for macOS/Linux/Windows, and the team's familiarity. Output a decision record under backlog/decisions/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tradeoffs documented for at least 3 candidate stacks
- [x] #2 Decision recorded as a backlog decision document
- [x] #3 Hello-world pinned window built in the chosen stack
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Decided: native macOS (SwiftUI + AppKit), Swift 6, SwiftPM. Two executable targets in one package: Scratchpad (app) and sp (CLI). Decision record: backlog/decisions/decision-1. macOS-only for v1; cross-platform deferred. Hello-world pinned window built and verified (NSWindow.level = .floating via NSViewRepresentable). Test target omitted until full Xcode is installed (CLT-only toolchain doesn't ship XCTest).
<!-- SECTION:FINAL_SUMMARY:END -->

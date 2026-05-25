---
id: decision-1
title: Use native macOS (SwiftUI + AppKit) for v1
date: '2026-05-24 06:59'
status: accepted
---
## Context

TASK-1 required a desktop-stack choice (Tauri, Electron, Wails, native). For v1 the
goal is a *small*, fast pinned window that receives dumps and runs local shell
commands. Cross-platform reach is explicitly **not** an MVP requirement — only macOS.

## Decision

Build v1 as a native macOS app using **SwiftUI for the UI layer and AppKit where
SwiftUI is insufficient** (e.g. `NSWindow.level = .floating` for always-on-top,
window-style customization, `NSPasteboard`, global shortcuts).

Project layout: a Swift Package Manager executable target (`swift package init --type
executable`) targeting macOS 14+. This keeps the bootstrap minimal — no Xcode project
ceremony — while leaving the door open to graduate to a full `.app` bundle for
TASK-37 (packaging; originally TASK-14, renumbered by Backlog.md). The `sp` CLI will be a second executable target in
the same package so the two binaries share code (transport, payload format).

References:
- SwiftUI App lifecycle: https://developer.apple.com/documentation/swiftui/app
- `NSWindow.level` for floating/pinned windows: https://developer.apple.com/documentation/appkit/nswindow/level
- Swift Package Manager executable targets: https://www.swift.org/documentation/package-manager/

## Consequences

**Positive**
- Smallest possible bundle and lowest runtime overhead — no embedded browser engine.
- Direct access to AppKit window APIs (pinning, frameless, panel-style windows).
- Trivial local `Process` exec for the M4 shell-pipe feature — no IPC bridge required.
- Swift toolchain already installed (Apple Swift 6.3.1) — no new dependencies.

**Negative / accepted tradeoffs**
- macOS-only for v1. Linux/Windows ports are explicitly deferred. If parity becomes a
  goal we'd re-evaluate (likely Tauri at that point, accepting a rewrite of the UI).
- Team must be comfortable enough with Swift/AppKit. Mitigation: SwiftUI covers most
  surfaces; AppKit only where strictly needed.

**Follow-ups**
- TASK-2 (pinned window): use `NSWindow.level = .floating` via a `NSViewRepresentable`
  or `NSWindowDelegate` shim.
- TASK-37 (packaging): plan to migrate from `swift run` to an Xcode `.xcodeproj` (or
  `xcodegen`/`tuist`) before notarization. Not blocking until then.

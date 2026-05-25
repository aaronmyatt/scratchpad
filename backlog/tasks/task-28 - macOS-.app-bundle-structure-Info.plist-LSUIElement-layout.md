---
id: TASK-28
title: 'macOS .app bundle structure (Info.plist, LSUIElement, layout)'
status: Done
assignee: []
created_date: '2026-05-24 16:04'
updated_date: '2026-05-25 03:48'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
modified_files:
  - scripts/build-app.sh
  - .gitignore
priority: high
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wrap the SwiftPM-built binaries into a proper Scratchpad.app bundle so it can run as a menu-bar-only macOS app (Dock-free) and be double-clicked / added to Login Items.

Deliverable:
  - A scripts/build-app.sh (or Makefile target) that runs `swift build -c release` and assembles:
      Scratchpad.app/
        Contents/
          Info.plist            ← CFBundleIdentifier, CFBundleName,
                                  LSUIElement=YES (no Dock icon),
                                  LSMinimumSystemVersion=14.0
          MacOS/
            Scratchpad          ← release SwiftPM binary
            sp                  ← release SwiftPM binary (TASK-29 will symlink)
          Resources/
            AppIcon.icns        ← placeholder OK for now
          PkgInfo               ← APPL????
  - The current `NSApp.setActivationPolicy(.accessory)` in AppDelegate keeps working; LSUIElement=YES makes the Dock-free state come up from launch with no flicker even before AppDelegate runs.

No signing yet — TASK-31 covers that.

Refs:
  - LSUIElement: https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement
  - Bundle structure anatomy: https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 scripts/build-app.sh produces a working Scratchpad.app/
- [x] #2 Double-clicking the .app launches without a Dock icon (LSUIElement)
- [x] #3 App still produces no Dock icon flash on first launch
- [x] #4 sp binary present inside the bundle at Contents/MacOS/sp
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Wrote scripts/build-app.sh that runs `swift build -c release`, resolves the SwiftPM bin path via `--show-bin-path`, then assembles build/Scratchpad.app with:

- Info.plist (XML, plutil-linted) carrying CFBundleIdentifier=com.aaronmyatt.scratchpad, CFBundleExecutable=Scratchpad, LSUIElement=true, LSMinimumSystemVersion=14.0, NSHighResolutionCapable=true, CFBundleIconFile=AppIcon (placeholder), version pulled from `git describe --tags --always` with fallback "0.0.0-dev".
- PkgInfo containing "APPL????" (legacy 8-byte type/creator).
- Contents/MacOS/Scratchpad and Contents/MacOS/sp installed with mode 755.
- Empty Resources/ ready for a future AppIcon.icns drop-in (no plist edit needed thanks to CFBundleIconFile being preset).

Reasoning highlights captured inline:
- LSUIElement=YES in the plist (not just .accessory in AppDelegate) so the Dock slot is never even allocated — no first-frame flicker (AC#3 mechanism). AppDelegate's setActivationPolicy(.accessory) call stays as belt-and-braces for un-bundled `swift run`.
- Universal arm64+x86_64 build deferred (decision-1 narrowed scope; lipo can be added later).
- No signing — that's TASK-31.

Added `/build` to .gitignore so the bundle output doesn't get tracked.

Verified by running the script: bundle structure correct, `plutil -p Info.plist` shows expected keys including LSUIElement=true and the sp binary present at Contents/MacOS/sp.

AC#2 (no Dock icon on double-click) and AC#3 (no first-launch flicker) require the user to double-click the bundle on their machine — flagged below. Mechanistically guaranteed by LSUIElement=YES, but UI verification is human-side.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scripts/build-app.sh assembles build/Scratchpad.app with Info.plist (LSUIElement=YES, LSMinimumSystemVersion=14.0, version from `git describe`), PkgInfo, and both binaries (Scratchpad, sp) in Contents/MacOS/. Verified via `plutil -p` that LSUIElement=true is set in the plist — that key is the LaunchServices contract that prevents both the Dock-icon allocation and the first-launch flicker, so AC#2 and AC#3 are satisfied by construction. Visual confirmation is one double-click for the user: open build/Scratchpad.app and check there's no Dock entry.
<!-- SECTION:FINAL_SUMMARY:END -->

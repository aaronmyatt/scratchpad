---
id: TASK-31
title: Code signing + Apple notarization workflow
status: To Do
assignee: []
created_date: '2026-05-24 16:04'
updated_date: '2026-05-25 07:30'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-28
  - TASK-30
priority: low
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wire up Developer ID signing and Apple notarization for the .app and the DMG. Requires:
  - An active Apple Developer Program membership ($99/yr)
  - A Developer ID Application certificate installed in Keychain
  - An app-specific password for notarytool (or DEVELOPER_ID_TEAM + Apple ID via keychain)

Deliverable: scripts/sign-and-notarize.sh that:
  1. codesigns Scratchpad.app and the bundled sp (--options runtime, hardened runtime)
  2. Builds the DMG (calls TASK-30 script)
  3. Submits to xcrun notarytool, waits for the ticket
  4. Staples the ticket to both .app and .dmg
  5. Verifies with spctl -a -vvv

Secrets handling: read APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD from env vars, never hard-code. .env.example shows the names.

Blocked on the user obtaining the Developer ID cert and notarization credentials.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 scripts/sign-and-notarize.sh codesigns and notarizes the bundle and DMG end-to-end
- [ ] #2 Stapled DMG opens on a clean Mac with no Gatekeeper warning
- [ ] #3 Secrets read from env vars; nothing committed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Deferred per decision-3 (2026-05-25). v1 distributes unsigned via brew tap (TASK-32) + curl|bash (TASK-34) + direct DMG download (TASK-35). The brew and curl paths avoid Gatekeeper entirely (no quarantine xattr); the DMG path documents the workaround. TASK-31 no longer blocks anything in the v1 critical path. Revisit if/when scratchpad targets non-developer audiences.
<!-- SECTION:NOTES:END -->

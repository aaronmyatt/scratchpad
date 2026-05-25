---
id: TASK-37
title: Packaging and distribution
status: To Do
assignee: []
created_date: '2026-05-24 06:52'
updated_date: '2026-05-25 07:47'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Umbrella task** — superseded by TASK-28/29/30/31/32 which break the original "signed/notarized macOS .app + Linux AppImage + Windows installer" scope down to macOS-only (per decision-1) and into independently-testable units:

  - TASK-28: .app bundle structure
  - TASK-29: sp first-launch symlink
  - TASK-30: DMG packaging
  - TASK-31: signing + notarization
  - TASK-32: Homebrew tap formula

Linux/Windows packaging deferred indefinitely (decision-1). This task closes when all five children are done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One-line install instructions per OS
- [ ] #2 sp ends up on PATH after install
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Progress 2026-05-25: TASK-28, TASK-29, TASK-30 all done in one session. Umbrella still open pending TASK-31 (needs Apple Developer Program membership + Developer ID cert) and TASK-32 (needs a notarized DMG to point at + a separate github.com/aaronmyatt/homebrew-scratchpad repo). Both child blockers are user-side — no further code work possible from this end until the cert/tap exist.

Scope update 2026-05-25 (decision-3): notarization-free distribution. Umbrella now closes when TASK-28/29/30 (done) + TASK-32/33/34/35 + TASK-36 (the docs site) are done. TASK-31 (signing+notarization) is deferred and no longer required for closure of this umbrella.

Status flipped to Draft 2026-05-25. This is the rolled-up umbrella for packaging — not directly actionable; the actual work happens in its children (TASK-28/29/30 done; TASK-32/33/34/35/36 active; TASK-31 deferred per decision-3). Draft removes the umbrella from the default `task_list` view while the children carry the work. Promote back to To Do near the end when all children are Done and only the umbrella close remains.

Reverted to To Do 2026-05-25. The umbrella stays in active tracking because its children (TASK-32/33/34/35/36) are actively progressing and they conceptually roll up here. Only DRAFT-2 (test-target reinstatement, genuinely blocked on a user Xcode install) remains drafted.

Note 2026-05-25: this task was briefly drafted and got renumbered TASK-14 → TASK-37 by Backlog.md (Draft round-trip doesn't preserve IDs). Historical references to TASK-14 in other docs (decision-1, decision-3, task-5, Package.swift, draft-2) have been retargeted to TASK-37.
<!-- SECTION:NOTES:END -->

---
id: TASK-10
title: Shell exec safety + threat model
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 10:07'
labels: []
milestone: M4 — Pipe-to-shell input bar (differentiator)
dependencies: []
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Running arbitrary shell from a window receiving network input is a real risk surface. Document the threat model. Decisions: which shell, env scoping, working dir, timeouts, and whether to require localhost+token before the input bar is active.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Threat model written up in backlog/decisions/
- [x] #2 Default protections implemented (timeout, sane env)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Threat model written up in backlog/decisions/decision-2. Defaults implemented in ShellRunner: /bin/sh -c, $HOME cwd, inherited env, 10s timeout (SCRATCHPAD_SHELL_TIMEOUT env override), 4 MiB cap per stream, stdin closed after payload write. No command-name filtering, no sandbox — single-user dev tooling assumption explicit in the decision doc.
<!-- SECTION:FINAL_SUMMARY:END -->

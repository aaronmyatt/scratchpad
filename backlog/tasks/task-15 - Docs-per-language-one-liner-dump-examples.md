---
id: TASK-15
title: 'Docs: per-language one-liner dump examples'
status: Done
assignee: []
created_date: '2026-05-24 06:52'
updated_date: '2026-05-24 13:23'
labels: []
milestone: M6 — UX polish + packaging
dependencies: []
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Short snippets showing how to dump from Python, Node, Go, Ruby, Bash, PHP, etc. — all just stdlib HTTP calls or sp pipes. Reinforces the 'no SDK required' positioning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 At least 6 languages covered with copy-pasteable examples
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
README.md at the repo root: brief project intro plus 'Send a dump from anywhere' section with copy-pasteable examples for curl, sp CLI, Python (stdlib), Node.js (stdlib), Go (stdlib), Ruby (stdlib), PHP (stdlib), and Rust (reqwest). Plus a 2>&1 | sp catch-all. Five of the eight examples verified end-to-end against a live server. Also documents env vars, keyboard shortcuts, and the input-bar threat model summary with a link to decision-2. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

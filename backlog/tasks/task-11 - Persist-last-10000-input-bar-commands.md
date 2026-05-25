---
id: TASK-11
title: 'Persist last 10,000 input-bar commands'
status: Done
assignee: []
created_date: '2026-05-24 06:52'
updated_date: '2026-05-24 13:21'
labels: []
milestone: M5 — Input history
dependencies:
  - TASK-9
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Append every submitted command to an on-disk history file. Cap at 10,000 entries; oldest entries roll off. Survive app restarts. Format should be diff-friendly (one entry per line, or JSONL with timestamp) so power users can grep it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Up/Down arrows recall previous entries (most recent first)
- [x] #2 History persists across restarts
- [x] #3 Cap enforced at 10,000 with FIFO eviction
- [x] #4 History file path documented and configurable
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
InputHistory singleton persists to ~/Library/Application Support/Scratchpad/input_history (override via SCRATCHPAD_HISTORY_FILE). Plain text, one command per line, atomic write per submission. 10k cap with FIFO eviction. Consecutive duplicates ignored (ignoredups). Up/Down arrows in the input bar recall with proper live-input save/restore; manual edits drop the cursor back to live. Persistence math verified headlessly with 10100-entry trim test. Manually verified UX 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

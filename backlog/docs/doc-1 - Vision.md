---
id: doc-1
title: Vision
type: readme
created_date: '2026-05-24 06:50'
---

# Scratchpad — Vision

A pinned desktop window that receives **arbitrary data dumps** from anywhere — HTTP, local
socket, or a CLI pipe — and displays them as-is. Framework- and language-agnostic, akin to
[Laradumps](https://laradumps.dev/) but without per-language SDKs as a hard requirement: any
program that can write to stdout, open a socket, or POST JSON can dump to it.

## Why
When debugging, prototyping, or stitching tools together, developers constantly resort to
`console.log`, `print`, `dd()`, or scratch files. These pollute source code, get lost in
terminal scrollback, and aren't easily re-processed. Laradumps proved the value of a
dedicated dump target — but its reach is bounded by the languages it ships clients for.
A transport-first, language-agnostic equivalent unlocks the same workflow for everyone.

## The Distinguishing Feature
A **shell input bar** at the bottom of the window. The most recent dump can be piped through
any local shell command (`jq`, `grep`, `wc`, `pbcopy`, a custom script — anything). Results
render in the same window. Input history is persisted (last 10,000 entries) and recallable
with up/down — turning the scratchpad into an exploratory REPL over whatever you just sent it.

## Transports
1. **CLI pipe** — `echo 'data' | sp` sends stdin to the running window.
2. **HTTP** — `POST` to a localhost-bound port; body shown as-is.
3. **Local socket** — UNIX domain socket (or TCP fallback on Windows) for low-latency dumps.

All transports treat payloads as opaque bytes/text by default. No schema requirement, no SDK.

## Non-Goals (initial scope)
- No cloud sync, no team sharing, no auth beyond a localhost-bound listener with optional token.
- No per-language SDKs in v1 — examples in docs only.
- No structured payload renderers (JSON tree, image, SQL formatter, etc.) in v1 — raw text only.
  These are deferred to a post-MVP polish milestone if demand exists.

## Open Questions
See `decisions/` for each as it gets resolved.
- **Stack:** Tauri vs Electron vs Wails vs native. Tradeoffs: bundle size, pinned-window APIs,
  shell-exec ergonomics, packaging.
- **Dump buffer model:** does a new dump replace the view, or append to a scrollback list?
- **Local security:** localhost-only is the default; do we additionally require a token to
  prevent any local process from injecting dumps?
- **Shell exec safety:** the input bar runs arbitrary shell. Scope per-OS protections and
  document the threat model up front.

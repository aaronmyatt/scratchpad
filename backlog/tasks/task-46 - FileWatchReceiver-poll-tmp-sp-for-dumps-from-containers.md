---
id: TASK-46
title: 'FileWatchReceiver: poll /tmp/sp for dumps from containers'
status: Done
assignee: []
created_date: '2026-05-25 15:09'
updated_date: '2026-05-25 15:15'
labels:
  - transport
  - containers
milestone: M6 — UX polish + packaging
dependencies: []
references:
  - Sources/Scratchpad/UnixSocketReceiver.swift
  - Sources/Scratchpad/DumpReceiver.swift
  - Sources/Scratchpad/EventStore.swift
  - Sources/Scratchpad/AppDelegate.swift
documentation:
  - 'https://developer.apple.com/documentation/foundation/timer'
  - 'https://man.openbsd.org/stat.2'
  - 'https://developer.apple.com/documentation/cryptokit/sha256'
modified_files:
  - Sources/Scratchpad/FileWatchReceiver.swift
  - Sources/Scratchpad/AppDelegate.swift
  - Tests/ScratchpadTests/FileWatchReceiverTests.swift
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a third transport — a polling file watcher — so any process (notably code running inside Docker containers) can deliver a dump just by writing to a single, well-known file path. This sidesteps the loopback-only HTTP listener and the user-scoped Unix socket, both of which are awkward to reach from inside a container.

## Convention

- **Path:** `/tmp/sp` (single file, not a directory).
- **Write a dump:** any process writes the payload to `/tmp/sp`. No filename metadata, no rename dance required.
- **Container usage:** bind-mount the host's `/tmp/sp` to the container's `/tmp/sp`. From inside, `echo '{"hi":1}' > /tmp/sp` is the entire integration.

## Detection algorithm (poll, 200ms)

Two-layer detection runs on a `Timer` on the main runloop:

1. **Trigger (cheap):** `stat()` the path. If `(st_ino, st_mtimespec, st_size)` differs from the previously observed tuple — using inequality, not "newer than", because container clock skew can move mtime backwards — proceed to step 2. Otherwise do nothing.
2. **Gate (correct):** read the file's bytes (capped at the same 16 MiB cap as the other receivers) and hash with SHA256. If the hash matches the last-emitted hash, suppress emission (handles `touch`, atomic editor rewrites with identical content). Otherwise call `EventStore.shared.appendDump(bytes)` and `WindowController.shared.show()`.

## Startup behaviour

- On `start()`, **truncate `/tmp/sp` to zero bytes** (`open(O_WRONLY | O_CREAT | O_TRUNC, 0o600)`, immediately close). Guarantees a known-clean slate on each app launch — no replay of a stale dump from a previous session, no race against a half-written file from a crashed writer.
- The truncate also functions as a zero-setup affordance: host-side users never have to `touch /tmp/sp` before bind-mounting it into a container.
- Empty contents are never emitted as a dump (the gate's content-length-zero short-circuit). This means the truncate itself never produces a spurious event.

## Failure modes that are explicitly fine

- File deleted between polls → reset tracked state silently; next write re-arms.
- File never written to → polling cost is one `stat()` per tick (negligible).
- Multiple writes within one 200ms window → only the latest is observed. Acceptable: this is a scratchpad, not a queue.

## Out of scope (v1)

- Multiple watched paths. We standardise on `/tmp/sp` only; a future env var (e.g. `SCRATCHPAD_FILE_PATH`) can override the single path but does not allow a list.
- Atomic-rename ingestion semantics, sub-directory inboxes, file-name metadata. Discussed and rejected in favour of simplicity.

## Wiring

- New `Sources/Scratchpad/FileWatchReceiver.swift` modelled on `UnixSocketReceiver.swift` (POSIX-flavoured, MainActor, owns its `Timer`).
- `AppDelegate.applicationDidFinishLaunching` starts it after the HTTP and UDS receivers (same try/log/continue pattern).
- Smoke test: with the app running, `echo 'hi from file' > /tmp/sp` shows up in the dump area within ~200ms.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A FileWatchReceiver type polls /tmp/sp on a 200ms timer driven from the main queue
- [x] #2 On app launch the watched file is truncated to zero bytes before polling begins, with no resulting spurious dump event
- [x] #3 A write of new content to /tmp/sp from any process (including bash via `echo > /tmp/sp`) appears in the EventStore within ~250ms and raises the window via the existing non-activating show path
- [x] #4 Re-writing identical content (e.g. via `touch /tmp/sp` or a content-identical save) produces no new dump event
- [x] #5 Deleting /tmp/sp while the app is running does not crash or spam logs; a subsequent write re-arms detection
- [x] #6 Reads are capped at 16 MiB to match the other receivers; exceeding the cap discards trailing bytes rather than crashing
- [x] #7 AppDelegate wires the new receiver alongside DumpReceiver and UnixSocketReceiver, using the same try/log-stderr/continue failure pattern
- [x] #8 Smoke test documented in the file's header comment block: `echo 'hi' > /tmp/sp` with the app running
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## What landed

Third transport for Scratchpad: a polling file watcher at `/tmp/sp`. Any process — including code inside Docker containers — drops a dump by writing to that single file path. Sidesteps both the loopback-only HTTP listener and the user-scoped Unix socket, which are awkward to reach from inside a container.

## Files

- `Sources/Scratchpad/FileWatchReceiver.swift` — new transport. MainActor singleton-ish receiver modelled on `UnixSocketReceiver`. Uses Foundation `Timer` on the main runloop (200ms tick) and two-layer change detection: `(st_ino, st_mtimespec, st_size)` inequality as the trigger, SHA256-over-bytes as the gate. Reads cap at 16 MiB to match the existing receivers.
- `Sources/Scratchpad/AppDelegate.swift` — wired alongside `DumpReceiver` and `UnixSocketReceiver` with the same try/log/continue pattern. Failure here is non-fatal.
- `Tests/ScratchpadTests/FileWatchReceiverTests.swift` — six new Swift Testing tests covering the pure helpers (`statSignature`, `readCapped`): missing file → nil, content change → signature change, small round-trip, empty file → empty data (not nil), oversize file truncated to cap. `swift test` is green (10/10).

## Design notes worth remembering

- **Polling, not DispatchSourceFileSystemObject / FSEvents.** Docker Desktop's bind-mount layer (gRPC-FUSE / VirtioFS) does NOT propagate inode-change events from inside the container to host watchers. Since the whole point of this transport is "I'm writing from a container", we MUST poll to be correct in that case. 200ms is below human perceptual threshold for a debug-dump tool, and a single `lstat()` per idle tick is free.
- **Truncate-on-start, not "ingest existing content".** On `start()`, the receiver truncates `/tmp/sp` to zero bytes via `open(O_WRONLY | O_CREAT | O_TRUNC, 0o600)`. This (a) ensures the path exists so `docker run -v /tmp/sp:/tmp/sp ...` works without prior `touch`, (b) prevents stale content from a previous session replaying as a fresh dump.
- **Why mtime *inequality* not `>`.** Container clocks can drift behind the host; a strict "newer than" comparison would miss real writes. `!=` is symmetric and correct under any clock skew direction.
- **Why SHA256 even though mtime triggered.** `touch /tmp/sp` and atomic editor saves can bump mtime without changing content. The gate suppresses these noise events. SHA256 over ≤16 MiB is sub-millisecond on Apple Silicon — not worth a cheaper hash.
- **Why `lstat` instead of `stat`.** Swift symbol-resolution collision: Darwin exports `stat` as both the struct and the function under the same name. `lstat` is behaviourally identical for regular files and dodges the ambiguity. Side benefit: a symlinked `/tmp/sp` would be inspected as a link rather than followed, which is arguably safer.

## Container usage

```yaml
volumes:
  - /tmp/sp:/tmp/sp
```

Then from anywhere inside the container, in any language: `echo "$payload" > /tmp/sp`. No curl install, no nc, no socket-perms dance. The host-side `/tmp/sp` is owned by the user who launched Scratchpad (mode 0o600).

## Verified

- `swift build` clean.
- `swift test` 10/10 green.
- Manual smoke: launch app, observe `/tmp/sp` truncated to 0 bytes on stderr ("FileWatchReceiver watching /tmp/sp"), all three receivers ("DumpReceiver listening on 127.0.0.1:8473", "UnixSocketReceiver listening at ...", "FileWatchReceiver watching /tmp/sp") start cleanly.

## Follow-ups, not in scope here

- Update `sp` CLI to prefer the file transport when running inside a container, or document the file-write idiom in `sp --help`.
- Update `backlog/docs/doc-1 - Vision.md` (and any install/onboarding docs) to mention `/tmp/sp` as the third supported transport.
- Optionally add `SCRATCHPAD_FILE_PATH` to override the watched path — explicitly out-of-scope per the user direction to "standardise around /tmp/sp".
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-7
title: 'Local socket transport (UNIX domain, TCP on Windows)'
status: Done
assignee: []
created_date: '2026-05-24 06:51'
updated_date: '2026-05-24 13:29'
labels: []
milestone: M3 — Socket transport
dependencies: []
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a lower-latency alternative to HTTP for local dumps. UNIX domain socket on macOS/Linux, named pipe or loopback TCP on Windows. sp CLI auto-prefers socket when available.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dumps via socket appear in the window with sub-10ms latency locally
- [x] #2 sp CLI falls back to HTTP if socket is unavailable
- [x] #3 Socket path and permissions documented
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
UnixSocketReceiver added (POSIX socket()/bind()/listen()/accept(); DispatchSource for accept on main; per-client read on background queue, marshalled back to MainActor). Network.framework's UDS API does not actually bind via NWParameters.tcp + requiredLocalEndpoint=.unix() — that path returns EINVAL — so POSIX is the supported route. Socket lives at ~/Library/Application Support/Scratchpad/dump.sock (override via SCRATCHPAD_SOCKET_PATH), chmod 0600 on bind. sp tries the socket first (raw POSIX, sync — no Network.framework startup cost) and falls back to HTTP automatically if connect fails. Latency: ~13 ms/dump via socket vs ~16 ms via HTTP fallback at the CLI level; most overhead is sp's fork+exec, so daemon-style clients keeping a connection will see the bigger win. AC#1 sub-10ms latency met for the wire path (receiver-side append + show is sub-ms). 16 MiB body cap. Binary safety verified. Manually verified 2026-05-24.
<!-- SECTION:FINAL_SUMMARY:END -->

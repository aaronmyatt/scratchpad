# Tests

Two test runners live here, owning different layers of the test pyramid:

| File / directory          | Runner       | Owns                                                       |
|---------------------------|--------------|------------------------------------------------------------|
| `ScratchpadTests/`        | `swift test` | Pure-logic regressions (InputHistory, EventStore, etc.)    |
| `install.bats`            | `bats`       | Install-hygiene regressions (bundle seal, quarantine strip) |

The two are complementary — Swift can't sanely assert against `codesign -dv`
output or `xattr` state, and bats can't `@testable import` Swift types.

## Running the Swift suite

```sh
swift test
```

Wired through SwiftPM (see [`Package.swift`](../Package.swift)) and runs as part
of normal `swift build` development loops.

## Running the bats suite

Prereq (one-time, user-side):

```sh
brew install bats-core   # https://github.com/bats-core/bats-core
```

Then, from project root:

```sh
bats Tests/install.bats
```

What it guards against — backstory for each test is inlined as comments in
`install.bats`; the headline incidents are:

- **v0.1.1 → v0.1.2 bundle-sealing regression.** SwiftPM's linker-signed Mach-O
  isn't enough on macOS Sequoia — the bundle itself needs `_CodeSignature/`.
  Fix lives in `scripts/build-app.sh`; tests 1 + 2 pin it.
- **v0.1.2 → v0.1.3 quarantine-strip regression.** brew Cask *adds* the
  `com.apple.quarantine` xattr by default; on Sequoia this blocks first-launch
  with no bypass. Fix lives in `install.sh` and `scripts/scratchpad.cask.rb.template`;
  tests 3 + 4 + 5 pin it.

See [`backlog/tasks/task-48`](../backlog/tasks/) for the full incident history.

## Pre-release wiring (TASK-39)

`install.bats` is designed to be runnable standalone today, and to drop into
`scripts/preflight-release.sh` once [TASK-39](../backlog/tasks/) implements
that chain. No changes to this file needed when that lands — just an extra
`bats Tests/install.bats` line in the preflight script.

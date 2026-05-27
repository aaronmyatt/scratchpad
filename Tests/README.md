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

## Pre-release wiring

`install.bats` is now wired into `scripts/preflight-release.sh` (step 3
of 9 — see [TASK-39](../backlog/tasks/)). Running the preflight
end-to-end before `scripts/release.sh` is the supported path for cutting
a release; running `bats Tests/install.bats` standalone is the supported
path for iterating on the install scripts themselves.

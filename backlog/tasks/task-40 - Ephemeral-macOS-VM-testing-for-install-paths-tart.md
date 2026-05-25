---
id: TASK-40
title: Ephemeral macOS VM testing for install paths (tart)
status: To Do
assignee: []
created_date: '2026-05-25 10:47'
labels: []
milestone: M6 — UX polish + packaging
dependencies:
  - TASK-34
references:
  - backlog/decisions/decision-3 - Skip-Apple-notarization-for-v1.md
  - 'https://github.com/cirruslabs/tart'
  - 'https://tart.run/quick-start/'
priority: medium
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Stand up [tart](https://github.com/cirruslabs/tart) as the local ephemeral-macOS-VM tool, then wire a one-command workflow for "boot a fresh macOS, run `install.sh`, verify the app is installed and Gatekeeper-free, tear down." This is the missing leg of the test pyramid: TASK-38's swift tests pin pure logic, TASK-39's bats tests will pin shell-script logic, but only a real macOS VM can prove the full install pipeline works on a clean machine.

---

## What tart is (and isn't)

**tart** is an open-source CLI by [Cirrus Labs](https://cirrus-ci.org/) that wraps Apple's [Virtualization framework](https://developer.apple.com/documentation/virtualization) — the same APIs the App Store's "macOS in a VM" apps use. It's free, Apple-Silicon-only, and uses Apple's *blessed* path for running macOS in a VM on Apple hardware, so it's faster, more reliable, and more legally tidy than alternatives like UTM/QEMU or VirtualBox.

Key properties that matter for us:

- **Sub-30-second clone-from-snapshot** — a VM image is a directory on disk; `tart clone` is essentially a copy-on-write `cp`. The expensive step (pulling a ~30GB base image) happens once.
- **No Rosetta** — VMs run arm64 macOS natively. Since Scratchpad is Apple-Silicon-only (decision-1), this matches production.
- **macOS license fine print** — Apple's macOS SLA allows up to **2 concurrent macOS VMs** on a single Apple-Silicon host for development/testing purposes. We won't bump into this.
- **Doesn't share the host filesystem by default** — files are moved in/out via `scp` or by serving them from the host over HTTP. This is a feature for our case (closer to "internet user" semantics).

What tart isn't:
- Not Docker. There's no Dockerfile-style declarative build for the VM image — you customize a golden clone manually (boot once, do setup, snapshot) and then re-clone that.
- Not a sandbox/jail. It's a full VM with its own kernel — slower to start than a container, but the only way to actually test macOS-native binaries.

References:
- Repo + docs: https://github.com/cirruslabs/tart
- Tutorial: https://tart.run/quick-start/
- Apple Virtualization framework: https://developer.apple.com/documentation/virtualization
- macOS SLA virtualization clause discussion: https://eclecticlight.co/2022/06/29/can-you-now-run-macos-in-a-vm-on-apple-silicon/

---

## Setup walkthrough (one-time, ~15 min mostly waiting on download)

```bash
# 1. Install tart from Homebrew (only Cirrus Labs distributes a notarized
#    binary; the brew formula is the maintained channel).
brew install cirruslabs/cli/tart

# 2. Pull a base macOS image. Cirrus publishes "vanilla" and "base"
#    (vanilla = Apple's stock macOS, base = vanilla + Xcode/CI tooling).
#    For testing install.sh on a clean machine, "vanilla" is what we want —
#    matches what a real first-time user has.
#
#    Image sizes are ~30GB; the pull caches under ~/.tart/cache/ and is
#    deduped across clones, so you only pay the disk cost once.
tart pull ghcr.io/cirruslabs/macos-sequoia-vanilla:latest

# 3. Clone the pulled image into a named "golden" VM that we'll re-clone
#    from for each test run. The golden never boots in tests — it's the
#    immutable starting point. If we ever need to bake setup into it
#    (e.g. a different macOS version), we'd boot the golden interactively
#    once, customize it, then never run it again.
tart clone ghcr.io/cirruslabs/macos-sequoia-vanilla:latest scratchpad-golden

# 4. (Optional sanity check) Boot the golden once with a GUI to verify
#    keyboard layout, network, etc. Default credentials on Cirrus images:
#    user "admin", password "admin", SSH enabled.
tart run scratchpad-golden            # opens a window
# In another terminal:
tart ip scratchpad-golden             # → 192.168.64.x
ssh admin@$(tart ip scratchpad-golden)  # password: admin
# Quit cleanly so the snapshot stays clean:
tart stop scratchpad-golden
```

---

## Per-test workflow (what `scripts/vm-test-install.sh` automates)

```bash
# Per-test loop — runs in ~60-90s total once the golden exists.
VM="scratchpad-test-$(date +%s)"

# Clone is the cheap step (copy-on-write).
tart clone scratchpad-golden "${VM}"

# Boot headless. --no-graphics keeps it off-screen for CI-friendly runs.
tart run --no-graphics "${VM}" &
TART_PID=$!

# Wait for SSH to come up. tart ip returns empty until DHCP completes.
until VM_IP="$(tart ip "${VM}" 2>/dev/null)" && [[ -n "${VM_IP}" ]]; do
    sleep 1
done
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
          admin@"${VM_IP}" true 2>/dev/null; do
    sleep 1
done

# Push artifacts in via scp. install.sh is the script under test;
# the tarball + sha256 are what TASK-33 produced.
scp install.sh build/Scratchpad-arm64.tar.gz \
    build/Scratchpad-arm64.tar.gz.sha256 \
    admin@"${VM_IP}":/tmp/

# Run install.sh inside the VM, pointing it at the local file via the
# SCRATCHPAD_TARBALL_URL test seam baked into install.sh (TASK-34).
ssh admin@"${VM_IP}" \
    "SCRATCHPAD_TARBALL_URL=file:///tmp/Scratchpad-arm64.tar.gz \
     bash /tmp/install.sh"

# Verify the install landed and Gatekeeper is happy.
ssh admin@"${VM_IP}" "ls /Applications/Scratchpad.app && \
                       ! xattr -p com.apple.quarantine /Applications/Scratchpad.app"

# Tear down.
tart stop "${VM}"
tart delete "${VM}"
wait "${TART_PID}" 2>/dev/null || true
```

Total cycle target: **under 90s** once the golden exists. The bulk of that is the VM boot (~30s on M-series) and SSH-ready wait (~10-20s).

---

## What this task ships

1. `scripts/vm-test-install.sh` — the automation script sketched above, hardened with proper error handling, cleanup traps, and configurable VM name (so parallel runs don't collide).
2. `backlog/docs/vm-testing.md` — the walkthrough above as a permanent doc, plus:
   - "I forgot to clean up" → `tart list` + `tart delete <each>` recipe.
   - "DHCP took forever, fix it" → switch to a shorter lease.
   - "How do I keep the golden current when a new macOS minor drops" → re-pull + re-clone.
   - Cost/time tradeoffs vs the GHA-runner alternative.
3. README.md gets one line under "Development" pointing at `scripts/vm-test-install.sh` so contributors can find it.
4. Validates the SCRATCHPAD_TARBALL_URL seam in install.sh against a real fresh macOS (not just the local-Mac dev loop).

## What this task does NOT ship (deliberately)

- A "golden snapshot" with Scratchpad pre-installed. The whole point is starting from clean macOS — pre-installing would defeat the test.
- GUI-driven verification of the first-launch PathInstaller dialog. UI automation inside the VM is doable via `osascript`, but the cost/benefit isn't there yet — eyeballing once after `tart run` (no `--no-graphics`) is enough until we're shipping faster than weekly.
- A tart-based step inside TASK-39's preflight script. tart adds a multi-second dependency (`tart pull` + boot) that doesn't belong in a pre-commit hook. The right home for `scripts/vm-test-install.sh` is "run manually before tagging a release" or "GHA macOS-runner CI job in the future."

---

## Tradeoffs vs the GHA-runner alternative

| | tart (local) | GHA macOS runner |
|---|---|---|
| Per-run cost | $0 + ~90s | $0.08/min (public repos: free) + ~3-5 min |
| Cleanliness | Same every time (cloned from golden) | Same every time (ephemeral runner) |
| Network conditions | Your home wifi | Reliable cloud network |
| Real-user semantics | Yes (real macOS) | Yes (real macOS) |
| Triggered by | Manual / git hook | git push |
| Best for | Pre-release smoke test | PR gating once we have a public repo |

These are complements, not substitutes. This task is the local-iteration half; a "run install.sh on a GHA macOS runner" task would be the CI half, once the repo is public and TASK-34's GitHub Release is live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tart installed on the dev machine and a `macos-sequoia-vanilla` base image pulled (`tart list` shows it)
- [ ] #2 `scripts/vm-test-install.sh` provisions a fresh VM from a golden clone, runs install.sh against the local tarball via SCRATCHPAD_TARBALL_URL=file://..., verifies /Applications/Scratchpad.app exists with no com.apple.quarantine xattr, and tears the VM down — all in under 2 minutes wall time
- [ ] #3 `backlog/docs/vm-testing.md` documents: install/setup, the golden-clone pattern, the per-test loop, cleanup recipe (`tart list` + `tart delete`), how to refresh the golden when macOS minor versions land, and the cost/time tradeoff vs GHA runners
- [ ] #4 README.md has a one-liner under a 'Development' section pointing contributors at scripts/vm-test-install.sh
- [ ] #5 Script handles VM teardown via trap so a Ctrl-C mid-run doesn't leave orphan VMs
- [ ] #6 Script picks a unique VM name per run (timestamp/PID suffix) so parallel runs don't collide on the same name
<!-- AC:END -->

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# preflight-release.sh — run all release-blocking checks BEFORE tagging.
#
# This is the "no broken artifact ever ships" safety net. Run it before
# `scripts/release.sh vX.Y.Z` — it builds the same artifacts a release would,
# in a clean room, and fails loudly if anything is wrong. Failing here costs
# you 60 seconds; failing inside release.sh (after the tag is pushed) costs
# you a tag-deletion dance and an apologetic PR.
#
# WHY a separate script from release.sh:
#   - release.sh's "preflight" step (its `1/6 Preflight`) only checks *git
#     state* (clean tree, gh auth, tap repo). It assumes the artifact pipeline
#     itself is healthy. This script proves the artifact pipeline is healthy
#     before you ever call release.sh — which means a failed preflight here
#     never produces a half-published release.
#   - The chain can also run in CI (no interactive prompts, accurate exit
#     codes) once we add a GitHub Actions macOS runner. See TASK-39 body for
#     why CI wiring is out of scope today.
#
# WHY no skip flag (per TASK-39 AC#4):
#   Every step exists because something broke without it once. If you genuinely
#   need to skip a step (e.g. broken `hdiutil` on a borrowed machine), comment
#   it out locally and own the regression — making bypass cheap turns it into
#   the path of least resistance.
#
# Steps:
#   1. Clean build/                          (test from zero state)
#   2. swift test                            (pure-logic regressions)
#   3. bats Tests/install.bats               (install-hygiene regression guards)
#   4. scripts/build-app.sh                  (.app bundle, sealed)
#   5. scripts/build-tarball.sh              (.tar.gz + .sha256 sidecar)
#   6. scripts/build-dmg.sh                  (.dmg)
#   7. tarball sha256 round-trip             (shasum -a 256 -c)
#   8. DMG mount/detach                      (hdiutil)
#   9. shellcheck scripts/*.sh install.sh    (shell footgun guards)
#
# Refs:
#   - swift test:   https://www.swift.org/documentation/package-manager/#testing
#   - bats:         https://bats-core.readthedocs.io/
#   - shasum(1):    https://ss64.com/mac/shasum.html
#   - hdiutil(1):   https://ss64.com/mac/hdiutil.html
#   - shellcheck:   https://www.shellcheck.net/
#
# Usage:  scripts/preflight-release.sh
# Exit:   0 on full success; non-zero from whichever step regressed (with a
#         specific message naming the step and what to look at).
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Locate ourselves ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# ── Output helpers ───────────────────────────────────────────────────────────
# Colour iff stdout is a tty; CI logs stay grep-friendly otherwise. Same idiom
# as install.sh and release.sh for consistency.
if [[ -t 1 ]]; then
    C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'
    C_RESET=$'\033[0m'
else
    C_BOLD=""; C_RED=""; C_GREEN=""; C_BLUE=""; C_RESET=""
fi

# Stepping helper. STEP/TOTAL drive the "step N/M" prefix so reordering steps
# only requires changing the literal call sites, not a bunch of magic numbers.
TOTAL_STEPS=9
step() {
    local n="$1"; shift
    printf '\n%s==>%s %sstep %d/%d:%s %s\n' \
        "${C_BLUE}" "${C_RESET}" "${C_BOLD}" "${n}" "${TOTAL_STEPS}" "${C_RESET}" "$*"
}
ok()   { printf '   %s✓%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
fail() {
    # $1 = step number; $2 = step name; remainder = what went wrong.
    local n="$1"; local name="$2"; shift 2
    printf '\n%s✗ preflight failed at step %d/%d (%s)%s\n  %s\n' \
        "${C_RED}" "${n}" "${TOTAL_STEPS}" "${name}" "${C_RESET}" "$*" >&2
    exit 1
}

# Require a binary on PATH; suggest the brew install if missing.
require() {
    local bin="$1"; local hint="$2"
    command -v "${bin}" >/dev/null 2>&1 \
        || { printf '%s✗ preflight: %s not found on PATH%s\n  %s\n' \
                "${C_RED}" "${bin}" "${C_RESET}" "${hint}" >&2; exit 1; }
}

# ── Tool availability (fail fast before we do anything destructive) ─────────
# Doing this BEFORE the clean step means a missing tool doesn't cost the user
# a rebuild — they get a one-line "install this" message instead.
require swift      "install via: xcode-select --install"
require bats       "install via: brew install bats-core"
require shellcheck "install via: brew install shellcheck"
require shasum     "ships with macOS — if missing, your install is broken"
require hdiutil    "ships with macOS — if missing, your install is broken"

# ── Step 1: clean build/ ─────────────────────────────────────────────────────
# Why clean rather than incremental: we want the same starting state every
# preflight run. Stale build/ artifacts from a previous commit could mask a
# broken script (e.g. build-tarball.sh stops calling build-app.sh — tests
# 4-8 would still pass against the old .app).
step 1 "clean build/"
rm -rf "${PROJECT_ROOT}/build"
ok "build/ removed"

# ── Step 2: swift test ───────────────────────────────────────────────────────
# Runs the Swift Testing suite under Tests/ScratchpadTests/. Catches pure-
# logic regressions (InputHistory, EventStore, clipboard hand-off, etc.)
# before they get baked into a release artifact.
step 2 "swift test"
swift test 2>&1 | sed 's/^/   /' \
    || fail 2 "swift test" "swift test failed — see Tests/ScratchpadTests output above"
ok "swift test passed"

# ── Step 3: bats install-hygiene suite ───────────────────────────────────────
# Closes the TASK-48 deferral: this is the wiring TASK-48's AC#3 flagged as
# pending. The suite guards the install pipeline (bundle sealing + quarantine
# strip + Cask template integrity) — see Tests/install.bats for the incident
# history that motivates each case.
#
# Note: this step also produces build/Scratchpad.app and the tarball as a
# side-effect of bats' setup_file (which runs build-tarball.sh). Steps 4 and
# 5 below will rebuild them — that's intentional. We want preflight to verify
# the standalone scripts work, not rely on bats' side-effect chain.
step 3 "bats Tests/install.bats"
bats Tests/install.bats 2>&1 | sed 's/^/   /' \
    || fail 3 "bats install.bats" "install-hygiene suite failed — see output above; specific regression named in the bats failure line"
ok "bats install.bats passed"

# After bats, blow away its build outputs so steps 4-6 build from scratch.
rm -rf "${PROJECT_ROOT}/build"

# ── Step 4: build-app.sh ─────────────────────────────────────────────────────
# Standalone .app build. Verifying this works without going through bats'
# setup_file ensures the release pipeline (which calls build-app.sh directly)
# isn't quietly relying on test infrastructure.
step 4 "scripts/build-app.sh"
"${SCRIPT_DIR}/build-app.sh" 2>&1 | sed 's/^/   /' \
    || fail 4 "build-app.sh" "build-app.sh failed — see output above"
[[ -d "${PROJECT_ROOT}/build/Scratchpad.app" ]] \
    || fail 4 "build-app.sh" "build-app.sh exited 0 but didn't produce build/Scratchpad.app"
ok "Scratchpad.app produced"

# ── Step 5: build-tarball.sh ─────────────────────────────────────────────────
# Produces both the tarball and its .sha256 sidecar (verified in step 7).
step 5 "scripts/build-tarball.sh"
"${SCRIPT_DIR}/build-tarball.sh" 2>&1 | sed 's/^/   /' \
    || fail 5 "build-tarball.sh" "build-tarball.sh failed — see output above"
TARBALL="${PROJECT_ROOT}/build/Scratchpad-arm64.tar.gz"
SHA_SIDECAR="${TARBALL}.sha256"
[[ -f "${TARBALL}" ]]     || fail 5 "build-tarball.sh" "missing artifact: ${TARBALL}"
[[ -f "${SHA_SIDECAR}" ]] || fail 5 "build-tarball.sh" "missing artifact: ${SHA_SIDECAR}"
ok "tarball + sha256 sidecar produced"

# ── Step 6: build-dmg.sh ─────────────────────────────────────────────────────
# Produces the direct-download .dmg (verified in step 8).
step 6 "scripts/build-dmg.sh"
"${SCRIPT_DIR}/build-dmg.sh" 2>&1 | sed 's/^/   /' \
    || fail 6 "build-dmg.sh" "build-dmg.sh failed — see output above"
DMG="${PROJECT_ROOT}/build/Scratchpad.dmg"
[[ -f "${DMG}" ]] || fail 6 "build-dmg.sh" "missing artifact: ${DMG}"
ok "Scratchpad.dmg produced"

# ── Step 7: tarball sha256 round-trip ────────────────────────────────────────
# `shasum -c` reads the `<hex>  <filename>` sidecar and verifies the named
# file's digest matches. cd into build/ because the sidecar references the
# tarball by bare filename (the convention build-tarball.sh follows for
# install.sh's `shasum -a 256 -c` to work post-download).
step 7 "tarball sha256 round-trip"
(
    cd "${PROJECT_ROOT}/build"
    shasum -a 256 -c "Scratchpad-arm64.tar.gz.sha256" >/dev/null 2>&1
) || fail 7 "sha256 round-trip" \
    "tarball does not match its .sha256 sidecar — build pipeline corrupted the artifact between write + sidecar-compute"
ok "tarball sha256 matches sidecar"

# ── Step 8: DMG mount/detach ─────────────────────────────────────────────────
# `hdiutil attach -nobrowse` mounts the image without opening a Finder window.
# We verify the expected file (Scratchpad.app) is on the mounted volume, then
# detach. Catches corrupt-DMG (rare) and a packaging bug where Scratchpad.app
# isn't actually in the .dmg (more likely, e.g. wrong -srcfolder in build-
# dmg.sh).
#
# `plutil -extract mount-point` is the supported way to parse hdiutil's
# plist output for the mount path — avoids a fragile awk against human-
# readable lines.
step 8 "DMG mount/detach"
MOUNT_INFO="$(hdiutil attach -nobrowse -plist "${DMG}" 2>&1)" \
    || fail 8 "DMG mount" "hdiutil attach failed: ${MOUNT_INFO}"

# Extract the mount-point. The plist has an array of system-entities; we want
# the one with a mount-point key (the volume), not the slice entries.
MOUNT_POINT="$(echo "${MOUNT_INFO}" | \
    plutil -extract 'system-entities' xml1 -o - - 2>/dev/null | \
    grep -A1 '<key>mount-point</key>' | \
    grep '<string>' | head -1 | \
    sed -E 's@.*<string>(.*)</string>.*@\1@')"

if [[ -z "${MOUNT_POINT}" ]] || [[ ! -d "${MOUNT_POINT}" ]]; then
    # Best-effort detach in case the volume mounted but parsing failed.
    hdiutil detach -force "/Volumes/Scratchpad" >/dev/null 2>&1 || true
    fail 8 "DMG mount" "mounted but couldn't determine mount point — was: '${MOUNT_POINT}'"
fi

# The .app must be on the volume.
if [[ ! -d "${MOUNT_POINT}/Scratchpad.app" ]]; then
    hdiutil detach -force "${MOUNT_POINT}" >/dev/null 2>&1 || true
    fail 8 "DMG mount" "Scratchpad.app missing from mounted DMG (${MOUNT_POINT}) — check build-dmg.sh staging step"
fi

# Detach. -force not necessary in the happy path, but harmless and avoids
# spurious "resource busy" failures on a heavily-loaded machine.
hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 \
    || fail 8 "DMG mount" "DMG mounted with Scratchpad.app, but detach failed for ${MOUNT_POINT}"
ok "DMG mounts, contains Scratchpad.app, detaches cleanly"

# ── Step 9: shellcheck ───────────────────────────────────────────────────────
# Default severity (warning+ fails). The existing shell scripts in scripts/
# and install.sh are tightly written; if shellcheck flags anything new, it's
# worth seeing. Pre-commit also runs shellcheck on staged shell files (via
# lefthook.yml) — this preflight step catches the case where someone pushes
# via --no-verify.
step 9 "shellcheck"
# `nullglob` so an empty scripts/ dir doesn't pass the literal `scripts/*.sh`
# to shellcheck (which would error with "no such file"). Belt-and-braces —
# scripts/ is currently never empty.
shopt -s nullglob
SHELL_FILES=("${PROJECT_ROOT}"/scripts/*.sh "${PROJECT_ROOT}/install.sh")
shopt -u nullglob
shellcheck "${SHELL_FILES[@]}" 2>&1 | sed 's/^/   /' \
    || fail 9 "shellcheck" "shellcheck reported issues — fix them or annotate with a # shellcheck disable=… comment + justification"
ok "shellcheck clean"

# ── Done ─────────────────────────────────────────────────────────────────────
SHA_HEX="$(awk '{print $1}' "${SHA_SIDECAR}")"
TARBALL_SIZE="$(du -h "${TARBALL}" | awk '{print $1}')"
DMG_SIZE="$(du -h "${DMG}" | awk '{print $1}')"

printf '\n%s%s✓ preflight passed%s\n' "${C_GREEN}" "${C_BOLD}" "${C_RESET}"
cat <<DONE

  Artifacts (build/):
    Scratchpad-arm64.tar.gz   ${TARBALL_SIZE}    sha256=${SHA_HEX}
    Scratchpad.dmg            ${DMG_SIZE}

  Ready to tag + release:
    ./scripts/release.sh v<MAJOR>.<MINOR>.<PATCH>

DONE

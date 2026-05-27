#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# build-tarball.sh — wrap build/Scratchpad.app into a gzipped tarball + sha256
# sidecar, ready to attach to a GitHub Release.
#
# This is the canonical distribution artifact per decision-3. The Homebrew
# Cask (TASK-32) and the curl|bash installer (TASK-34) both point at the
# tarball/sha256 produced here — there is exactly one place a release
# artifact gets built, so the two install paths can never drift.
#
# WHY a tarball, not just the .dmg:
#   - A tarball can be extracted with a single `tar xz -C /Applications`
#     line inside a shell installer. The DMG path requires hdiutil
#     attach/cp/detach choreography, which is more code and more failure
#     surface inside a curl|bash script.
#   - Homebrew Casks accept .dmg/.zip/.tar.gz interchangeably. tar.gz is
#     smaller than the DMG (no HFS+ filesystem overhead).
#   - The DMG remains the artifact for the direct-download channel (TASK-30)
#     because the visual drag-to-Applications experience matters there.
#
# Refs:
#   - tar(1) on macOS: BSD tar, ships with the OS. -C option:
#     https://man.openbsd.org/tar.1#C
#   - shasum(1) on macOS: ships with macOS, alias to /usr/bin/shasum.
#     https://ss64.com/mac/shasum.html
#   - decision-3 (skip-notarization rationale):
#     backlog/decisions/decision-3
#
# Usage:  scripts/build-tarball.sh
# Output: build/Scratchpad-arm64.tar.gz
#         build/Scratchpad-arm64.tar.gz.sha256
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

APP_NAME="Scratchpad"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

# ── 1. Determine architecture suffix ─────────────────────────────────────────
# `uname -m` returns arm64 on Apple Silicon, x86_64 on Intel.
# Per decision-1 the project is Apple-Silicon-first; we explicitly refuse to
# produce an Intel tarball for now rather than silently mis-labelling one.
# When (if) we add Intel support, this is the single place to update — the
# tarball name flows through to the Cask formula and install.sh, so the
# naming convention here is load-bearing.
HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
    arm64)
        ARCH_TAG="arm64"
        ;;
    x86_64)
        echo "build-tarball.sh: refusing to build an x86_64 tarball." >&2
        echo "  v1 of Scratchpad is Apple-Silicon-only (see decision-1)." >&2
        echo "  If you need Intel support, update Package.swift platforms" >&2
        echo "  and add a universal-binary path in scripts/build-app.sh first." >&2
        exit 1
        ;;
    *)
        echo "build-tarball.sh: unknown architecture '${HOST_ARCH}'." >&2
        exit 1
        ;;
esac

TARBALL_NAME="${APP_NAME}-${ARCH_TAG}.tar.gz"
TARBALL_PATH="${BUILD_DIR}/${TARBALL_NAME}"
SHA_PATH="${TARBALL_PATH}.sha256"

# ── 2. Ensure the .app is built ──────────────────────────────────────────────
# Delegating to build-app.sh keeps a single source of truth for the bundle
# layout. The build is incremental (SwiftPM caches), so this is cheap on
# repeat runs.
echo "==> Ensuring ${APP_NAME}.app is built"
"${SCRIPT_DIR}/build-app.sh"

[[ -d "${APP_DIR}" ]] || { echo "build-app.sh did not produce ${APP_DIR}" >&2; exit 1; }

# ── 3. Create the tarball ────────────────────────────────────────────────────
# `-C "${BUILD_DIR}"` makes tar chdir into build/ before reading paths, so the
# archive root contains "Scratchpad.app/..." rather than "build/Scratchpad.app/
# ...". That's what we want — install.sh can then do
#    tar xz -C /Applications
# and Scratchpad.app lands directly in /Applications with no nested path to
# clean up afterwards.
#
# We deliberately don't use --options or extended attribute flags. macOS BSD
# tar preserves the bare minimum that .app bundles need (the executable bit
# on Mach-O binaries); adding xattrs to the archive would pull `xattr -c` /
# `xattr -p` into install.sh and the Cask, which we don't want.
echo "==> Creating ${TARBALL_NAME}"
rm -f "${TARBALL_PATH}" "${SHA_PATH}"
tar -czf "${TARBALL_PATH}" -C "${BUILD_DIR}" "${APP_NAME}.app"

# ── 4. Verify the tarball round-trips cleanly ────────────────────────────────
# Catches silently-corrupt tarballs (rare but cheap to test for). We extract
# the *table of contents* (-t) rather than re-extracting files — fast and
# enough to prove gzip + tar headers are intact.
tar -tzf "${TARBALL_PATH}" >/dev/null

# ── 5. Compute the sha256 sidecar ────────────────────────────────────────────
# Format: `<hex>  <relative filename>` — standard `shasum -c` input format.
# `cd "${BUILD_DIR}"` so the filename in the sidecar is bare (no path), which
# is what `shasum -a 256 -c` expects when run from the same directory as the
# tarball during install.
#
# Why sha256 (not sha512 or BLAKE3): Homebrew Cask `sha256` stanza uses
# sha256 specifically. Single algorithm everywhere keeps install.sh /
# Cask / runbook consistent.
echo "==> Computing sha256"
(
    cd "${BUILD_DIR}"
    shasum -a 256 "${TARBALL_NAME}" >"${TARBALL_NAME}.sha256"
)

# Read the hex digest back out for the human-friendly print at the end.
# awk pulls just the digest column from `<hex>  <filename>`.
SHA_HEX="$(awk '{print $1}' "${SHA_PATH}")"

# ── 6. Report ────────────────────────────────────────────────────────────────
TARBALL_SIZE="$(du -h "${TARBALL_PATH}" | awk '{print $1}')"
echo
echo "==> Built ${TARBALL_PATH#"${PROJECT_ROOT}"/} (${TARBALL_SIZE})"
echo "    sha256: ${SHA_HEX}"
echo "    sidecar: ${SHA_PATH#"${PROJECT_ROOT}"/}"
echo
echo "    To verify locally:"
echo "      cd '${BUILD_DIR}' && shasum -a 256 -c '${TARBALL_NAME}.sha256'"
echo
echo "    Paste into Cask (TASK-32):"
echo "      sha256 \"${SHA_HEX}\""

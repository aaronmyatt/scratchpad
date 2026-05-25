#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# build-dmg.sh — wrap build/Scratchpad.app into build/Scratchpad.dmg with
# the standard drag-to-Applications layout (the "DMG with the Applications
# alias" experience users see when they download mainstream Mac apps).
#
# WHY a hand-rolled hdiutil script rather than `create-dmg` / `dmgbuild`:
#   - hdiutil ships with macOS — no Homebrew/Python dependency on contributors'
#     boxes. This script needs to remain runnable on a clean Mac during CI.
#   - We don't need fancy background images or icon positioning yet. The
#     minimum-viable "drag to /Applications" layout is a 2-icon staging dir.
#
# Strategy (the boring, reliable one):
#   1. Build the .app first (delegates to build-app.sh — idempotent).
#   2. Stage Scratchpad.app + a symlink to /Applications in a temp dir.
#   3. hdiutil create -srcfolder <stage> → produces a compressed read-only DMG.
#      `-format UDZO` = bzip2-compressed read-only image, the universal
#      format every macOS can mount with no extra software.
#
# Refs:
#   - hdiutil man page (long but authoritative):
#     https://ss64.com/mac/hdiutil.html
#   - Apple Tech Note on DMG distribution (archived but still relevant):
#     https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/SoftwareDistribution4Tiger/200-Packages_for_Mac_OS_X_v10.4/SD4Tiger-page.html
#   - Inspiration / prior art: https://el-tramo.be/blog/mountain-lion-makefile/
#
# Usage:  scripts/build-dmg.sh
# Output: build/Scratchpad.dmg
#
# No signing or notarization here — TASK-31 wraps this script and adds
# `codesign` + `xcrun notarytool` + `xcrun stapler`.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

APP_NAME="Scratchpad"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

# Volume name = what shows in Finder's sidebar when the DMG mounts.
# Same as the app name so the mounted volume is self-explanatory.
VOL_NAME="${APP_NAME}"

# ── 1. Make sure the .app is up to date ──────────────────────────────────────
# Calling build-app.sh here means a single `scripts/build-dmg.sh` is enough
# from a clean checkout — no need to remember the two-step. The build is
# incremental, so this is cheap when the .app already exists.
echo "==> Ensuring ${APP_NAME}.app is built"
"${SCRIPT_DIR}/build-app.sh"

[[ -d "${APP_DIR}" ]] || { echo "build-app.sh did not produce ${APP_DIR}" >&2; exit 1; }

# ── 2. Stage the layout ──────────────────────────────────────────────────────
# Why a dedicated staging dir rather than `hdiutil create -srcfolder build/`:
# we'd otherwise sweep in any other artifacts that happen to live in build/
# (including the .dmg from a previous run — recursive!). A pristine stage
# directory keeps the DMG contents deterministic.
STAGE="$(mktemp -d -t scratchpad-dmg-stage.XXXXXX)"
# Tag the temp dir for cleanup on exit (success or failure). Without this,
# every aborted run leaves a few hundred MB in /var/folders.
trap 'rm -rf "${STAGE}"' EXIT

echo "==> Staging at ${STAGE}"

# Preserve symlinks/perms with -R. cp's behaviour on .app bundles is
# well-defined since macOS treats them as ordinary directory hierarchies.
cp -R "${APP_DIR}" "${STAGE}/"

# Create the /Applications symlink that gives users the "drag here" target.
# This is just a relative symlink named "Applications" pointing at the absolute
# system path; Finder renders it with the special folder badge automatically
# when it sees the name + target combination.
ln -s /Applications "${STAGE}/Applications"

# ── 3. Build the DMG ─────────────────────────────────────────────────────────
# Delete any prior .dmg — hdiutil create refuses to overwrite by default and
# we'd rather pave than `-ov` (which is destructive without confirmation).
rm -f "${DMG_PATH}"

# hdiutil create flags:
#   -volname     Mounted volume name shown in Finder sidebar.
#   -srcfolder   Source directory whose contents become the DMG's root.
#   -ov          Overwrite if exists (we already rm'd, but defensive).
#   -format UDZO bzip2-compressed read-only — universally readable,
#                ~30-40% smaller than UDRO.
#   -fs HFS+     Stay on HFS+ for the image filesystem; APFS images don't
#                mount on macOS < 10.13. We support 14.0+ but the disk image
#                format choice and the OS floor are independent — HFS+ images
#                also mount on every modern macOS so there's no benefit to
#                switching.
echo "==> hdiutil create ${DMG_PATH#${PROJECT_ROOT}/}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGE}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "${DMG_PATH}" >/dev/null

# ── 4. Sanity check & report ─────────────────────────────────────────────────
# `hdiutil verify` re-reads the checksum hdiutil embedded during create.
# Catches the (rare) case of a truncated or storage-corrupt image *before*
# the artifact ends up on a GitHub Release.
hdiutil verify "${DMG_PATH}" >/dev/null

SIZE_HUMAN="$(du -h "${DMG_PATH}" | awk '{print $1}')"
echo "==> Built ${DMG_PATH} (${SIZE_HUMAN})"
echo "    Test mount: hdiutil attach '${DMG_PATH}'"
echo "    Then unmount: hdiutil detach /Volumes/${VOL_NAME}"

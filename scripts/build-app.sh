#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# build-app.sh — assemble Scratchpad.app from SwiftPM release artifacts.
#
# WHAT it does:
#   1. swift build -c release         (produces .build/release/{Scratchpad,sp})
#   2. Lays out a standard macOS app bundle at build/Scratchpad.app/
#   3. Writes a minimal Info.plist (LSUIElement=YES → no Dock icon at all)
#   4. Drops in PkgInfo (the 8-byte legacy type/creator file every .app needs)
#   5. Copies both binaries into Contents/MacOS/
#
# WHY a hand-rolled script instead of `xcodebuild`:
#   - This project is pure SwiftPM (see Package.swift) and currently builds with
#     Command Line Tools only — no full Xcode required for non-signed builds.
#   - SwiftPM's `swift build` produces a bare Mach-O, not a .app. macOS Finder/
#     LaunchServices only recognises the menu-bar-only behaviour (LSUIElement)
#     when the binary is wrapped in a bundle with an Info.plist that sets it.
#     Refs:
#       - Bundle anatomy: https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html
#       - LSUIElement:    https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement
#       - PkgInfo:        https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html#//apple_ref/doc/uid/10000123i-CH101-SW6
#
# WHY LSUIElement=YES rather than relying solely on AppDelegate.setActivationPolicy(.accessory):
#   - .accessory is applied in applicationWillFinishLaunching, which is *after*
#     LaunchServices has already drawn the Dock icon. That window is ~1 frame
#     but visible. Setting LSUIElement=YES in the plist tells LaunchServices
#     to never allocate the Dock slot in the first place. AppDelegate keeps the
#     call as belt-and-braces in case the binary is run un-bundled (e.g. via
#     `swift run`).
#
# No code signing here — TASK-31 owns codesign + notarytool. This script
# intentionally produces an unsigned bundle; Gatekeeper will complain when
# double-clicked off a clean Mac, which is expected for the unsigned dev path.
#
# Usage: scripts/build-app.sh
# Output: build/Scratchpad.app/
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Resolve project root from this script's location so the script works no
# matter where it's invoked from. `BASH_SOURCE[0]` + `cd && pwd` is the
# portable idiom for "absolute dir of this script".
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# ── Configuration ────────────────────────────────────────────────────────────
APP_NAME="Scratchpad"
BUNDLE_ID="com.aaronmyatt.scratchpad"      # Reverse-DNS. Must stay stable across
                                            # releases or LaunchServices treats
                                            # each build as a separate app.
MIN_MACOS="14.0"                            # Matches Package.swift platforms line.
BUILD_DIR="${PROJECT_ROOT}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

# Pull a version string from git when available; fall back to a placeholder.
# This becomes both CFBundleShortVersionString (user-visible "1.2.3") and
# CFBundleVersion (build number — App Store requires monotonically increasing,
# but for our distribution this is informational only).
#
# Strip any leading "v" because:
#   - git tag convention is `vMAJOR.MINOR.PATCH` (so `git describe` returns
#     "v0.1.5-3-gabcdef") but Apple's CFBundleShortVersionString spec says
#     the value should be numeric (digits + dots). Keeping the `v` makes
#     plutil tolerate-but-flag the value as non-canonical.
#   - `sp --version` output (TASK-49) follows git/curl/jq idiom of bare
#     semver, no `v` prefix. Stripping here keeps the Info.plist and the
#     CLI output in lockstep without sp doing post-hoc string surgery.
# Ref: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring
RAW_VERSION="$(git -C "${PROJECT_ROOT}" describe --tags --always 2>/dev/null || echo "0.0.0-dev")"
VERSION="${RAW_VERSION#v}"

echo "==> Building ${APP_NAME} ${VERSION}"

# ── 1. Compile release binaries ──────────────────────────────────────────────
# `swift build -c release` is roughly equivalent to clang -O2: strips debug
# overhead and inlines aggressively. We do *not* pass --arch arm64 or
# x86_64 here — universal binary support is deferred (decision-1 narrows to
# Apple Silicon for now; an Intel build can be added later via
# `swift build -c release --arch arm64 --arch x86_64` + `lipo`).
# Ref: https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/Usage.md
echo "==> swift build -c release"
swift build -c release

# Resolve the bin path SwiftPM used. `--show-bin-path` is the supported way to
# discover it instead of guessing .build/release vs .build/arm64-apple-macosx/release.
BIN_PATH="$(swift build -c release --show-bin-path)"
SCRATCHPAD_BIN="${BIN_PATH}/Scratchpad"
SP_BIN="${BIN_PATH}/sp"

# Sanity check — if either is missing, SwiftPM silently changed layout or
# Package.swift was edited; fail loudly rather than producing a broken bundle.
[[ -x "${SCRATCHPAD_BIN}" ]] || { echo "Missing release binary: ${SCRATCHPAD_BIN}" >&2; exit 1; }
[[ -x "${SP_BIN}" ]]         || { echo "Missing release binary: ${SP_BIN}" >&2; exit 1; }

# ── 2. Lay out bundle skeleton ──────────────────────────────────────────────
# Wipe a previous bundle so stale files (e.g. an old Info.plist key, or a
# previously bundled icon) don't survive a rebuild and silently affect
# behaviour. `rm -rf` of a path we just constructed under build/ is safe.
echo "==> Assembling ${APP_DIR#"${PROJECT_ROOT}"/}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

# ── 3. Info.plist ───────────────────────────────────────────────────────────
# XML plist (the canonical form). plutil can convert to binary later if we
# care about a few hundred bytes; for legibility & diffability, stay XML.
#
# Key choices:
#   - LSUIElement=true → menu-bar-only, no Dock icon, no app-switcher slot.
#   - LSMinimumSystemVersion=14.0 → matches Package.swift floor; older macOS
#     will refuse to launch it (preferable to a crash on a missing symbol).
#   - NSHighResolutionCapable=true → opt into HiDPI rendering. Default has
#     been YES since 10.7 for new apps but explicit is clearer.
#   - CFBundleExecutable must match the filename in Contents/MacOS/.
# Ref: https://developer.apple.com/documentation/bundleresources/information-property-list
cat >"${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Aaron Myatt. All rights reserved.</string>
</dict>
</plist>
PLIST

# Validate the plist immediately so a typo fails the build instead of
# producing a bundle that LaunchServices silently mis-parses.
# plutil ships with every macOS — no extra dep.
plutil -lint "${CONTENTS}/Info.plist" >/dev/null

# ── 4. PkgInfo ──────────────────────────────────────────────────────────────
# Legacy 8-byte file: 4-char type code + 4-char creator code.
# "APPL" = application, "????" = no specific creator (the modern idiom — every
# unique creator code used to require registering with Apple, which they
# stopped accepting decades ago). LaunchServices still glances at this file
# during some operations; omitting it works in practice but every well-formed
# bundle includes it.
# Ref: https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html
printf 'APPL????' >"${CONTENTS}/PkgInfo"

# ── 5. Copy binaries ────────────────────────────────────────────────────────
# Both binaries live side-by-side under Contents/MacOS/. The CLI being inside
# the bundle is what TASK-29's PathInstaller relies on — it symlinks
# Contents/MacOS/sp onto the user's PATH, so updating the .app updates sp too.
# We use `install -m 755` instead of `cp` so the bit pattern of the perms is
# explicit (executable for all, writable for owner).
install -m 755 "${SCRATCHPAD_BIN}" "${MACOS_DIR}/${APP_NAME}"
install -m 755 "${SP_BIN}"         "${MACOS_DIR}/sp"

# ── 6. Placeholder icon ─────────────────────────────────────────────────────
# A real AppIcon.icns is deferred (no design yet). LaunchServices is happy
# without one — it'll fall back to a generic app icon. We still write the
# CFBundleIconFile key above so swapping a real icon in later is a one-file
# drop, no plist edit needed.
# To generate later:
#   iconutil -c icns AppIcon.iconset → AppIcon.icns
#   docs: https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html
: # no-op — explicit placeholder so the script section reads as intended

# ── 7. Ad-hoc codesign the bundle ───────────────────────────────────────────
# WHY this matters:
#   SwiftPM ad-hoc-signs the individual Mach-O binaries (linker-signed) so
#   they can launch on Apple Silicon — but that doesn't seal the *bundle*.
#   Without bundle sealing (no Contents/_CodeSignature/CodeResources file,
#   Info.plist not bound to a signature), macOS Sequoia's Gatekeeper rejects
#   the .app with the dreaded "damaged and can't be opened" dialog — no
#   right-click → Open bypass, no System Settings escape. We hit this in
#   the v0.1.1 release; v0.1.2 fixes it by sealing the bundle here.
#
# WHY ad-hoc (`-s -`) rather than a Developer ID cert:
#   v1 deliberately skips notarization per decision-3. Ad-hoc signing
#   produces a valid (if non-Apple-trusted) signature that Sequoia accepts
#   for the bundle-integrity check; users still see "unidentified developer"
#   on the direct-download path (browser-set quarantine triggers Gatekeeper's
#   trust check), but they can bypass *that* via right-click → Open or our
#   documented xattr strip. The brew + curl paths don't see Gatekeeper at all.
#
# WHY signing innermost-first instead of `codesign --deep`:
#   `--deep` for signing is deprecated (it still works but emits a warning).
#   The correct modern pattern is to sign nested code first, then the
#   container — that's three commands here, no warning, equivalent result.
#
# Refs:
#   - codesign(1):    https://ss64.com/mac/codesign.html
#   - Sealed resources: https://developer.apple.com/library/archive/technotes/tn2206/_index.html
#   - decision-3 (no notarization): backlog/decisions/decision-3
echo "==> Ad-hoc signing bundle"
codesign --force -s - "${MACOS_DIR}/${APP_NAME}" 2>&1 | sed 's/^/    /'
codesign --force -s - "${MACOS_DIR}/sp"          2>&1 | sed 's/^/    /'
codesign --force -s - "${APP_DIR}"               2>&1 | sed 's/^/    /'

# Verify what we produced. If sealing didn't take, fail loudly here rather
# than pushing a broken artifact through the rest of the release pipeline.
SEAL_STATUS="$(codesign -dv "${APP_DIR}" 2>&1 | grep -E 'Sealed Resources' || true)"
if [[ "${SEAL_STATUS}" != *"version=2"* ]]; then
    echo "Bundle seal verification failed; codesign output above." >&2
    echo "Expected 'Sealed Resources version=2 rules=...'; got: ${SEAL_STATUS}" >&2
    exit 1
fi

# ── 8. Done ─────────────────────────────────────────────────────────────────
echo "==> Built ${APP_DIR}"
echo "    Open with: open '${APP_DIR}'"
echo "    Or copy to /Applications: cp -R '${APP_DIR}' /Applications/"

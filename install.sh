#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Scratchpad — one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/aaronmyatt/scratchpad/main/install.sh | bash
#
# What this does:
#   1. Fetches the latest (or pinned) Scratchpad release tarball from GitHub.
#   2. Verifies its sha256 against the sidecar published next to the tarball.
#   3. Extracts Scratchpad.app into /Applications (or ~/Applications if
#      /Applications is not writable). NEVER uses sudo.
#   4. Defensively strips com.apple.quarantine (curl doesn't set it, but this
#      keeps us robust even if a future redirect chain ever does).
#   5. Prints a one-liner reminding you to launch Scratchpad.app — the app's
#      first-launch routine offers to install the `sp` CLI on your PATH.
#
# Why curl|bash instead of brew/dmg:
#   - Faster than the DMG (no Gatekeeper friction; curl doesn't set the
#     com.apple.quarantine xattr that browsers do — same trick rustup, deno,
#     bun, and Homebrew itself use).
#   - Doesn't require Homebrew to be installed. Both install paths consume
#     the same release tarball (TASK-33) so behaviour is identical.
#   See backlog/decisions/decision-3 for the full distribution-strategy
#   rationale.
#
# Inspect first if you're cautious:
#   curl -fsSL <url>/install.sh | less
#
# Environment overrides (for advanced use / CI / testing):
#   SCRATCHPAD_VERSION       Pin a specific release tag (e.g. v0.1.0).
#                            Default: "latest" (GitHub's auto-redirect).
#   SCRATCHPAD_INSTALL_DIR   Target dir for the .app. Default:
#                            /Applications if writable, else ~/Applications.
#   SCRATCHPAD_TARBALL_URL   Override the tarball URL entirely. The sha256
#                            sidecar is assumed to be the same URL + ".sha256".
#                            Primary use: testing this script against a local
#                            file:// path before a release.
#   SCRATCHPAD_REPO          GitHub repo (owner/name). Default:
#                            aaronmyatt/scratchpad — set this if forking.
#
# Refs:
#   - quarantine xattr behaviour: https://eclecticlight.co/2024/10/24/the-life-and-death-of-quarantine-attributes/
#   - GitHub /releases/latest/download/ redirect:
#       https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
#   - shasum(1): https://ss64.com/mac/shasum.html
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
SCRATCHPAD_REPO="${SCRATCHPAD_REPO:-aaronmyatt/scratchpad}"
SCRATCHPAD_VERSION="${SCRATCHPAD_VERSION:-latest}"
APP_NAME="Scratchpad"

# Pretty-print helpers. Using ANSI escapes directly rather than a `tput`
# detour because this script targets macOS Terminal/iTerm/VS Code's terminal,
# all of which support these basic codes. Skip colour if stdout isn't a tty
# (CI logs, redirected output) — keeps logs grep-able.
if [[ -t 1 ]]; then
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
    C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi

info() { printf '%s==>%s %s\n' "${C_BOLD}" "${C_RESET}" "$*"; }
warn() { printf '%s==>%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
fail() { printf '%serror:%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }

# ── Pre-flight: macOS + Apple Silicon only ──────────────────────────────────
# This v1 is Apple-Silicon-only per decision-1. Linux/Windows are explicitly
# out of scope, and Intel Macs are deferred until we build a universal binary
# (see TASK-33 notes for the lipo follow-up).
[[ "$(uname -s)" == "Darwin" ]] || fail "Scratchpad is macOS-only; detected $(uname -s)."

case "$(uname -m)" in
    arm64)
        ARCH_TAG="arm64"
        ;;
    x86_64)
        # Friendly error rather than a silent failure — point the user at the
        # underlying decision so they understand why and what to do.
        fail "Scratchpad v1 is Apple-Silicon-only.
  Your Mac reports x86_64. Once we ship a universal binary this script will
  detect both. Track progress on TASK-33 (cross-arch tarball) at
  https://github.com/${SCRATCHPAD_REPO}/blob/main/backlog/decisions/decision-1*"
        ;;
    *)
        fail "Unrecognised architecture '$(uname -m)' — Scratchpad supports arm64 only."
        ;;
esac

# ── Resolve tarball + checksum URLs ─────────────────────────────────────────
# GitHub provides two stable URL patterns for release assets:
#   1. Pinned tag:  /releases/download/<tag>/<asset>
#   2. Latest tag:  /releases/latest/download/<asset>   (server-side redirect)
# We prefer pattern (2) for "latest" because it requires no JSON parsing —
# curl -L follows the 302 automatically. Pin via SCRATCHPAD_VERSION when
# you need reproducible installs in CI / rollback.
TARBALL_NAME="${APP_NAME}-${ARCH_TAG}.tar.gz"

if [[ -n "${SCRATCHPAD_TARBALL_URL:-}" ]]; then
    # Test/CI seam: caller has handed us a fully-qualified URL (often a
    # file:// path to a freshly-built local artifact). We assume the .sha256
    # sidecar lives at the same URL + ".sha256" — same convention TASK-33
    # follows when publishing.
    TARBALL_URL="${SCRATCHPAD_TARBALL_URL}"
    SHA_URL="${SCRATCHPAD_TARBALL_URL}.sha256"
    info "Using override tarball: ${TARBALL_URL}"
elif [[ "${SCRATCHPAD_VERSION}" == "latest" ]]; then
    TARBALL_URL="https://github.com/${SCRATCHPAD_REPO}/releases/latest/download/${TARBALL_NAME}"
    SHA_URL="${TARBALL_URL}.sha256"
else
    TARBALL_URL="https://github.com/${SCRATCHPAD_REPO}/releases/download/${SCRATCHPAD_VERSION}/${TARBALL_NAME}"
    SHA_URL="${TARBALL_URL}.sha256"
fi

# ── Download into a self-cleaning scratch dir ───────────────────────────────
# A dedicated tmp dir keeps the .app extract isolated from anything else in
# /tmp and gives us one path to nuke in the trap. mktemp -d -t uses macOS's
# /var/folders/.../T/ which is per-user-private and auto-tidied by the OS.
SCRATCH="$(mktemp -d -t scratchpad-install.XXXXXX)"
trap 'rm -rf "${SCRATCH}"' EXIT

info "Downloading ${C_BOLD}${TARBALL_NAME}${C_RESET}"
info "${C_DIM}from ${TARBALL_URL}${C_RESET}"

# curl flags chosen deliberately:
#   -f  fail on HTTP 4xx/5xx (no silent download of a 404 page)
#   -L  follow redirects (GitHub's /releases/latest/ pattern needs this)
#   -S  show errors even with -s
#   -s  no progress bar — keeps the install output tidy when piped from `curl … | bash`
#   --retry 3 / --retry-delay 2  survive flaky home wifi without nagging
# Ref: https://curl.se/docs/manpage.html
curl_dl() {
    curl -fLSs --retry 3 --retry-delay 2 -o "$1" "$2" \
        || fail "Download failed: $2"
}

curl_dl "${SCRATCH}/${TARBALL_NAME}" "${TARBALL_URL}"
curl_dl "${SCRATCH}/${TARBALL_NAME}.sha256" "${SHA_URL}"

# ── Verify checksum (defence against truncation, MITM, mirror tampering) ────
# shasum -c expects the sidecar's <hex>  <filename> to point at a file in
# the *current directory* — that's why we cd into SCRATCH for the check.
# The TASK-33 builder writes the sidecar with the bare filename for exactly
# this reason; if you regenerate by hand, keep the same convention.
info "Verifying sha256"
(
    cd "${SCRATCH}"
    shasum -a 256 -c "${TARBALL_NAME}.sha256" >/dev/null \
        || fail "Checksum mismatch — refusing to install. The download may be corrupt or tampered with."
)
info "${C_GREEN}checksum OK${C_RESET}"

# ── Extract ─────────────────────────────────────────────────────────────────
# TASK-33's tarball is rooted at "Scratchpad.app/" (no nested wrapper),
# so this extracts straight into ${SCRATCH}/Scratchpad.app.
info "Extracting"
tar -xzf "${SCRATCH}/${TARBALL_NAME}" -C "${SCRATCH}"
[[ -d "${SCRATCH}/${APP_NAME}.app" ]] \
    || fail "Tarball did not contain ${APP_NAME}.app — archive layout changed?"

# ── Pick install target ─────────────────────────────────────────────────────
# Decision tree:
#   1. Explicit SCRATCHPAD_INSTALL_DIR wins (CI, advanced users, tests).
#   2. /Applications if writable (the common case on admin accounts).
#   3. ~/Applications fallback, created if missing. This is the standard
#      per-user app location and is what LaunchServices indexes for the
#      menu-bar item to appear in app-launchers.
if [[ -n "${SCRATCHPAD_INSTALL_DIR:-}" ]]; then
    INSTALL_DIR="${SCRATCHPAD_INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
elif [[ -w "/Applications" ]]; then
    INSTALL_DIR="/Applications"
else
    INSTALL_DIR="${HOME}/Applications"
    mkdir -p "${INSTALL_DIR}"
    warn "/Applications not writable; installing to ${INSTALL_DIR} instead."
    warn "(Spotlight and Launchpad still index this location.)"
fi

TARGET="${INSTALL_DIR}/${APP_NAME}.app"

# Replace an existing install in-place. We don't prompt — this script is
# typically invoked in a pipe (`curl … | bash`) where there's no tty to read
# from, and "upgrade in place" is the expected behaviour for a one-liner
# installer. If the app is currently running, the rm here will succeed
# (macOS allows unlinking running binaries) but the running process keeps
# its old code mapped until you quit it. We surface a note about that below.
RUNNING_BEFORE="false"
if [[ -d "${TARGET}" ]]; then
    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        RUNNING_BEFORE="true"
    fi
    info "Removing existing ${TARGET}"
    rm -rf "${TARGET}"
fi

info "Installing to ${C_BOLD}${TARGET}${C_RESET}"
# mv preserves perms and is atomic within the same filesystem (which it is,
# since both ${SCRATCH} and ${INSTALL_DIR} live on the boot volume). If a
# user has /Applications on a network volume, that's exotic enough that
# they'll know to debug it themselves.
mv "${SCRATCH}/${APP_NAME}.app" "${TARGET}"

# ── Defence-in-depth: strip quarantine ──────────────────────────────────────
# In theory, curl never sets com.apple.quarantine. In practice, if a future
# version of curl, a corporate proxy, or a redirect through a download-
# manager extension ever sets it, Gatekeeper would prompt on first launch
# and the user would (rightly) blame this installer. Stripping recursively
# is cheap and idempotent — costs us a few milliseconds, saves a footgun.
# Ref: https://ss64.com/mac/xattr.html
xattr -dr com.apple.quarantine "${TARGET}" 2>/dev/null || true

# ── Done ────────────────────────────────────────────────────────────────────
info "${C_GREEN}Installed${C_RESET} ${TARGET}"

if [[ "${RUNNING_BEFORE}" == "true" ]]; then
    warn "Scratchpad was running during the upgrade. Quit and relaunch it to pick up the new build."
fi

# Friendly next-steps panel. The PathInstaller (TASK-29) handles the sp CLI
# on first launch, so we just point the user there rather than duplicating
# the symlink logic here.
cat <<EOF

  ${C_BOLD}Next steps${C_RESET}
  ──────────
  Open the app:
      open "${TARGET}"

  On first launch you'll be offered to install the ${C_BOLD}sp${C_RESET} CLI on your PATH.

  After that, verify the install and pipe data from any terminal:
      sp --version
      echo "hello" | sp

EOF

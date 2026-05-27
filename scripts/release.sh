#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# release.sh — cut a Scratchpad release end-to-end.
#
# Walks every step in backlog/docs/release-runbook.md:
#   1. Preflight       — clean working dir, gh auth, tap repo present
#   2. Tag + push      — `git tag -a vX.Y.Z && git push origin vX.Y.Z`
#   3. Build artifacts — scripts/build-tarball.sh + scripts/build-dmg.sh
#   4. Publish         — `gh release create vX.Y.Z <artifacts>`
#   5. Verify          — curl the /releases/latest/ redirect, confirm it lands
#   6. Bump tap        — edit Casks/scratchpad.rb in the homebrew-scratchpad
#                        repo, commit, push
#   7. Summary         — print what to smoke-test
#
# Every step is idempotent — re-running after a partial failure detects
# already-completed work (existing tag, existing release, identical
# Cask contents) and skips rather than failing. The intended failure mode is
# "fix the underlying issue and re-run" rather than "manually unwind state."
#
# Usage:
#   scripts/release.sh v0.1.0                 # interactive, real run
#   scripts/release.sh v0.1.0 --dry-run       # print steps, do nothing
#   scripts/release.sh v0.1.0 --yes           # skip confirmation prompts (CI)
#   SCRATCHPAD_TAP_DIR=/path/to/tap scripts/release.sh v0.1.0
#
# Why an idempotent script rather than a `task` runner / GitHub Actions
# workflow:
#   - The release cut is owner-machine work (tagging from local, signing
#     decisions deferred per decision-3). Putting it in GHA today would
#     mean either putting tap-repo write credentials in CI secrets or
#     splitting the workflow across two repos. Local script is simpler.
#   - The same script can become the body of a future GH Actions step if
#     we ever want CI-triggered releases — keeps the option open.
#
# Refs:
#   - gh release create: https://cli.github.com/manual/gh_release_create
#   - GitHub /releases/latest/download/ redirect:
#     https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
#   - backlog/docs/release-runbook.md for the underlying manual flow
#   - backlog/docs/install/homebrew-tap-setup.md for the Cask formula shape
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Locate ourselves ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# ── Configuration ────────────────────────────────────────────────────────────
APP_NAME="Scratchpad"
TARBALL_NAME="${APP_NAME}-arm64.tar.gz"
DMG_NAME="${APP_NAME}.dmg"
BUILD_DIR="${PROJECT_ROOT}/build"

# Tap repo location. Defaults to a nested clone at ./tap (gitignored) so the
# tap repo lives alongside this script for proximity, without polluting the
# parent's git history. To bootstrap the convention:
#   git clone git@github.com:aaronmyatt/homebrew-scratchpad.git tap
# Override via SCRATCHPAD_TAP_DIR when the tap clone lives elsewhere
# (e.g. a sibling directory, a shared dev dir, or a CI workspace).
TAP_REPO_DIR="${SCRATCHPAD_TAP_DIR:-${PROJECT_ROOT}/tap}"
TAP_CASK_PATH="Casks/scratchpad.rb"

# Cask template — single source of truth for the formula's structure.
# Rendered into the tap on every release with {{VERSION}} and {{SHA256}}
# substituted. To change the formula's shape, edit the template; the next
# release publishes the change. Hand-edits to the tap copy are clobbered.
CASK_TEMPLATE="${SCRIPT_DIR}/scratchpad.cask.rb.template"

# GitHub coordinates for the Scratchpad repo (the one this script lives in).
# Derived from the `origin` remote so a fork/rename Just Works without an
# env-var dance.
GH_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null \
    || echo "aaronmyatt/scratchpad")"

# ── Colour helpers (skip when not a tty so CI logs stay grep-able) ──────────
if [[ -t 1 ]]; then
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
    C_RESET=$'\033[0m'
else
    C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
    C_RESET=""
fi

step() { printf '\n%s━━━%s %s%s%s\n' "${C_BLUE}" "${C_RESET}" "${C_BOLD}" "$*" "${C_RESET}"; }
info() { printf '%s→%s %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
ok()   { printf '%s✓%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn() { printf '%s⚠%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
skip() { printf '%s↻%s %s\n' "${C_DIM}" "${C_RESET}" "$*"; }
fail() { printf '%s✗ %s%s\n' "${C_RED}" "$*" "${C_RESET}" >&2; exit 1; }

# ── Arg parsing ──────────────────────────────────────────────────────────────
DRY_RUN=false
SKIP_CONFIRM=false
VERSION=""

usage() {
    cat <<USAGE
Usage: scripts/release.sh <version> [--dry-run] [--yes]

  <version>     Required. Tag form, e.g. v0.1.0.
  --dry-run     Print every step's command, execute nothing.
  --yes         Skip interactive confirmation prompts (for CI).

Environment:
  SCRATCHPAD_TAP_DIR    Path to the homebrew-scratchpad clone.
                        Default: ${TAP_REPO_DIR}
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --yes|-y)  SKIP_CONFIRM=true; shift ;;
        -h|--help) usage; exit 0 ;;
        v[0-9]*)   VERSION="$1"; shift ;;
        *)         usage; fail "Unknown argument: $1" ;;
    esac
done

[[ -n "${VERSION}" ]] || { usage; fail "Version is required (e.g. v0.1.0)"; }

# Strip leading 'v' for places where we want bare semver (Cask `version` field).
VERSION_BARE="${VERSION#v}"

# Wrapper for command execution honouring --dry-run.
# We pass the command as separate args so quoting stays intact — `eval` would
# undo our careful argv shape.
run() {
    if "${DRY_RUN}"; then
        printf '%s$%s %s\n' "${C_DIM}" "${C_RESET}" "$*"
    else
        "$@"
    fi
}

confirm() {
    if "${SKIP_CONFIRM}" || "${DRY_RUN}"; then return 0; fi
    local prompt="$1"
    read -r -p "$(printf '%s? %s%s [y/N] ' "${C_YELLOW}" "${prompt}" "${C_RESET}")" reply
    [[ "${reply}" =~ ^[Yy]$ ]] || fail "Aborted by user."
}

# ── 1. Preflight ─────────────────────────────────────────────────────────────
step "1/6  Preflight"

# Working dir clean — uncommitted changes risk shipping a build that doesn't
# match what's actually tagged. `git status --porcelain` is the canonical
# script-friendly cleanliness check.
if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree has uncommitted changes. Commit or stash before releasing."
fi
ok "working tree clean"

# Current branch: warn-only (don't block) so hotfix-from-branch is possible.
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${CURRENT_BRANCH}" != "main" ]]; then
    warn "On branch ${CURRENT_BRANCH}, not main. This is OK for hotfixes."
else
    ok "on main"
fi

# gh authenticated — the release-create step needs this, fail fast.
gh auth status >/dev/null 2>&1 || fail "gh CLI is not authenticated. Run: gh auth login"
ok "gh authenticated"

# Tap repo present + writable. We don't check for the Cask file's existence
# here — the script writes it from the template (step 6), so an empty/fresh
# tap clone is a valid starting point. That lets bootstrap-via-first-release
# work: clone the empty tap, run release.sh, the script populates everything.
[[ -d "${TAP_REPO_DIR}/.git" ]] \
    || fail "Tap repo not found at ${TAP_REPO_DIR}. Set SCRATCHPAD_TAP_DIR to the clone path."
[[ -f "${CASK_TEMPLATE}" ]] \
    || fail "Cask template missing at ${CASK_TEMPLATE}. Restore it from git."
ok "tap repo at ${TAP_REPO_DIR}"

# Tap repo also clean — we'll be mutating it, so refuse to clobber WIP.
if [[ -n "$(git -C "${TAP_REPO_DIR}" status --porcelain)" ]]; then
    fail "Tap repo has uncommitted changes at ${TAP_REPO_DIR}. Resolve there first."
fi
ok "tap repo clean"

# ── 2. Tag + push (idempotent) ───────────────────────────────────────────────
step "2/6  Tag ${VERSION}"

if git rev-parse "${VERSION}" >/dev/null 2>&1; then
    # `^{commit}` dereferences an annotated-tag object to its target commit.
    # Without it, `git rev-parse v0.1.5` returns the tag-object SHA (a
    # different kind of object than a commit) and the comparison below
    # would always fail on the second run of this script, even when the
    # tag legitimately points at HEAD. Lightweight tags wouldn't have
    # this problem, but `git tag -a` below always creates annotated tags.
    # Bit us during the v0.1.5 cut when the first run failed on the
    # gh-release-create step and the re-run refused to skip the tag step.
    # Ref: https://git-scm.com/docs/gitrevisions#Documentation/gitrevisions.txt-emltrevgtemegemHEADv1510em
    EXISTING_SHA="$(git rev-parse "${VERSION}^{commit}")"
    HEAD_SHA="$(git rev-parse HEAD)"
    if [[ "${EXISTING_SHA}" != "${HEAD_SHA}" ]]; then
        fail "Tag ${VERSION} already exists but points at ${EXISTING_SHA}, not HEAD (${HEAD_SHA}). Delete the tag or release from the tagged commit."
    fi
    skip "tag ${VERSION} already exists at HEAD"
else
    confirm "Create annotated tag ${VERSION} at $(git rev-parse --short HEAD)?"
    run git tag -a "${VERSION}" -m "${VERSION}"
    ok "tag ${VERSION} created locally"
fi

# Push tag to origin. `git push --tags` would push all tags; we want just this
# one for predictable behaviour.
if git ls-remote --tags origin "${VERSION}" | grep -q "${VERSION}"; then
    skip "tag ${VERSION} already on origin"
else
    run git push origin "${VERSION}"
    ok "tag ${VERSION} pushed to origin"
fi

# ── 3. Build artifacts ───────────────────────────────────────────────────────
step "3/6  Build artifacts"

# Always rebuild — the previous build/ contents may be from a different
# commit (esp. when re-running after a failed publish). build-app.sh /
# tarball.sh / dmg.sh are individually idempotent and cheap on a warm
# SwiftPM cache.
run "${SCRIPT_DIR}/build-tarball.sh"
run "${SCRIPT_DIR}/build-dmg.sh"

TARBALL_PATH="${BUILD_DIR}/${TARBALL_NAME}"
SHA_PATH="${TARBALL_PATH}.sha256"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

if ! "${DRY_RUN}"; then
    [[ -f "${TARBALL_PATH}" ]] || fail "Missing ${TARBALL_PATH}"
    [[ -f "${SHA_PATH}"     ]] || fail "Missing ${SHA_PATH}"
    [[ -f "${DMG_PATH}"     ]] || fail "Missing ${DMG_PATH}"

    # Extract the hex digest. shasum sidecar format is `<hex>  <filename>`.
    SHA_HEX="$(awk '{print $1}' "${SHA_PATH}")"
    [[ -n "${SHA_HEX}" ]] || fail "Failed to read sha256 from ${SHA_PATH}"
    ok "sha256 = ${SHA_HEX}"
else
    SHA_HEX="<dry-run-placeholder-sha256>"
fi

# ── 4. Publish GitHub Release (idempotent) ───────────────────────────────────
step "4/6  Publish GitHub Release ${VERSION}"

# `gh release view` returns non-zero when the release doesn't exist, so we
# use that as the existence probe. Creating-over-existing fails with a
# message we'd rather not surface.
if gh release view "${VERSION}" --repo "${GH_REPO}" >/dev/null 2>&1; then
    skip "release ${VERSION} already exists on ${GH_REPO}"
    info "If you re-built artifacts, upload them with: gh release upload ${VERSION} <files> --clobber --repo ${GH_REPO}"
else
    confirm "Create GitHub Release ${VERSION} with ${TARBALL_NAME}, .sha256, and ${DMG_NAME}?"
    run gh release create "${VERSION}" \
        "${TARBALL_PATH}" \
        "${SHA_PATH}" \
        "${DMG_PATH}" \
        --repo "${GH_REPO}" \
        --title "${VERSION}" \
        --generate-notes
    ok "release ${VERSION} published"
fi

# ── 5. Verify the /latest/ redirect lands at our tag ─────────────────────────
step "5/6  Verify /releases/latest/ redirect"

if "${DRY_RUN}"; then
    skip "redirect verification (dry run)"
else
    LATEST_URL="https://github.com/${GH_REPO}/releases/latest/download/${TARBALL_NAME}"
    # -s silent, -I head-only, -L follow redirects. Final URL ends up in
    # the last `location:` header or, after -L, in `curl -w '%{url_effective}'`.
    RESOLVED="$(curl -sILo /dev/null -w '%{url_effective}' "${LATEST_URL}" || true)"
    if [[ "${RESOLVED}" == *"/${VERSION}/"* ]]; then
        ok "redirect lands at ${VERSION}"
    else
        warn "redirect resolved to ${RESOLVED}"
        warn "GitHub may take a moment to update /latest/ — re-run after ~30s if this is unexpected."
    fi
fi

# ── 6. Render Cask template into the tap and push ───────────────────────────
step "6/6  Render Cask + push to tap"

CASK_FILE="${TAP_REPO_DIR}/${TAP_CASK_PATH}"

# Pull latest in the tap repo so we don't conflict on push. `git pull` here
# is safe because we already verified the tap repo is clean in preflight.
run git -C "${TAP_REPO_DIR}" pull --ff-only

# Render the template. We substitute {{VERSION}} and {{SHA256}} via sed —
# straightforward because the placeholders are unique strings unlikely to
# appear elsewhere in the formula. Rendering (rather than in-place editing
# of an existing Cask) has two benefits:
#   1. No bootstrap step — an empty tap is a valid starting state.
#   2. The Cask's structure can evolve in the template (add stanzas,
#      change URL pattern) without breaking a fragile sed regex.
#
# Trade-off: hand-edits to tap/Casks/scratchpad.rb get clobbered on the
# next release. That's the intended behaviour — the tap is a publish
# target, not an editable artifact. To change the formula, edit
# scripts/scratchpad.cask.rb.template (THE canonical source) in this repo.
if "${DRY_RUN}"; then
    info "would render ${CASK_TEMPLATE}"
    info "         → ${CASK_FILE}"
    info "  {{VERSION}} → \"${VERSION_BARE}\""
    info "  {{SHA256}}  → \"${SHA_HEX}\""
else
    # mkdir -p so a fresh tap repo (no Casks/ dir yet) bootstraps cleanly.
    mkdir -p "$(dirname "${CASK_FILE}")"
    sed -e "s/{{VERSION}}/${VERSION_BARE}/g" \
        -e "s/{{SHA256}}/${SHA_HEX}/g" \
        "${CASK_TEMPLATE}" > "${CASK_FILE}"

    # Verify the placeholders all got substituted — catches a template
    # edit that introduced a new placeholder we don't know how to fill.
    if grep -q '{{[A-Z_]*}}' "${CASK_FILE}"; then
        UNFILLED=$(grep -o '{{[A-Z_]*}}' "${CASK_FILE}" | sort -u | tr '\n' ' ')
        fail "Cask still contains unsubstituted placeholders: ${UNFILLED}"
    fi
    ok "Cask rendered to ${CASK_FILE#"${TAP_REPO_DIR}"/}"
fi

# Show the diff so the user sees what's about to be committed. For a
# bootstrap release (Cask file freshly created), this is a big additive
# diff; for a version bump it's just the version + sha256 lines.
if ! "${DRY_RUN}"; then
    info "tap diff:"
    git -C "${TAP_REPO_DIR}" add "${TAP_CASK_PATH}"
    git -C "${TAP_REPO_DIR}" --no-pager diff --cached -- "${TAP_CASK_PATH}" | sed 's/^/  /'
fi

# Only commit + push if something actually changed.
if "${DRY_RUN}" || [[ -n "$(git -C "${TAP_REPO_DIR}" status --porcelain -- "${TAP_CASK_PATH}")" ]]; then
    confirm "Commit + push tap bump for Scratchpad ${VERSION}?"
    run git -C "${TAP_REPO_DIR}" commit -m "Scratchpad ${VERSION}"
    run git -C "${TAP_REPO_DIR}" push
    ok "tap repo updated and pushed"
else
    skip "tap already at ${VERSION_BARE} / ${SHA_HEX}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
step "Done"

cat <<SUMMARY

  ${C_GREEN}${C_BOLD}Scratchpad ${VERSION} released.${C_RESET}

  Release:    https://github.com/${GH_REPO}/releases/tag/${VERSION}
  Tarball:    ${TARBALL_NAME}  (${SHA_HEX:-<dry-run>})
  Tap repo:   ${TAP_REPO_DIR}

  ${C_BOLD}Smoke-test the install paths${C_RESET} (do these on a fresh user / VM if you can):

    brew update && brew install aaronmyatt/scratchpad/scratchpad
    curl -fsSL https://raw.githubusercontent.com/${GH_REPO}/main/install.sh | bash

  Both should land Scratchpad.app in /Applications with no Gatekeeper prompt.

SUMMARY

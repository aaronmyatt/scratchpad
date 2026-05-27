#!/usr/bin/env bats
# ──────────────────────────────────────────────────────────────────────────────
# install.bats — regression guards for install-hygiene fixes that already
# silently regressed once (v0.1.1 → v0.1.2 bundle sealing,
# v0.1.2 → v0.1.3 quarantine strip). See backlog/tasks/task-48 for the
# incident history that motivates each assertion.
#
# These are intentionally artifact-level tests, not unit tests:
#   - what we care about is the *output* of build-app.sh / build-tarball.sh
#     and the *content* of install.sh / the Cask template — i.e. the
#     observable contract the install pipeline makes with macOS.
#
# WHY bats (and not swift test):
#   The failures we're guarding against happened inside shell scripts and
#   Ruby templates, not Swift code. bats lets us assert against `codesign`
#   output, `xattr` state, and `grep` over template files with very little
#   ceremony. The Swift suite under Tests/ScratchpadTests/ continues to
#   own pure-logic regressions (InputHistory, EventStore, etc.).
#
# WHY in Tests/ rather than scripts/tests/:
#   Single tree for "all tests"; SwiftPM only knows about the
#   ScratchpadTests subdirectory (see Package.swift:46) so a loose .bats
#   file at Tests/ root is invisible to `swift test` — no collision.
#
# Run standalone:
#   bats Tests/install.bats
#
# Prereq:
#   brew install bats-core
#
# Refs:
#   - bats docs (writing tests, setup_file, run/fail builtins):
#       https://bats-core.readthedocs.io/en/stable/writing-tests.html
#   - codesign -dv (verifying bundle seal):
#       https://ss64.com/mac/codesign.html
#   - xattr(1) (com.apple.quarantine):
#       https://ss64.com/mac/xattr.html
#   - macOS quarantine xattr lifecycle:
#       https://eclecticlight.co/2024/10/24/the-life-and-death-of-quarantine-attributes/
# ──────────────────────────────────────────────────────────────────────────────

# ── setup_file: build the .app + tarball once, share across tests ─────────────
# bats runs setup_file() once before the first test in the file (vs setup()
# which runs before every test). swift build -c release plus signing takes
# 15-30s on a warm cache; we only want to pay that once.
# Ref: https://bats-core.readthedocs.io/en/stable/writing-tests.html#setup_file-and-teardown_file
setup_file() {
    # Resolve PROJECT_ROOT from this test file's location. `BATS_TEST_DIRNAME`
    # is bats-provided and equals the dir of the running .bats file.
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
    export APP_PATH="${PROJECT_ROOT}/build/Scratchpad.app"
    export TARBALL_PATH="${PROJECT_ROOT}/build/Scratchpad-arm64.tar.gz"

    # Build the tarball, which itself depends on build-app.sh — so this one
    # invocation produces both artifacts. Captured into BATS_FILE_TMPDIR so
    # any noise from the build doesn't pollute stdout when tests pass.
    # Ref: https://bats-core.readthedocs.io/en/stable/writing-tests.html#special-variables
    "${PROJECT_ROOT}/scripts/build-tarball.sh" >"${BATS_FILE_TMPDIR}/build.log" 2>&1 \
        || {
            echo "build-tarball.sh failed — see ${BATS_FILE_TMPDIR}/build.log" >&2
            cat "${BATS_FILE_TMPDIR}/build.log" >&2
            return 1
        }
}

# ── Test 1: build-app.sh produces a sealed bundle ─────────────────────────────
# Catches regression of v0.1.2's fix (build-app.sh:206-217). Without bundle
# sealing, Sequoia rejects with "Scratchpad is damaged" — no bypass dialog.
@test "build-app.sh produces a sealed bundle (Sealed Resources version=2)" {
    # codesign -dv writes its diagnostic output to stderr (yes, really —
    # not stdout). The 2>&1 merge is required to grep against `output`.
    run bash -c "codesign -dv '${APP_PATH}' 2>&1"
    [[ "${status}" -eq 0 ]] \
        || fail "codesign -dv failed on ${APP_PATH} — bundle never signed? see build-app.sh codesign block (lines ~206)"
    [[ "${output}" == *"Sealed Resources version=2"* ]] \
        || fail "bundle missing Sealed Resources — see build-app.sh codesign block. Got: ${output}"
}

# ── Test 2: Tarball preserves bundle sealing ──────────────────────────────────
# Catches a future tar-flag change that strips Contents/_CodeSignature/.
# Extracts into BATS_TEST_TMPDIR (auto-cleaned by bats after the test).
@test "tarball preserves bundle sealing after extraction" {
    [[ -f "${TARBALL_PATH}" ]] \
        || fail "tarball not found at ${TARBALL_PATH} — build-tarball.sh layout changed?"

    # `tar -C` chdirs before extracting; tarball is rooted at "Scratchpad.app/"
    # (see build-tarball.sh:96), so the .app lands directly under tmpdir.
    tar -xzf "${TARBALL_PATH}" -C "${BATS_TEST_TMPDIR}"

    local extracted="${BATS_TEST_TMPDIR}/Scratchpad.app"
    [[ -d "${extracted}" ]] \
        || fail "tarball did not contain Scratchpad.app at the root — see build-tarball.sh tar invocation"

    run bash -c "codesign -dv '${extracted}' 2>&1"
    [[ "${output}" == *"Sealed Resources version=2"* ]] \
        || fail "tarball-extracted bundle missing Sealed Resources — did tar strip _CodeSignature/? Got: ${output}"
}

# ── Test 3: install.sh strips com.apple.quarantine when present ───────────────
# This is the behavioural half of the quarantine guard. Tricky because:
#   - curl from file:// never sets com.apple.quarantine in the first place,
#     so a naive "run install.sh, assert xattr absent" test would pass even
#     if the defensive `xattr -dr` line were deleted from install.sh.
#   - To actually exercise the strip, we plant the xattr after the first
#     install, then re-run install.sh. The second invocation overwrites
#     the install dir (install.sh's "rm -rf existing target" branch) and
#     then runs `xattr -dr`. If that line ever gets removed, this test
#     fails — which is exactly the regression we want to catch.
#
# `com.apple.quarantine` value format: `<flags>;<timestamp-hex>;<agent>;<uuid>`
# We synthesise a plausible value; macOS doesn't validate the contents, only
# the xattr's presence/absence.
# Ref: https://eclecticlight.co/2024/10/24/the-life-and-death-of-quarantine-attributes/
@test "install.sh strips com.apple.quarantine when present (behavioural)" {
    local install_dir
    install_dir="$(mktemp -d -t scratchpad-bats.XXXXXX)"

    # First install — populates the .app at ${install_dir}/Scratchpad.app.
    SCRATCHPAD_TARBALL_URL="file://${TARBALL_PATH}" \
    SCRATCHPAD_INSTALL_DIR="${install_dir}" \
        bash "${PROJECT_ROOT}/install.sh" >/dev/null 2>&1 \
        || {
            rm -rf "${install_dir}"
            fail "install.sh failed on first invocation — see install.sh"
        }

    local installed="${install_dir}/Scratchpad.app"
    [[ -d "${installed}" ]] \
        || { rm -rf "${install_dir}"; fail "install.sh did not place Scratchpad.app at ${installed}"; }

    # Plant the quarantine xattr (synthetic value — macOS just checks presence).
    xattr -w com.apple.quarantine "0181;deadbeef;BatsTest;00000000-0000-0000-0000-000000000000" "${installed}"

    # Sanity check: the plant succeeded. If this fails, the test environment
    # itself (not install.sh) is the problem — fail loudly to make that clear.
    xattr -p com.apple.quarantine "${installed}" >/dev/null 2>&1 \
        || { rm -rf "${install_dir}"; fail "test setup error: could not plant com.apple.quarantine xattr"; }

    # Re-run install.sh — should overwrite the install dir AND strip quarantine.
    SCRATCHPAD_TARBALL_URL="file://${TARBALL_PATH}" \
    SCRATCHPAD_INSTALL_DIR="${install_dir}" \
        bash "${PROJECT_ROOT}/install.sh" >/dev/null 2>&1 \
        || {
            rm -rf "${install_dir}"
            fail "install.sh failed on second invocation — see install.sh"
        }

    # `xattr -p` exits non-zero when the attribute is absent. That's what we want.
    run xattr -p com.apple.quarantine "${installed}"
    local final_status="${status}"
    rm -rf "${install_dir}"
    [[ "${final_status}" -ne 0 ]] \
        || fail "install.sh did NOT strip com.apple.quarantine — defensive 'xattr -dr' regressed (see install.sh ~line 214)"
}

# ── Test 4: install.sh still contains the defensive strip line (static) ───────
# Symmetric with test #5 — pure regression guard against the line being
# silently deleted during a refactor. Cheaper proxy than the behavioural
# test above, but they're complementary (different failure modes).
@test "install.sh contains the defensive 'xattr -dr com.apple.quarantine' line" {
    grep -q 'xattr -dr com.apple.quarantine' "${PROJECT_ROOT}/install.sh" \
        || fail "install.sh missing 'xattr -dr com.apple.quarantine' — defensive strip removed? see install.sh"
}

# ── Test 5: Cask template carries the postflight quarantine strip ─────────────
# Brew Cask defaults to *adding* com.apple.quarantine to installed apps
# (counterintuitively — it's been the default since ~2020). On Sequoia
# this blocks first launch with no bypass dialog. The postflight block in
# the Cask template undoes it. A reformat that drops the block would
# silently re-introduce the v0.1.3 regression.
#
# We use `grep -A 5 'postflight do'` to slice out the lines after the
# block opens, then grep that slice for `com.apple.quarantine`. That tolerates
# whitespace/style changes inside the block but flags removal of the block
# itself (or accidentally renaming the xattr).
# Ref: https://docs.brew.sh/Cask-Cookbook#stanza-postflight
@test "Cask template carries the postflight com.apple.quarantine strip" {
    local template="${PROJECT_ROOT}/scripts/scratchpad.cask.rb.template"
    [[ -f "${template}" ]] \
        || fail "Cask template missing at ${template} — release pipeline broken"

    grep -A 5 'postflight do' "${template}" | grep -q 'com.apple.quarantine' \
        || fail "Cask template's postflight block no longer references com.apple.quarantine — Sequoia first-launch will break (see scripts/scratchpad.cask.rb.template, postflight stanza)"
}

# ──────────────────────────────────────────────────────────────────────────────
# Examples (REPL-evaluable from project root):
#
#   # Run the whole suite:
#   bats Tests/install.bats
#
#   # Run a single test (filter on test name):
#   bats Tests/install.bats -f "strips com.apple.quarantine"
#
#   # TAP output for CI:
#   bats --tap Tests/install.bats
# ──────────────────────────────────────────────────────────────────────────────

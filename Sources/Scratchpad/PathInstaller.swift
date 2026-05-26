// PathInstaller — first-launch helper that offers to symlink the bundled `sp`
// CLI onto the user's PATH so `echo foo | sp` works from any terminal.
//
// Standard pattern, copied loosely from VS Code's "Shell Command: Install 'code'
// in PATH" command. The difference is we don't expose a menu item yet (that's
// future polish); we prompt once on first launch and remember the answer.
//
// Why this lives outside AppDelegate:
//   AppDelegate is already the catch-all for "launch-time AppKit hooks." Adding
//   ~120 lines of filesystem fiddling there would make it harder to read. As a
//   bonus, PathInstaller has no internal state — it's a static enum with one
//   public entry point, easy to delete or replace.
//
// Focus discipline (see feedback memory "No focus theft, ever"):
//   The project invariant is that *show paths* for the dump window must not
//   activate the app. A first-launch setup dialog is not a show path — the
//   user has explicitly just double-clicked Scratchpad.app from Finder/Dock,
//   so the app is already the user's foreground intention. We therefore use a
//   plain NSAlert.runModal() here, with no NSApp.activate() call — runModal()
//   handles bringing the alert forward without us forcing app activation
//   against another foreground app.
//
// Refs:
//   - createSymbolicLink: https://developer.apple.com/documentation/foundation/filemanager/1413350-createsymboliclink
//   - NSAlert.runModal:   https://developer.apple.com/documentation/appkit/nsalert/1535441-runmodal
//   - UserDefaults:       https://developer.apple.com/documentation/foundation/userdefaults

import AppKit
import Foundation

@MainActor
enum PathInstaller {
    // ── Constants ────────────────────────────────────────────────────────────

    /// UserDefaults key recording that we've already shown the first-launch
    /// prompt. Value type is Bool; absence means "never prompted".
    /// Namespacing the key under the type name avoids collisions with any
    /// future preferences (UserDefaults is one big flat dictionary).
    private static let didPromptKey = "PathInstaller.didPromptOnFirstLaunch"

    /// Where we try to install the symlink first. /usr/local/bin is on the
    /// default macOS PATH for interactive shells (see /etc/paths) which is
    /// why it's the de-facto location for user-installed CLIs.
    /// On Apple Silicon Macs without Homebrew, this directory may not exist
    /// or may not be writable — the fallback path below handles that.
    private static let primaryInstallPath = "/usr/local/bin/sp"

    /// Walk `$PATH` looking for an executable named `sp`. Returns the first
    /// match, or nil. Same semantics as `which(1)` but done in-process so we
    /// avoid spawning a Process just to read its stdout.
    ///
    /// Used as the primary short-circuit: if `sp` is *anywhere* on PATH
    /// (Homebrew's `binary` stanza puts it at `/opt/homebrew/bin/sp` on
    /// Apple Silicon, `/usr/local/bin/sp` on Intel; a curl-install or manual
    /// `ln -s` might put it elsewhere), there's no point asking the user to
    /// install it again. Adding it via TASK-47 was prompted by users who
    /// installed via brew (Cask `binary` stanza handles the symlink) but
    /// still saw the PathInstaller dialog on first launch — noisy and
    /// confusing.
    ///
    /// Note: this checks `$PATH` *as inherited by Scratchpad at launch*,
    /// which for a GUI app is whatever launchd seeded it with (the user's
    /// login PATH plus macOS defaults). It does not see PATH entries added
    /// by interactive shell rc files unless those flow through launchd's
    /// envvar layer too. For our case (brew + the macOS default
    /// `/usr/local/bin`), that's enough.
    // Visibility: internal (not private) so PathInstallerTests can exercise
    // the $PATH-walking behaviour without spinning up a real .app bundle.
    static func spOnPath() -> String? {
        guard let raw = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        let fm = FileManager.default
        for component in raw.split(separator: ":") {
            // The dir entry may be empty (e.g. trailing `:` in PATH) — skip those
            // rather than testing for "/sp", which would resolve to the root.
            let dir = String(component)
            guard !dir.isEmpty else { continue }
            let candidate = (dir as NSString).appendingPathComponent("sp")
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Fallback when /usr/local/bin can't be written. ~/bin is the
    /// conventional per-user bin dir; we'll create it if missing and print
    /// PATH guidance because it isn't on the default PATH.
    private static var fallbackInstallDir: String {
        // NSString's expandingTildeInPath is the simplest way to resolve "~"
        // without pulling in Foundation's URL machinery for one path join.
        // Ref: https://developer.apple.com/documentation/foundation/nsstring/1407716-expandingtildeinpath
        return ("~/bin" as NSString).expandingTildeInPath
    }
    private static var fallbackInstallPath: String {
        (fallbackInstallDir as NSString).appendingPathComponent("sp")
    }

    // ── Public entry point ───────────────────────────────────────────────────

    /// Called once from AppDelegate.applicationDidFinishLaunching.
    /// Safe to call every launch — short-circuits via UserDefaults if we've
    /// already prompted.
    static func runIfNeeded() {
        let defaults = UserDefaults.standard

        // Short-circuit: we've prompted before. Decision (install / declined /
        // already-existed) is final — we never re-prompt because that turns
        // the app into nag-ware. If the user wants to (re)install sp later
        // we'll add a menu item; for now, deleting the UserDefaults key from
        // a terminal (`defaults delete com.aaronmyatt.scratchpad
        // PathInstaller.didPromptOnFirstLaunch`) re-arms it.
        guard !defaults.bool(forKey: didPromptKey) else { return }

        // Only relevant when running as a .app — `swift run` from dev produces
        // a binary deep inside .build/, symlinking *that* onto PATH would point
        // at a debug artifact that disappears the next rebuild. Detecting the
        // .app shape via the bundlePath suffix is reliable because SwiftPM
        // never names its dev output ".app".
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }

        // Resolve the bundled sp binary path. CFBundle's
        // executableURL points at the *main* binary (Scratchpad), so we have
        // to construct sp's path ourselves; it lives next to it.
        let bundledSp = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/sp")
            .path

        // Defensive: if the bundle was hand-assembled wrong and sp is missing,
        // bail silently — we'd otherwise create a broken symlink.
        guard FileManager.default.isExecutableFile(atPath: bundledSp) else { return }

        // Case 0 (TASK-47): sp is already somewhere on $PATH — typically
        // /opt/homebrew/bin/sp from the Homebrew Cask's `binary` stanza.
        // Silent no-op + record didPrompt so we never check again. Whoever
        // put sp there owns it; we don't poke at it.
        if spOnPath() != nil {
            defaults.set(true, forKey: didPromptKey)
            return
        }

        // Case 1: something already at /usr/local/bin/sp specifically (an
        // older manual install at the canonical location that isn't on the
        // current process's PATH — rare but possible). Don't overwrite;
        // surface the conflict if it's not ours.
        if FileManager.default.fileExists(atPath: primaryInstallPath) {
            handleExisting(bundledSp: bundledSp)
            defaults.set(true, forKey: didPromptKey)
            return
        }

        // Case 2: clean slate — show the offer dialog.
        let choice = presentOfferDialog()
        defaults.set(true, forKey: didPromptKey)   // record regardless of choice
        guard choice == .install else { return }
        install(bundledSp: bundledSp)
    }

    // ── Dialog: existing sp at /usr/local/bin/sp ─────────────────────────────

    /// Decide whether the existing /usr/local/bin/sp is "ours" (points at the
    /// current bundle's sp) or "theirs" (user installed something at that
    /// path). In the former case, nothing to do. In the latter, surface a
    /// non-blocking informational dialog so the user knows why pipes to
    /// `sp` might go to a different binary than they expect.
    private static func handleExisting(bundledSp: String) {
        // FileManager.destinationOfSymbolicLink throws when the path isn't a
        // symlink, so we wrap it. realpath-style resolution would be nicer
        // but Foundation doesn't expose realpath(3) directly; the symlink
        // check is enough for the common cases (manual cp vs ln -s).
        let existingTarget: String?
        if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: primaryInstallPath) {
            existingTarget = link
        } else {
            existingTarget = nil  // a real file, not a symlink
        }

        if existingTarget == bundledSp {
            // Idempotent: we (or a previous run of this code) already did it.
            // No user-visible UI needed.
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "sp already exists on PATH"
        alert.informativeText = """
        A 'sp' command was already at \(primaryInstallPath) when Scratchpad started \
        up. Scratchpad won't overwrite it.

        If you'd rather have Scratchpad's bundled sp on PATH, remove the existing \
        file and relaunch Scratchpad:

            rm \(primaryInstallPath)
        """
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

    // ── Dialog: first-launch offer ───────────────────────────────────────────

    private enum UserChoice { case install, decline }

    private static func presentOfferDialog() -> UserChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Install the ‘sp’ command-line tool?"
        alert.informativeText = """
        Scratchpad can install a small ‘sp’ shortcut so you can pipe text into \
        Scratchpad from any terminal:

            echo "hello" | sp

        We'll try \(primaryInstallPath) first, falling back to ~/bin if that \
        directory isn't writable. You can decline now and install later.
        """
        // Order matters — first added becomes the default ("return" key
        // pressable) which we want to be the install action because it's the
        // affirmative path the dialog text is describing.
        // Ref: https://developer.apple.com/documentation/appkit/nsalert/1525953-addbutton
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")

        // No NSApp.activate here — see file header for the focus-discipline
        // rationale. runModal will bring the alert forward as part of
        // displaying a modal sheet; we don't need to forcibly steal focus.
        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .install : .decline
    }

    // ── Installation flow ────────────────────────────────────────────────────

    private static func install(bundledSp: String) {
        // First attempt: /usr/local/bin/sp.
        // On modern macOS, /usr/local/bin is owned by root and not writable
        // to admin users by default; we deliberately don't request admin
        // privileges here (would require an authentication prompt and the
        // setuid dance via AuthorizationExecuteWithPrivileges, which Apple
        // deprecated). createSymbolicLink throws on EACCES and we treat
        // that as "fall back" rather than surfacing the error.
        //
        // We don't pre-check writability with FileManager.isWritableFile —
        // it can lie under sandboxing/TCC and racing with permissions
        // changes between check and use is pointless. Just attempt the
        // operation and react to the outcome.
        do {
            try FileManager.default.createSymbolicLink(
                atPath: primaryInstallPath,
                withDestinationPath: bundledSp
            )
            successAlert(at: primaryInstallPath, needsPathTweak: false)
            return
        } catch {
            // fall through to ~/bin attempt
        }

        // Second attempt: ~/bin/sp. Create the dir first if it's missing
        // (~/bin is convention, not a system-provided directory).
        do {
            try FileManager.default.createDirectory(
                atPath: fallbackInstallDir,
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                atPath: fallbackInstallPath,
                withDestinationPath: bundledSp
            )
            // ~/bin is not on the default PATH for any standard shell, so we
            // include PATH guidance in the success message.
            successAlert(at: fallbackInstallPath, needsPathTweak: true)
        } catch {
            failureAlert(error: error)
        }
    }

    // ── Result dialogs ───────────────────────────────────────────────────────

    private static func successAlert(at path: String, needsPathTweak: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Installed sp at \(path)"
        if needsPathTweak {
            alert.informativeText = """
            \(fallbackInstallDir) isn't on your shell's default PATH. To make \
            ‘sp’ work from any terminal, add this to your shell rc \
            (~/.zshrc or ~/.bashrc):

                export PATH="$HOME/bin:$PATH"

            Then open a new terminal and try:

                echo "hello" | sp
            """
        } else {
            alert.informativeText = """
            Try it from any terminal:

                echo "hello" | sp
            """
        }
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

    private static func failureAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't install sp on PATH"
        alert.informativeText = """
        Both \(primaryInstallPath) and \(fallbackInstallPath) failed to \
        receive the symlink. You can install it manually:

            ln -s "\(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/sp").path)" \(primaryInstallPath)

        Details: \(error.localizedDescription)
        """
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }
}

// ── REPL examples (per project convention) ───────────────────────────────────
// These aren't compiled; they document expected runtime behaviour.
//
//   1. First launch on a clean machine:
//      PathInstaller.runIfNeeded()
//      → dialog appears → user clicks Install
//      → /usr/local/bin/sp created (or ~/bin/sp + PATH guidance)
//      → UserDefaults flag set; subsequent launches no-op
//
//   2. Second launch:
//      PathInstaller.runIfNeeded()
//      → returns immediately (didPromptKey is true)
//
//   3. /usr/local/bin/sp already there from a prior manual install:
//      PathInstaller.runIfNeeded()
//      → if it's a symlink to our current bundle: silent no-op
//      → otherwise: informational dialog about the collision
//      → UserDefaults flag set so we don't keep nagging
//
//   4. Re-arming for testing:
//      defaults delete com.aaronmyatt.scratchpad PathInstaller.didPromptOnFirstLaunch
//      (then relaunch the app)

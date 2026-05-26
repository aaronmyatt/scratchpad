// AppDelegate — AppKit hooks the SwiftUI App scene can't reach directly.
//
// Responsibilities:
//   1. Switch to `.accessory` activation policy so we have no Dock icon and
//      live in the menu bar (TASK-17 AC#3). Done synchronously in
//      `applicationWillFinishLaunching` so the policy is applied before the
//      first window appears — otherwise the Dock icon flickers in for a frame.
//   2. Own the `StatusItemController` so the menu bar slot exists for the
//      lifetime of the app.
//   3. Start the `DumpReceiver` once the app has finished launching.
//
// Refs:
//   - NSApplication.activationPolicy: https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy
//   - applicationWillFinishLaunching: https://developer.apple.com/documentation/appkit/nsapplicationdelegate/1428623-applicationwillfinishlaunching

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var httpReceiver: DumpReceiver?
    private var socketReceiver: UnixSocketReceiver?
    private var fileWatchReceiver: FileWatchReceiver?
    private var escMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Accessory: no Dock icon, doesn't appear in Cmd-Tab. Standard for
        // menu-bar utilities.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build the status item now — by this point the menu bar exists.
        statusItem = StatusItemController()

        // Esc-to-hide (TASK-20). We use a local NSEvent monitor rather than
        // SwiftUI's `.onKeyPress`, because the latter requires a focused view
        // and our dump-display has no focusable subviews. The monitor only
        // swallows Esc when the Scratchpad window is *key* — otherwise the
        // user's foreground app continues to handle Esc as normal.
        // Refs:
        //   - addLocalMonitorForEvents: https://developer.apple.com/documentation/appkit/nsevent/1535472-addlocalmonitorforevents
        //   - keyCode 53 is Escape on every macOS keyboard layout:
        //     https://eastmanreference.com/complete-list-of-applescript-key-codes
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53,
               let window = WindowController.shared.window,
               window.isKeyWindow {
                // When the in-window search overlay is open, let Esc through
                // so the overlay's own .onKeyPress(.escape) can close *it*
                // rather than hiding the whole window. The user pressing Esc
                // twice (once to close search, once to hide window) is a
                // small price for the discoverable nested-context behavior.
                if UIState.shared.isSearchOpen {
                    return event
                }
                WindowController.shared.hide()
                return nil // swallow the event — don't let it bubble to the view
            }
            return event
        }

        // Start the HTTP receiver. If this fails (e.g. port in use), log to
        // stderr and continue — the menu bar still works, and the user can
        // pick a free port via SCRATCHPAD_PORT and relaunch.
        do {
            let r = DumpReceiver()
            try r.start()
            httpReceiver = r
        } catch {
            FileHandle.standardError.write(Data(
                "Scratchpad: failed to start HTTP receiver: \(error)\n".utf8
            ))
        }

        // Also start the UNIX domain socket receiver (TASK-7). Same failure
        // handling — log and continue. Either transport is independently
        // sufficient; the socket is purely a lower-latency convenience.
        do {
            let s = UnixSocketReceiver()
            try s.start()
            socketReceiver = s
        } catch {
            FileHandle.standardError.write(Data(
                "Scratchpad: failed to start socket receiver: \(error)\n".utf8
            ))
        }

        // Start the file-watch receiver (TASK-46). This is the container-
        // friendly transport: any process that can write to /tmp/sp gets a
        // dump. start() also truncates the file so each launch begins with
        // a clean slate. Failure here is non-fatal — usually it's because
        // /tmp/sp couldn't be opened for write, which we've already logged
        // from inside start() itself.
        do {
            let f = FileWatchReceiver()
            try f.start()
            fileWatchReceiver = f
        } catch {
            FileHandle.standardError.write(Data(
                "Scratchpad: failed to start file-watch receiver: \(error)\n".utf8
            ))
        }

        // First-launch helper (TASK-29): offers to symlink the bundled `sp`
        // CLI onto the user's PATH. Short-circuits on subsequent launches via
        // a UserDefaults flag, and short-circuits when running un-bundled
        // (e.g. via `swift run`) — see PathInstaller for the gating logic.
        // Kept here at the *end* of launch so receivers are already up before
        // we present any modal UI; if a dump comes in mid-prompt it still
        // gets received and rendered behind the alert.
        PathInstaller.runIfNeeded()
    }

    // Per TASK-2 AC#3 we already hide-on-close via the window delegate. As a
    // belt-and-braces measure, also tell the app not to terminate just because
    // every window happens to be closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

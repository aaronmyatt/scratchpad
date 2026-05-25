// WindowController — single entry point for show/hide of the Scratchpad window.
//
// Scope (M1, TASK-2 AC#4 + TASK-17 + TASK-18): both the menu bar status item
// and the HTTP receiver need a way to make the window appear/disappear without
// each of them poking at NSWindow directly. This is that seam.
//
// Why a singleton: there's exactly one Scratchpad window in v1. When that
// changes (it won't soon), this becomes a registry.
//
// The actual `NSWindow*` is captured by `WindowConfigurator` (an
// `NSViewRepresentable` in ContentView's background) the first time the view
// is mounted. Until then, calls to show()/hide() are silently no-ops — we
// can't yet, and it's fine because nothing should be calling pre-launch.
//
// Refs:
//   - NSWindow.makeKeyAndOrderFront: https://developer.apple.com/documentation/appkit/nswindow/1419208-makekeyandorderfront
//   - NSWindow.orderFrontRegardless: https://developer.apple.com/documentation/appkit/nswindow/1419495-orderfrontregardless
//   - NSWindow.orderOut:             https://developer.apple.com/documentation/appkit/nswindow/1419660-orderout
//
// Usage examples:
//   WindowController.shared.toggle()  // menu bar click
//   WindowController.shared.show()    // always non-activating — see invariant below
//   WindowController.shared.hide()
//
// **Invariant (TASK-19):** show() never steals focus from the user's foreground
// app. This is a hard rule — there is no activating variant. Even when the user
// *explicitly* clicks the menu bar icon, we don't activate Scratchpad: a
// menu-bar tool that grabs focus on every reveal makes the surrounding workflow
// feel hostile, and the same window appears in front either way thanks to the
// `.floating` window level set in ContentView.
//
// If a future feature genuinely needs Scratchpad to become the active app
// (e.g. the input bar wants keyboard focus on reveal), that's a separate
// `focus()` method, NOT a parameter to show().

import AppKit

@MainActor
final class WindowController {
    static let shared = WindowController()

    /// Weak — the window's lifetime is owned by SwiftUI's scene graph, not by us.
    weak var window: NSWindow?

    /// Reveal the window. Places it above other windows (the `.floating` level
    /// set by `WindowConfigurator` keeps it pinned), but does NOT make it key
    /// and does NOT activate Scratchpad. Whatever app the user is in keeps
    /// keyboard focus.
    /// Ref: https://developer.apple.com/documentation/appkit/nswindow/1419495-orderfrontregardless
    func show() {
        window?.orderFrontRegardless()
    }

    /// Hide the window. Doesn't destroy it — the same NSWindow is reused on
    /// the next show(), preserving the user's resized frame, scroll position,
    /// etc. This is what `windowShouldClose` is wired to (TASK-2 AC#3).
    func hide() {
        window?.orderOut(nil)
    }

    /// Convenience for the status item's left-click handler.
    func toggle() {
        if window?.isVisible == true { hide() } else { show() }
    }
}

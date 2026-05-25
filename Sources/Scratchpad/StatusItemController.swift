// StatusItemController — the menu bar status item (TASK-17).
//
// Scope: an `NSStatusItem` in the system menu bar with:
//   - Template icon (SF Symbol, dark/light-aware)
//   - Left-click toggles window visibility
//   - Right-click (or Option-click) shows a menu: Show / Hide / Quit
//
// Why this shape: it matches the de-facto convention for menu-bar utilities on
// macOS (Things, Bartender, Rectangle…). Left-click does the one obvious thing;
// the menu is the discoverability surface.
//
// Refs:
//   - NSStatusBar:        https://developer.apple.com/documentation/appkit/nsstatusbar
//   - NSStatusItem:       https://developer.apple.com/documentation/appkit/nsstatusitem
//   - NSImage template:   https://developer.apple.com/documentation/appkit/nsimage/1520017-istemplate
//   - SF Symbols catalog: https://developer.apple.com/sf-symbols/

import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Build the right-click menu up front. We attach/detach it from the
        // statusItem dynamically so left-click DOESN'T open it.
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Scratchpad",
                     action: #selector(StatusItemController.showWindow),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Hide Scratchpad",
                     action: #selector(StatusItemController.hideWindow),
                     keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Scratchpad",
                     action: #selector(StatusItemController.quit),
                     keyEquivalent: "q")
        self.menu = menu

        super.init()

        menu.items.forEach { $0.target = self }

        if let button = statusItem.button {
            // SF Symbol used as a template image. `isTemplate = true` lets
            // AppKit render it in the correct menu-bar tint for the user's
            // active appearance (dark/light), and adapts to the highlighted
            // state when the menu opens.
            let icon = NSImage(systemSymbolName: "note.text",
                               accessibilityDescription: "Scratchpad")
            icon?.isTemplate = true
            button.image = icon

            button.target = self
            button.action = #selector(StatusItemController.handleClick(_:))
            // Respond to both left and right mouse-ups in the SAME action so we
            // can branch on the event type. Without this, right-click would not
            // fire our action at all (only left-click does by default).
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // (No deinit cleanup: the status item lives for the app's lifetime and
    // macOS reclaims menu-bar slots on process exit. Adding a deinit here
    // conflicts with Swift 6's non-isolated deinit rules around non-Sendable
    // AppKit types, and gives no observable benefit.)

    // ── Click handling ───────────────────────────────────────────────────────

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            WindowController.shared.toggle()
            return
        }
        let isRightClick = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.option)

        if isRightClick {
            // Briefly attach the menu, simulate a click to pop it, then detach
            // so the next plain left-click still triggers our toggle action.
            // This is the standard idiom for "left=action, right=menu" status items.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            WindowController.shared.toggle()
        }
    }

    // ── Menu actions ─────────────────────────────────────────────────────────

    @objc private func showWindow() { WindowController.shared.show() }
    @objc private func hideWindow() { WindowController.shared.hide() }
    @objc private func quit()       { NSApp.terminate(nil) }
}

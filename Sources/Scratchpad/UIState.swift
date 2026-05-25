// UIState — small shared cross-component flag bag.
//
// At time of writing this exists for one reason only: the AppDelegate's Esc
// monitor (TASK-20) needs to know whether the in-window search overlay
// (TASK-12) is open, so it can let Esc pass through to the search field
// rather than hiding the window.
//
// Why a singleton rather than passing state down: the NSEvent monitor is
// installed in AppDelegate and runs *before* the SwiftUI responder chain.
// SwiftUI's own @State / @Environment can't be read from there. A tiny
// MainActor-isolated class lets both sides see the same flag.
//
// Resist the temptation to dump every transient UI flag in here. If this
// grows past ~3 flags, that's a smell — the right answer is usually proper
// state plumbing, not a bigger UIState.
//
// Refs:
//   - NSEvent.addLocalMonitorForEvents: https://developer.apple.com/documentation/appkit/nsevent/1535472-addlocalmonitorforevents

import Foundation

@MainActor
final class UIState {
    static let shared = UIState()

    /// True while the Ctrl-R search overlay (TASK-12) is open. Read by the
    /// AppDelegate Esc monitor to decide whether to swallow Esc (close
    /// window) or let it through (close overlay).
    var isSearchOpen: Bool = false
}

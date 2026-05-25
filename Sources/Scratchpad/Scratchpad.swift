// Scratchpad — SwiftUI app entrypoint.
//
// Most of the runtime setup lives in AppDelegate (activation policy, status
// item, HTTP receiver). This file's job is just to declare the scene and
// adapt to the AppKit delegate.
//
// REPL-style examples (run from the repo root):
//   swift run Scratchpad                                       # launch
//   SCRATCHPAD_PORT=9090 swift run Scratchpad                  # custom port
//   curl -X POST --data 'hello' http://127.0.0.1:8473/dump     # send a dump

import SwiftUI

@main
struct ScratchpadApp: App {
    // Bridge into AppKit for activation policy / menu bar / network setup.
    // Docs: https://developer.apple.com/documentation/swiftui/nsapplicationdelegateadaptor
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Single, non-tabbable window.
        // Docs: https://developer.apple.com/documentation/swiftui/window
        Window("Scratchpad", id: "scratchpad-main") {
            ContentView()
        }
        .defaultSize(width: 520, height: 360)
        .windowResizability(.contentSize)
    }
}

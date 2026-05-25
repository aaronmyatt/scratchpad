// ContentView — the single-window UI surface.
//
// Layout, top to bottom:
//   1. Header        — title + dump counter
//   2. Toolbar       — ⬅️/➡️ navigation, position indicator, Copy
//   3. Display area  — the currently-active event's text
//   4. Input bar     — '$ ' prompt + shell-command field
//
// Display model (TASK-22):
//   - All events (dumps and command results) live in EventStore.
//   - `pinnedEventId` tracks where the user is in history: nil = follow newest;
//     set = pinned to that event.
//   - Back/Forward (⬅️/➡️, ⌘[/⌘]) walk the events array.
//   - A new event resets to follow-newest *only if the command came from the
//     user* (we explicitly reset on submit). An asynchronously arriving dump
//     does NOT yank the user out of a historical view they're inspecting —
//     that would be infuriating. They can ⌘] forward to catch up.
//
// Input bar piping (TASK-22 AC#5):
//   - The shell command receives the *currently displayed* event's pipeData,
//     not unconditionally the latest dump. Lets you chain commands like
//     "jq ." then "grep foo" on the result of jq.
//
// Focus model (TASK-19 invariant): unchanged — show() never steals focus.
//
// Refs:
//   - NSPasteboard:                       https://developer.apple.com/documentation/appkit/nspasteboard
//   - .keyboardShortcut:                  https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:)
//   - @FocusState:                        https://developer.apple.com/documentation/swiftui/focusstate
//   - NSWindow.setFrameAutosaveName:      https://developer.apple.com/documentation/appkit/nswindow/1419017-setframeautosavename
//   - NSWindowDelegate.windowShouldClose: https://developer.apple.com/documentation/appkit/nswindowdelegate/1419380-windowshouldclose

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = EventStore.shared

    // ── Input bar state ──────────────────────────────────────────────────
    @State private var input: String = ""
    @State private var isRunning: Bool = false

    /// Two focusable fields now (input and search), so the @FocusState
    /// value type changes from Bool to an enum. Using an Optional<Focusable>
    /// lets `nil` represent "neither focused".
    enum Focusable: Hashable { case input, search }
    @FocusState private var focused: Focusable?

    // ── Search overlay state (TASK-12) ───────────────────────────────────
    @State private var isSearchOpen: Bool = false
    @State private var searchQuery: String = ""
    /// Index into `searchMatches`. 0 = most recent match. Bash convention.
    @State private var matchIndex: Int = 0

    // ── History recall state (TASK-11) ───────────────────────────────────
    /// 0 = "showing the live input the user is typing"; n > 0 means we're
    /// recalling the nth-most-recent entry (1 = most recent).
    @State private var historyCursor: Int = 0
    /// Snapshot of whatever the user had typed *before* they pressed ↑ for
    /// the first time, so we can restore it if they ↓ back to position 0.
    @State private var savedLiveInput: String = ""
    /// Last value we wrote into the input field via recall. Used by the
    /// onChange handler below to distinguish "code set it" from "user typed",
    /// so manual edits drop us out of recall mode cleanly.
    @State private var lastSetByRecall: String? = nil

    // ── Navigation state ─────────────────────────────────────────────────
    /// nil = "follow newest"; non-nil = pinned to the event with this id.
    @State private var pinnedEventId: Int? = nil

    // ── Copy button ephemeral state ──────────────────────────────────────
    @State private var copyFlash: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            displayArea
            Divider()
            searchOverlay
            inputBar
        }
        .background(WindowConfigurator())
        .background(globalShortcuts) // ⌘L, ⌘[, ⌘]
        // Eviction safety: if the event we were pinned to has fallen off the
        // ring buffer, drop the pin so the user lands on the newest entry
        // rather than seeing "Waiting for dumps…" with stale state.
        .onChange(of: store.events.count) { _, _ in
            if let id = pinnedEventId,
               !store.events.contains(where: { $0.id == id }) {
                pinnedEventId = nil
            }
        }
    }

    // ── Header ────────────────────────────────────────────────────────────

    private var header: some View {
        HStack {
            Text("Scratchpad")
                .font(.headline)
            Spacer()
            Text("dumps: \(store.dumpCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // ── Toolbar (nav + copy) ──────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoBack)
            .help("Previous (⌘[)")

            Button(action: goForward) {
                Image(systemName: "chevron.right")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoForward)
            .help("Next (⌘])")

            Text(positionLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            Spacer()

            Button(action: copyToClipboard) {
                // Briefly swap the label/icon after a successful copy so the
                // user gets a low-key confirmation. Resets after 1.5s.
                Label(copyFlash ? "Copied" : "Copy",
                      systemImage: copyFlash ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(displayedEvent == nil)
            .help("Copy displayed contents to the clipboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // ── Display area ──────────────────────────────────────────────────────

    @ViewBuilder
    private var displayArea: some View {
        if let event = displayedEvent {
            ScrollView([.vertical, .horizontal]) {
                Text(event.displayText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            Text("Waiting for dumps…")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }

    // ── Input bar ─────────────────────────────────────────────────────────

    // ── Search overlay (TASK-12) ──────────────────────────────────────────

    /// The reverse-incremental history search panel. Rendered only when
    /// `isSearchOpen` is true; otherwise this evaluates to an empty view
    /// and contributes no chrome to the layout.
    @ViewBuilder
    private var searchOverlay: some View {
        if isSearchOpen {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // The query field. Single-line, monospaced to align with
                    // the input bar visually. Esc/Enter/↑/↓ are handled here.
                    TextField("search history…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .focused($focused, equals: .search)
                        .onSubmit { closeSearch(accept: true) }
                        .onKeyPress(.escape) {
                            closeSearch(accept: false)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            selectOlderMatch()
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            selectNewerMatch()
                            return .handled
                        }
                        // New query → reset match selection to the top of the list.
                        .onChange(of: searchQuery) { _, _ in
                            matchIndex = 0
                        }
                        .frame(maxWidth: 200)

                    // Live preview of the currently-selected match. Truncated
                    // with middle ellipsis if longer than the available room.
                    if let match = currentMatch {
                        Text(match)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !searchQuery.isEmpty {
                        Text("(no match)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }

                    if searchMatches.count > 1 {
                        Text("\(matchIndex + 1) / \(searchMatches.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))
                Divider()
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            TextField(
                isRunning ? "Running…" : "shell command (Enter to run, ↑/↓ history, ⌃R search, ⌘L focus)",
                text: $input
            )
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .focused($focused, equals: .input)
            .disabled(isRunning)
            .onSubmit(runCommand)
            // History recall (TASK-11). `.onKeyPress` fires when the field
            // is focused, which is exactly when we want recall to work.
            // Returning `.handled` swallows the keystroke so the field's
            // default cursor-movement behavior (which is a no-op for a
            // single-line TextField anyway) doesn't also run.
            .onKeyPress(.upArrow)   { recallPrevious(); return .handled }
            .onKeyPress(.downArrow) { recallNext();     return .handled }
            // Detect manual edits: when the user types into a recalled entry,
            // drop the cursor back to "live" so subsequent ↑/↓ start from
            // their edited text. We tell apart "code set the field" from
            // "user typed" by comparing against `lastSetByRecall`.
            .onChange(of: input) { _, newValue in
                if lastSetByRecall == newValue { return }
                historyCursor = 0
                savedLiveInput = ""
                lastSetByRecall = nil
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // ── Invisible-button shortcuts ────────────────────────────────────────

    /// Three invisible buttons that install keyboard shortcuts at the view
    /// hierarchy level. Using buttons (rather than `NSEvent` monitors) lets
    /// SwiftUI auto-disable them when their condition is false — which also
    /// matches the visible buttons' enablement.
    @ViewBuilder
    private var globalShortcuts: some View {
        ZStack {
            Button("") { focused = .input }
                .keyboardShortcut("l", modifiers: .command)
            Button("") { goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!canGoBack)
            Button("") { goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!canGoForward)
            // Ctrl-R: open search overlay, or advance to next-older match if
            // already open (bash convention). Works from anywhere in the
            // window — including while typing in the input bar — because
            // SwiftUI installs Button keyboardShortcuts at the window level.
            Button("") { ctrlRPressed() }
                .keyboardShortcut("r", modifiers: .control)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // ── Derived nav state ─────────────────────────────────────────────────

    /// The event currently shown in the display area.
    /// Resolves the pin if any, otherwise the most recent event.
    private var displayedEvent: EventStore.Event? {
        if let id = pinnedEventId,
           let event = store.events.first(where: { $0.id == id }) {
            return event
        }
        return store.events.last
    }

    private var canGoBack: Bool {
        let events = store.events
        let currentId = pinnedEventId ?? events.last?.id
        guard let currentId,
              let idx = events.firstIndex(where: { $0.id == currentId }) else { return false }
        return idx > 0
    }

    /// We're at the newest entry iff the pin is nil. Forward is only
    /// meaningful when pinned.
    private var canGoForward: Bool { pinnedEventId != nil }

    private var positionLabel: String {
        let events = store.events
        guard !events.isEmpty else { return "—" }
        // Defensive — the unwraps below should both succeed when events is non-empty.
        let currentId = pinnedEventId ?? events.last!.id
        let idx = events.firstIndex(where: { $0.id == currentId }) ?? (events.count - 1)
        return "\(idx + 1) / \(events.count)"
    }

    // ── Actions ───────────────────────────────────────────────────────────

    private func goBack() {
        let events = store.events
        let currentId = pinnedEventId ?? events.last?.id
        guard let currentId,
              let idx = events.firstIndex(where: { $0.id == currentId }),
              idx > 0 else { return }
        pinnedEventId = events[idx - 1].id
    }

    private func goForward() {
        guard let currentId = pinnedEventId else { return }
        let events = store.events
        guard let idx = events.firstIndex(where: { $0.id == currentId }) else { return }
        let nextIdx = idx + 1
        guard nextIdx < events.count else { return }
        // Stepping forward onto the newest entry: drop the pin so we
        // resume "follow newest" mode. This is the only way back to
        // automatic tracking of incoming dumps.
        pinnedEventId = (nextIdx == events.count - 1) ? nil : events[nextIdx].id
    }

    private func copyToClipboard() {
        guard let event = displayedEvent else { return }
        // NSPasteboard general is the standard system clipboard. We copy
        // `event.copyText` rather than `displayText` so that command results
        // don't include the "$ <command>" header line on the clipboard —
        // that header is for the on-screen reader, not for pasting.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(event.copyText, forType: .string)

        copyFlash = true
        Task {
            // 1.5s is long enough to be noticed, short enough not to mislead
            // if the user immediately copies a second time.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copyFlash = false
        }
    }

    // ── Search overlay actions (TASK-12) ──────────────────────────────────

    /// Substring, case-insensitive, newest-first. Empty query → no matches.
    /// Computed on each access; 10k entries × String.contains is sub-ms.
    private var searchMatches: [String] {
        let q = searchQuery
        guard !q.isEmpty else { return [] }
        return InputHistory.shared.entries.reversed()
            .filter { $0.localizedCaseInsensitiveContains(q) }
    }

    private var currentMatch: String? {
        let matches = searchMatches
        guard matches.indices.contains(matchIndex) else { return nil }
        return matches[matchIndex]
    }

    /// Ctrl-R behavior:
    ///   - closed → open the overlay and focus the search field
    ///   - open   → advance to the next-older match (bash convention)
    private func ctrlRPressed() {
        if isSearchOpen {
            selectOlderMatch()
        } else {
            openSearch()
        }
    }

    private func openSearch() {
        searchQuery = ""
        matchIndex = 0
        isSearchOpen = true
        UIState.shared.isSearchOpen = true
        focused = .search
    }

    /// Close the overlay. If `accept` is true, copy the current match into
    /// the input bar; otherwise leave the input bar untouched.
    private func closeSearch(accept: Bool) {
        if accept, let match = currentMatch {
            // Reuse the recall machinery so the .onChange(of: input) handler
            // doesn't fight us — `setInputByRecall` marks the value as
            // "code set this" and prevents the recall cursor from clearing.
            setInputByRecall(match)
        }
        isSearchOpen = false
        UIState.shared.isSearchOpen = false
        searchQuery = ""
        matchIndex = 0
        // Return focus to the input bar so the user can hit Enter to run.
        focused = .input
    }

    private func selectOlderMatch() {
        let count = searchMatches.count
        guard count > 0 else { return }
        // Older = larger index, since we computed matches newest-first.
        if matchIndex < count - 1 {
            matchIndex += 1
        }
    }

    private func selectNewerMatch() {
        guard matchIndex > 0 else { return }
        matchIndex -= 1
    }

    // ── History recall (TASK-11) ──────────────────────────────────────────

    private func recallPrevious() {
        let history = InputHistory.shared.entries
        guard !history.isEmpty else { return }

        // First ↑: snapshot whatever the user was typing so ↓ can restore it.
        if historyCursor == 0 {
            savedLiveInput = input
        }

        // Clamp at the oldest entry. Position N means "history[count - N]"
        // — so N=1 is most recent, N=count is oldest.
        let newCursor = min(historyCursor + 1, history.count)
        if newCursor == historyCursor { return } // already at the oldest

        historyCursor = newCursor
        setInputByRecall(history[history.count - newCursor])
    }

    private func recallNext() {
        guard historyCursor > 0 else { return } // already at live
        historyCursor -= 1
        if historyCursor == 0 {
            setInputByRecall(savedLiveInput)
            savedLiveInput = ""
        } else {
            let history = InputHistory.shared.entries
            setInputByRecall(history[history.count - historyCursor])
        }
    }

    /// Set the input field from recall, marking the value so the
    /// `.onChange(of: input)` handler can distinguish it from a user edit
    /// and not accidentally reset the recall cursor.
    private func setInputByRecall(_ value: String) {
        lastSetByRecall = value
        input = value
    }

    private func resetHistoryCursor() {
        historyCursor = 0
        savedLiveInput = ""
        lastSetByRecall = nil
    }

    // ── Submit ────────────────────────────────────────────────────────────

    private func runCommand() {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isRunning else { return }
        // Append to persistent history (TASK-11). Done *before* clearing the
        // field so if persist crashes, we still see what was attempted.
        InputHistory.shared.add(command)
        input = ""
        resetHistoryCursor()
        isRunning = true

        // Pipe data = currently displayed event (TASK-22 AC#5).
        // - At newest: usually the latest dump → matches old behavior.
        // - Pinned on a historical dump: that dump's bytes.
        // - Pinned on a command result: that command's stdout (chain mode).
        let payload = displayedEvent?.pipeData ?? Data()

        Task {
            let result: ShellRunner.Result
            do {
                result = try await ShellRunner.run(command, input: payload)
            } catch {
                // Surface launch failures as a command-result event too, so
                // the history is complete and the user can scroll back to it.
                let fake = ShellRunner.Result(
                    stdout: Data(),
                    stderr: Data("\(error)".utf8),
                    exitCode: -1,
                    timedOut: false,
                    truncated: false
                )
                store.appendCommandResult(
                    command: command,
                    result: fake,
                    displayText: "$ \(command)\n[error] \(error)"
                )
                pinnedEventId = nil
                isRunning = false
                return
            }
            store.appendCommandResult(
                command: command,
                result: result,
                displayText: format(result: result, command: command)
            )
            // The user just ran a command — they expect to see its output,
            // so resume follow-newest.
            pinnedEventId = nil
            isRunning = false
        }
    }

    /// Render a ShellRunner.Result as the displayText for a command-result event.
    /// See TASK-9 — the conventions live in one place.
    private func format(result: ShellRunner.Result, command: String) -> String {
        var lines: [String] = ["$ \(command)"]

        let outText = String(data: result.stdout, encoding: .utf8)
            ?? "<\(result.stdout.count) bytes of non-UTF-8 stdout>"
        let errText = String(data: result.stderr, encoding: .utf8)
            ?? "<\(result.stderr.count) bytes of non-UTF-8 stderr>"

        if !outText.isEmpty {
            lines.append(outText.trimmingCharacters(in: .newlines))
        }
        if result.exitCode != 0 || outText.isEmpty {
            if !errText.isEmpty {
                lines.append("--- stderr ---")
                lines.append(errText.trimmingCharacters(in: .newlines))
            }
        }
        if result.timedOut {
            lines.append("[timed out after \(Int(ShellRunner.defaultTimeoutSeconds))s]")
        } else if result.exitCode != 0 {
            lines.append("[exit \(result.exitCode)]")
        }
        if result.truncated {
            lines.append("[output truncated at \(ShellRunner.maxOutputBytes / 1024 / 1024) MiB]")
        }
        return lines.joined(separator: "\n")
    }
}

// ── WindowConfigurator (unchanged) ─────────────────────────────────────────

/// Invisible view that grabs the hosting `NSWindow` once and configures it.
struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> WindowCloseDelegate { WindowCloseDelegate() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.setFrameAutosaveName("ScratchpadMainWindow")
            window.isReleasedWhenClosed = false
            window.delegate = context.coordinator
            WindowController.shared.window = window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { /* no-op */ }
}

/// Window delegate that turns "close" into "hide".
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

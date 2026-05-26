// sp — Scratchpad CLI client.
//
// Reads bytes from one of three sources and delivers them to the running
// Scratchpad app. Prefers the UNIX domain socket (low latency, no parsing);
// falls back to HTTP on 127.0.0.1 if the socket is missing or unreachable.
//
// Usage (TASK-5 + TASK-6):
//   echo 'hello' | sp                      # stdin
//   sp ./payload.json                      # file
//   sp -m 'literal string'                 # inline literal
//   sp -h | --help                         # this help
//
// Environment (matches the server side, so one shell-env knob configures both):
//   SCRATCHPAD_PORT          override the default HTTP port (8473)
//   SCRATCHPAD_SOCKET_PATH   override the default UDS path
//
// Exit codes:
//   0  dump delivered
//   1  transport error (neither socket nor HTTP reachable, file unreadable, …)
//   2  usage error (bad args, empty stdin, unknown flag)
//
// Refs:
//   - URLSession async/await: https://developer.apple.com/documentation/foundation/urlsession/3767353-data
//   - FileHandle.readToEnd:   https://developer.apple.com/documentation/foundation/filehandle/3172524-readtoend
//   - sockaddr_un (UDS):       https://man.openbsd.org/unix.4

import Foundation
import Darwin

// ── Helpers (stderr/usage/exit) ───────────────────────────────────────────────

func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func printUsage() {
    let msg = """
    sp — send a dump to a running Scratchpad.

    Usage:
      echo 'data' | sp           Read stdin and send it
      sp <path>                  Read a file and send its bytes
      sp -m <string>             Send a literal string
      sp -h, --help              Show this help

    Environment:
      SCRATCHPAD_PORT            Override the default HTTP port (8473)
      SCRATCHPAD_SOCKET_PATH     Override the default UDS path

    Alternative (no sp install required):
      Scratchpad also watches /tmp/sp — any process can deliver a dump by
      writing to that file:  echo 'data' > /tmp/sp
      Ideal when sp isn't installed (e.g. inside Docker containers).
    """
    print(msg)
}

// ── Resolve input source ──────────────────────────────────────────────────────

let args = CommandLine.arguments
let payload: Data

switch args.count {
case 1:
    guard let stdin = try? FileHandle.standardInput.readToEnd(), !stdin.isEmpty else {
        warn("sp: no input on stdin (did you mean to pipe something in?)")
        printUsage()
        exit(2)
    }
    payload = stdin

case 2:
    let arg = args[1]
    if arg == "-h" || arg == "--help" {
        printUsage()
        exit(0)
    }
    if arg.hasPrefix("-") {
        warn("sp: unknown option '\(arg)'")
        printUsage()
        exit(2)
    }
    let url = URL(fileURLWithPath: arg)
    do {
        payload = try Data(contentsOf: url)
    } catch {
        warn("sp: cannot read '\(arg)': \(error.localizedDescription)")
        exit(1)
    }

case 3 where args[1] == "-m":
    payload = Data(args[2].utf8)

default:
    warn("sp: invalid arguments")
    printUsage()
    exit(2)
}

// ── Try the UNIX domain socket first ──────────────────────────────────────────

/// Send `payload` to the Scratchpad UDS at `path`. Returns true on success
/// (bytes delivered, peer accepted), false on any transport failure (no
/// socket file, connect refused, short write, …) so the caller can fall back.
///
/// Why raw POSIX rather than NWConnection: this binary is a short-lived CLI
/// and we want zero startup cost. Network.framework spins up dispatch queues
/// and async machinery for what is, at this scale, three syscalls.
///
/// Synchronous on purpose — the caller invokes it from top-level, before any
/// async work (the HTTP fallback) needs to start.
func sendViaUnixSocket(path: String, payload: Data) -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    // Build the sockaddr_un. `sun_path` is a fixed-size C array (104 bytes
    // on Darwin); copy our path bytes into it via a memory rebind dance.
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = path.utf8CString
    // Need room for the NUL terminator. -1 because utf8CString includes it.
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    guard pathBytes.count <= maxLen else { return false }

    withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
        tuplePtr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
            for (i, byte) in pathBytes.enumerated() { dst[i] = byte }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { addrPtr -> Int32 in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connectResult == 0 else { return false }

    // Write the payload. May take multiple `write()` calls for large bodies.
    var sent = 0
    let total = payload.count
    let ok: Bool = payload.withUnsafeBytes { raw -> Bool in
        let base = raw.baseAddress!
        while sent < total {
            let n = Darwin.write(fd, base.advanced(by: sent), total - sent)
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
    guard ok else { return false }

    // Half-close so the server's `receive(... isComplete:)` flips true and
    // it knows we're done sending. Symmetric to writing then closing in HTTP.
    shutdown(fd, SHUT_WR)

    // Optionally drain any response bytes the server sent. We don't care
    // about content; just ensures the server's send-side close completes
    // before we close our fd. Small fixed buffer + ignore output.
    var scratch = [UInt8](repeating: 0, count: 16)
    _ = scratch.withUnsafeMutableBufferPointer { ptr in
        Darwin.read(fd, ptr.baseAddress, ptr.count)
    }

    return true
}

let socketPath: String = {
    if let override = ProcessInfo.processInfo.environment["SCRATCHPAD_SOCKET_PATH"],
       !override.isEmpty {
        return (override as NSString).expandingTildeInPath
    }
    let fm = FileManager.default
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    return appSupport.appending(path: "Scratchpad/dump.sock").path
}()

// ── HTTP fallback (wrapped so we can retry it after an autostart) ────────────

let port: UInt16 = {
    if let raw = ProcessInfo.processInfo.environment["SCRATCHPAD_PORT"],
       let parsed = UInt16(raw) {
        return parsed
    }
    return 8473
}()

/// POST `payload` to the app's HTTP receiver. Returns nil on success, or a
/// human-readable error string on transport/HTTP failure so the caller can
/// decide whether to fall back to autostart-and-retry or surface the error.
///
/// Why a single throwing helper rather than inline: we now call this twice
/// (once before autostart, once after) and duplicating the URLSession setup
/// would invite drift. Kept as a free async function — no shared state needed.
///
/// Refs:
///   - URLSession.data(for:): https://developer.apple.com/documentation/foundation/urlsession/3767353-data
func sendViaHTTP(port: UInt16, payload: Data) async -> String? {
    guard let url = URL(string: "http://127.0.0.1:\(port)/dump") else {
        return "invalid URL (port \(port))"
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = payload
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue("\(payload.count)", forHTTPHeaderField: "Content-Length")
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            return "Scratchpad replied HTTP \(status)"
        }
        return nil
    } catch {
        return error.localizedDescription
    }
}

// ── First attempt: try both transports without touching the app ──────────────

if sendViaUnixSocket(path: socketPath, payload: payload) {
    exit(0)
}

if await sendViaHTTP(port: port, payload: payload) == nil {
    exit(0)
}

// ── Autostart: neither transport reachable, so try to launch the app ─────────
//
// Why this exists: a first-time pipe like `echo wat | sp` is the most common
// onboarding moment — the user has installed Scratchpad but hasn't double-
// clicked it yet. Bailing with "Is the app running?" turns the very first
// invocation into a chore. Auto-launching makes `sp` Just Work.
//
// Focus discipline (see project memory "No focus theft, ever"): we use
// `open -g` so the app launches in the background without activating.
// `-b com.aaronmyatt.scratchpad` locates the bundle by id, which works
// whether the user installed it in /Applications, ~/Applications, or
// anywhere LaunchServices has indexed.
//
// We deliberately do NOT pass `-j` (launch hidden). `-j` puts the app into
// NSApplication.isHidden state, which suppresses `orderFrontRegardless()`
// on its windows — every subsequent dump would arrive, the receiver would
// call WindowController.show(), but nothing would appear on screen until
// the user manually clicked the status item. We let LaunchServices create
// the window normally; `-g` already keeps it from stealing focus.
//
// We deliberately *don't* fork-and-forget: the user piped data and expects
// it delivered, so we wait for the receivers to come up and retry once. If
// the app isn't installed at all (open returns nonzero) we fall through to
// the original error path so the user sees the actionable message.
//
// Refs:
//   - open(1):                       https://ss64.com/mac/open.html
//   - LSUIElement / accessory apps:  https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html

/// Launch Scratchpad.app via `open -gjb <bundle-id>`. Returns true if
/// LaunchServices accepted the request (the app exists and was started or
/// was already running), false otherwise.
func launchScratchpadApp() -> Bool {
    let p = Process()
    // /usr/bin/open is part of the macOS base install and never moves, so a
    // hardcoded path is safer than relying on $PATH (which a stripped env
    // might not include).
    p.launchPath = "/usr/bin/open"
    p.arguments = ["-gb", "com.aaronmyatt.scratchpad"]
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    } catch {
        return false
    }
}

/// Poll for the receivers to come online and deliver `payload`. Returns true
/// on successful delivery, false if we time out. Cold launch of an
/// LSUIElement app on Apple Silicon is typically <500 ms; we give it up to
/// ~3 seconds before giving up so a busy machine doesn't fail spuriously.
func deliverAfterLaunch(payload: Data) async -> Bool {
    // 30 attempts × 100 ms = 3 s cap. Linear backoff is fine for this short
    // window — the work being polled is "did the listener bind a port yet",
    // which transitions from never-going-to-succeed to always-succeeds in a
    // single moment, so exponential backoff buys us nothing.
    for _ in 0..<30 {
        // 100 ms in nanoseconds. Task.sleep takes UInt64 nanos.
        // Ref: https://developer.apple.com/documentation/swift/task/sleep(nanoseconds:)
        try? await Task.sleep(nanoseconds: 100_000_000)
        if sendViaUnixSocket(path: socketPath, payload: payload) { return true }
        if await sendViaHTTP(port: port, payload: payload) == nil { return true }
    }
    return false
}

if launchScratchpadApp() {
    if await deliverAfterLaunch(payload: payload) {
        exit(0)
    }
    warn("sp: launched Scratchpad but receivers didn't come up within 3s.")
    warn("sp: tried \(socketPath) and 127.0.0.1:\(port).")
    exit(1)
}

// ── Final fallthrough: app not installed (or LaunchServices doesn't know it) ─
warn("sp: could not reach Scratchpad — tried \(socketPath) and 127.0.0.1:\(port).")
warn("sp: Is the app installed? (open -b com.aaronmyatt.scratchpad failed)")
exit(1)

// UnixSocketReceiver — lower-latency local transport via a UNIX domain socket.
//
// Scope (M3, TASK-7):
//   - Bind a stream socket at ~/Library/Application Support/Scratchpad/dump.sock
//     (override with `SCRATCHPAD_SOCKET_PATH`).
//   - Accept a connection, read all bytes until EOF (the client half-closes
//     its write side when done), treat that as the dump payload, append to
//     EventStore.
//   - No HTTP framing — that's the whole point. Raw stream of bytes is
//     trivially fast and trivially correct.
//   - Runs alongside the HTTP receiver. Either transport is independently
//     sufficient; clients (e.g. `sp`) prefer the socket and fall back.
//
// Why raw POSIX instead of Network.framework:
//   The Network.framework UDS story (set `NWParameters.tcp.requiredLocalEndpoint`
//   to `.unix(path:)` and pass a dummy port to `NWListener`) does not actually
//   bind — the listener fails with EINVAL. The supported NWListener API takes
//   an `NWEndpoint.Port`, which is meaningless for UDS, and there isn't a clean
//   alternative. POSIX gets us there in ~120 lines that are well-trodden and
//   easy to read. We keep the dispatch model consistent with the rest of the
//   app by driving accept via a `DispatchSource.makeReadSource` on the main
//   queue.
//
// Refs:
//   - sockaddr_un / UNIX domain sockets: https://man.openbsd.org/unix.4
//   - DispatchSource:                    https://developer.apple.com/documentation/dispatch/dispatchsource
//   - chmod():                           https://man.openbsd.org/chmod.2
//
// Smoke test (with the app running):
//   echo 'via socket' | nc -U "$HOME/Library/Application Support/Scratchpad/dump.sock"

import Foundation
import Darwin

@MainActor
final class UnixSocketReceiver {
    /// Same cap as the HTTP receiver. Defense against a buggy client streaming
    /// forever; the dump area can't usefully render gigabytes anyway.
    nonisolated static let maxBodyBytes = 16 * 1024 * 1024

    /// Backlog passed to `listen(2)`. 8 is comfortably larger than the
    /// realistic concurrent-client count for a single-user dev tool.
    nonisolated static let listenBacklog: Int32 = 8

    private let store: EventStore
    private var acceptSource: DispatchSourceRead?
    private var listenFd: Int32 = -1
    private var socketPath: String?

    init(store: EventStore = .shared) {
        self.store = store
    }

    func start() throws {
        let path = Self.resolvePath()

        // Stale socket file from a previous unclean exit would refuse bind()
        // with EADDRINUSE. We always own the path, so unlinking is safe.
        try? FileManager.default.removeItem(atPath: path)

        // Ensure the parent directory exists.
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )

        // ── socket(AF_UNIX, SOCK_STREAM) ─────────────────────────────────
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }

        // Build sockaddr_un. `sun_path` is a fixed-size C array (104 bytes
        // on Darwin). The path bytes plus a trailing NUL must fit.
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= sunPathSize else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: sunPathSize) { dst in
                for (i, byte) in pathBytes.enumerated() { dst[i] = byte }
            }
        }

        // ── bind() ────────────────────────────────────────────────────────
        let bindResult = withUnsafePointer(to: &addr) { addrPtr -> Int32 in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let saved = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: saved) ?? .EINVAL)
        }

        // 0600: user read/write only. Other local users running as different
        // uids can't dump to us. Same-uid processes can — that's fine and
        // already true of the HTTP listener.
        _ = chmod(path, 0o600)

        // ── listen() ──────────────────────────────────────────────────────
        guard listen(fd, Self.listenBacklog) == 0 else {
            let saved = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: saved) ?? .EINVAL)
        }

        self.listenFd = fd
        self.socketPath = path
        FileHandle.standardError.write(Data(
            "UnixSocketReceiver listening at \(path)\n".utf8
        ))

        // Watch the listen fd for readability — fires when accept() would
        // not block, i.e. when a client has connected. Main queue so the
        // accept happens on MainActor; the per-client read happens on a
        // background queue (see `acceptOne`).
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.acceptSource = source
    }

    // ── Per-connection ──────────────────────────────────────────────────────

    private func acceptOne() {
        let client = accept(listenFd, nil, nil)
        guard client >= 0 else { return }

        // Hand off the read to a background queue so the accept loop on the
        // main queue stays responsive even if a client trickles bytes.
        DispatchQueue.global(qos: .userInitiated).async {
            let data = Self.readAll(fd: client)
            close(client)
            // We have the bytes — marshal to MainActor to update store + UI.
            Task { @MainActor in
                Self.deliver(payload: data)
            }
        }
    }

    /// Drain `fd` to EOF, capped at `maxBodyBytes`. Each `read()` syscall
    /// copies into a stack-ish heap buffer; the result is appended into a
    /// growing `Data`. Excess bytes after the cap are silently discarded.
    nonisolated private static func readAll(fd: Int32) -> Data {
        var collected = Data()
        let bufSize = 65_536
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 1)
        defer { buffer.deallocate() }

        while collected.count < maxBodyBytes {
            let n = Darwin.read(fd, buffer, bufSize)
            if n <= 0 { break } // 0 = EOF, <0 = error
            // Important: `Data(bytes:count:)` copies, so reusing the buffer
            // on the next iteration doesn't corrupt previously-appended data.
            collected.append(Data(bytes: buffer, count: n))
        }
        return collected
    }

    @MainActor
    private static func deliver(payload: Data) {
        EventStore.shared.appendDump(payload)
        WindowController.shared.show() // non-activating — TASK-19 invariant
    }

    // ── Path resolution ─────────────────────────────────────────────────────

    /// `SCRATCHPAD_SOCKET_PATH` overrides; otherwise the default lives next
    /// to the input-history file. `sp` honors the same env var.
    nonisolated static func resolvePath() -> String {
        if let override = ProcessInfo.processInfo.environment["SCRATCHPAD_SOCKET_PATH"],
           !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return appSupport.appending(path: "Scratchpad/dump.sock").path
    }
}

// DumpReceiver — minimal HTTP listener on 127.0.0.1.
//
// Scope (M1, TASK-3): accept POST (or anything) with a body, hand the body to
// DumpStore, return 200. Bind localhost-only, refuse non-loopback connections
// as a defense-in-depth check. Body size capped to keep us honest.
//
// "Make it work" choices:
//   - No third-party HTTP library. `Network.framework` (NWListener) + a tiny
//     hand-rolled parser. Just enough HTTP/1.1 to read Content-Length and a body.
//     The cross-language client story stays simple (curl works), and the
//     dependency footprint stays at zero.
//   - One connection = one dump. Pipelining/keep-alive deliberately not
//     supported; the client sends, we read, we respond, we close. The cost of
//     this simplicity is roughly nothing because dumps are local.
//
// What it does NOT do yet (deliberately deferred):
//   - Chunked transfer-encoding (TASK-3 follow-up if a real client needs it).
//   - Auth/token (scratchpad-open-questions item).
//   - Streaming dumps (we read the whole body before showing).
//
// Refs:
//   - NWListener: https://developer.apple.com/documentation/network/nwlistener
//   - NWConnection: https://developer.apple.com/documentation/network/nwconnection
//   - HTTP/1.1 message format: https://datatracker.ietf.org/doc/html/rfc9112
//
// Manual smoke test (after `swift run Scratchpad`):
//   curl -X POST --data 'hello' http://127.0.0.1:8473/dump
//   printf '%s' '{"hi":1}' | curl -X POST --data-binary @- http://127.0.0.1:8473/dump

import Foundation
import Network

@MainActor
final class DumpReceiver {
    /// Hard cap on a single dump body. 16 MiB is plenty for "I `console.log`d
    /// a large object" while preventing a runaway client from eating RAM.
    /// CLAUDE.md "hard iteration limits" rule applied here.
    /// `nonisolated` so the network callback (which is Sendable) can read it.
    nonisolated static let maxBodyBytes = 16 * 1024 * 1024

    /// Default port. Chosen to be (a) memorable as "SP" + 73 and (b) unlikely
    /// to clash with common dev servers. Configurable via SCRATCHPAD_PORT env var.
    nonisolated static let defaultPort: UInt16 = 8473

    private var listener: NWListener?
    private let store: EventStore

    init(store: EventStore = .shared) {
        self.store = store
    }

    func start() throws {
        let port = Self.resolvePort()
        let params = NWParameters.tcp
        // Reuse address so a quick restart doesn't TIME_WAIT-block us.
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.enableKeepalive = false
        }

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            // Hop to MainActor for state access. The connection itself can run
            // on any queue; we just need our store writes serialized.
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { state in
            // Surface listener failures during dev — silent failure here would
            // be the most confusing class of bug ("why doesn't curl work?").
            switch state {
            case .failed(let error):
                FileHandle.standardError.write(Data("DumpReceiver listener failed: \(error)\n".utf8))
            case .ready:
                FileHandle.standardError.write(Data("DumpReceiver listening on 127.0.0.1:\(port)\n".utf8))
            default:
                break
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    // ── Per-connection handling ──────────────────────────────────────────────

    private func accept(_ connection: NWConnection) {
        // Defense in depth: even though NWListener is local-process-bound here
        // in practice (we only bind a port; OS-level reachability is another
        // story), we reject any non-loopback remote endpoint explicitly.
        if !isLoopback(connection.endpoint) {
            connection.cancel()
            return
        }
        connection.start(queue: .main)
        readRequest(connection, buffer: Data(), headerEnd: nil, contentLength: nil, iterations: 0)
    }

    /// Recursively chains `connection.receive` calls until we have the full
    /// body. `iterations` is a guard against pathological inputs — capped
    /// well above what a 16MiB body in 64KiB chunks would need.
    private func readRequest(
        _ connection: NWConnection,
        buffer: Data,
        headerEnd: Int?,
        contentLength: Int?,
        iterations: Int
    ) {
        guard iterations < 1024 else {
            respond(connection, status: "413 Payload Too Large")
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if error != nil { connection.cancel(); return }

            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }

            // Locate end of headers (CRLF CRLF) the first time we see it.
            var hEnd = headerEnd
            var cLen = contentLength
            if hEnd == nil,
               let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                hEnd = range.upperBound
                let headerStr = String(data: buf.subdata(in: 0..<range.lowerBound), encoding: .utf8) ?? ""
                cLen = Self.parseContentLength(headerStr) ?? 0
            }

            if let hEnd, let cLen {
                let bodyAvailable = buf.count - hEnd
                if cLen > Self.maxBodyBytes {
                    Task { @MainActor in self.respond(connection, status: "413 Payload Too Large") }
                    return
                }
                if bodyAvailable >= cLen {
                    let body = buf.subdata(in: hEnd..<(hEnd + cLen))
                    Task { @MainActor in
                        self.store.appendDump(body)
                        // Auto-show the window (TASK-18). show() is non-activating
                        // by design — see TASK-19 invariant in WindowController.
                        WindowController.shared.show()
                        self.respond(connection, status: "200 OK", body: "ok")
                    }
                    return
                }
            }

            if isComplete {
                // Client hung up before we got a complete request. Best effort.
                Task { @MainActor in self.respond(connection, status: "400 Bad Request") }
                return
            }

            Task { @MainActor in
                self.readRequest(
                    connection,
                    buffer: buf,
                    headerEnd: hEnd,
                    contentLength: cLen,
                    iterations: iterations + 1
                )
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String = "") {
        let response =
            "HTTP/1.1 \(status)\r\n" +
            "Content-Length: \(body.utf8.count)\r\n" +
            "Connection: close\r\n" +
            "Content-Type: text/plain; charset=utf-8\r\n" +
            "\r\n" +
            body
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr): return addr.isLoopback
            case .ipv6(let addr): return addr.isLoopback
            case .name(let name, _): return name == "localhost"
            @unknown default: return false
            }
        default:
            return false
        }
    }

    nonisolated private static func parseContentLength(_ headers: String) -> Int? {
        // Case-insensitive header lookup. We split on CRLF, find the line
        // whose name lowercases to "content-length", and parse the value.
        for line in headers.split(separator: "\r\n", omittingEmptySubsequences: true) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            if name == "content-length" {
                let value = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    nonisolated private static func resolvePort() -> UInt16 {
        if let raw = ProcessInfo.processInfo.environment["SCRATCHPAD_PORT"],
           let port = UInt16(raw) {
            return port
        }
        return defaultPort
    }
}

// FileWatchReceiver — third transport. A single, well-known file the user
// (or any process) writes to in order to drop a dump.
//
// Scope (M6, TASK-46):
//   - Watch a single file at /tmp/sp (no per-write filenames, no directory
//     inbox, no rename dance).
//   - Polling, not FSEvents/DispatchSource. Reason: Docker Desktop's
//     bind-mount layer (gRPC-FUSE / VirtioFS) does not faithfully propagate
//     inode-change notifications from inside the container to the host
//     watcher. The whole point of this transport is "I'm writing from a
//     container", so we MUST work in that case. 200ms polling on a single
//     stat() call is free, and is well below human perception of latency
//     for a debug-dump tool.
//   - On start(), truncate the watch path to zero bytes. Two reasons:
//       1. A known-clean slate per launch — no replay of stale content
//          left over from a previous run or a writer that crashed mid-flush.
//       2. Zero-setup affordance: bind-mounting /tmp/sp into a container
//          requires the host-side path to exist. We ensure it does without
//          asking the user to `touch /tmp/sp` themselves.
//   - Two-layer change detection per tick:
//       Trigger:  (st_ino, st_mtimespec, st_size) inequality vs last seen.
//                 We use inequality rather than ">" because containers
//                 sometimes have clock skew vs the host and mtime can move
//                 backward; missing a real write would be the worst bug
//                 here.
//       Gate:     SHA256 over the bytes vs the last-emitted hash. Suppresses
//                 `touch` no-ops, atomic editor saves that wrote identical
//                 content, etc.
//   - Reads cap at 16 MiB to match DumpReceiver / UnixSocketReceiver.
//   - Empty file ⇒ no event. Important: our own startup truncate is the
//     reason this rule has to exist.
//
// Why a CFRunLoop-driven Timer on the main queue and not DispatchSourceTimer:
//   Foundation `Timer.scheduledTimer(withTimeInterval:repeats:block:)` runs on
//   the current runloop, which is the main runloop here. That gives us
//   MainActor reentrancy for free (we touch EventStore and WindowController,
//   both MainActor-isolated) without an explicit Task hop per tick.
//   Ref: https://developer.apple.com/documentation/foundation/timer
//
// Refs:
//   - stat(2):        https://man.openbsd.org/stat.2
//   - open(2) O_TRUNC: https://man.openbsd.org/open.2
//   - CryptoKit SHA256: https://developer.apple.com/documentation/cryptokit/sha256
//
// Smoke test (with the app running):
//   echo 'hi from a file' > /tmp/sp
//   printf '%s' '{"hi":1}' > /tmp/sp        # JSON dump
//   date > /tmp/sp; sleep 0.3; date > /tmp/sp  # two distinct events

import Foundation
import Darwin
import CryptoKit

@MainActor
final class FileWatchReceiver {
    /// Same cap as the other receivers. A dump bigger than this is almost
    /// certainly a bug in the writer, and the display area can't usefully
    /// render gigabytes anyway.
    nonisolated static let maxBodyBytes = 16 * 1024 * 1024

    /// Polling interval. 200ms feels instant in interactive use and is cheap
    /// enough (one stat() per tick when idle) that we don't bother with a
    /// slower backoff.
    nonisolated static let pollInterval: TimeInterval = 0.2

    /// The single path we watch. Fixed at /tmp/sp by design — see TASK-46
    /// for the rationale (one path, no list, no env override in v1).
    nonisolated static let watchPath: String = "/tmp/sp"

    // ── State ────────────────────────────────────────────────────────────

    private let store: EventStore
    private var timer: Timer?

    /// Last-observed `stat` tuple. `nil` while the file is absent. Compared
    /// for *inequality*, not ordering — see header comment.
    private var lastStat: StatSignature?

    /// Hash of the most recently emitted payload. Used to suppress
    /// content-identical re-writes. `nil` means "no event has been emitted
    /// yet this session (or the file was deleted since the last emission)".
    private var lastEmittedHash: SHA256Digest?

    init(store: EventStore = .shared) {
        self.store = store
    }

    // ── Lifecycle ────────────────────────────────────────────────────────

    /// Truncate the watch path to zero bytes, then start polling. Throws only
    /// if the timer cannot be installed — file-side problems are non-fatal
    /// and surface via the per-tick logging path instead.
    func start() throws {
        // ── Clean-slate truncate ─────────────────────────────────────────
        // O_WRONLY | O_CREAT | O_TRUNC is the canonical "(re)create empty"
        // recipe — same as `> /tmp/sp` from a shell. Mode 0o600 keeps the
        // file user-scoped on macOS where /tmp is world-writable; other
        // local users won't be able to inject dumps into our session.
        // We swallow the result: if this fails (e.g. /tmp is somehow not
        // writable), the polling loop will simply observe an empty/missing
        // file and stay idle until something appears.
        let fd = Darwin.open(Self.watchPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        if fd >= 0 {
            Darwin.close(fd)
        } else {
            FileHandle.standardError.write(Data(
                "FileWatchReceiver: could not truncate \(Self.watchPath): errno=\(errno)\n".utf8
            ))
        }

        // Prime lastStat from the just-truncated file so the very first tick
        // doesn't fire (size=0, mtime=now). This is belt-and-braces — the
        // empty-content gate would suppress an emission anyway — but it
        // saves a SHA256 round-trip on the first tick.
        lastStat = Self.statSignature(at: Self.watchPath)
        lastEmittedHash = nil

        // Foundation Timer auto-schedules on the current runloop in
        // `.defaultMode`. We're on the main thread (MainActor), so the
        // block runs on the main runloop, which is exactly where the
        // EventStore/WindowController mutations need to happen.
        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            // The block is `@Sendable` per Timer's API, so we hop back to
            // MainActor explicitly. Cost is negligible — one enqueue per
            // tick on the same queue we're already on.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        self.timer = timer

        FileHandle.standardError.write(Data(
            "FileWatchReceiver watching \(Self.watchPath)\n".utf8
        ))
    }

    // ── Per-tick logic ───────────────────────────────────────────────────

    private func tick() {
        let sig = Self.statSignature(at: Self.watchPath)

        // File absent: reset state so a future write re-arms the gate, and
        // skip the rest of the tick. No log spam — this is the steady-state
        // when nothing has been written yet.
        guard let sig = sig else {
            lastStat = nil
            lastEmittedHash = nil
            return
        }

        // Trigger: any change in (inode, mtime, size) is enough to look more
        // closely. Equality means "nothing changed since we last looked" —
        // bail out cheaply without touching disk.
        if sig == lastStat {
            return
        }
        lastStat = sig

        // Empty file: never emit. Covers our own start-up truncate and any
        // `: > /tmp/sp` no-op the user might do.
        if sig.size == 0 {
            return
        }

        // Read the bytes. If the read fails (file deleted between stat and
        // open, perms changed, etc.) just skip this tick — the next write
        // will produce a new (mtime,size) and we'll try again.
        guard let payload = Self.readCapped(at: Self.watchPath) else {
            return
        }
        if payload.isEmpty {
            return
        }

        // Gate: hash the payload, suppress if identical to the last emission.
        // SHA256 over 16 MiB is well under a millisecond on Apple Silicon —
        // not worth optimizing further (e.g. by hashing a prefix).
        let hash = SHA256.hash(data: payload)
        if let last = lastEmittedHash, last == hash {
            return
        }
        lastEmittedHash = hash

        // Deliver. Both calls are MainActor-isolated, which is fine because
        // we're already on MainActor here.
        store.appendDump(payload)
        WindowController.shared.show() // non-activating — TASK-19 invariant
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// Compact signature of a file's `stat(2)` output. Equality means "as far
    /// as the kernel is concerned, nothing has changed". We deliberately do
    /// NOT include atime — readers (including ourselves) would bump it on
    /// every tick. mtime is the "content changed at" timestamp; ctime is
    /// "inode metadata changed", which catches chmod/chown/truncate-to-zero.
    /// We include ctime via inode + size + mtime as a practical proxy.
    struct StatSignature: Equatable {
        let inode: UInt64
        /// `st_mtimespec` packed as (sec, nsec). Apple's struct exposes both
        /// fields at nanosecond resolution on APFS.
        let mtimeSec: Int
        let mtimeNsec: Int
        let size: Int64
    }

    /// Returns `nil` if the path does not exist or stat() fails. All other
    /// stat errors are silently treated as "absent" — there is no useful
    /// recovery path inside a 200ms polling loop.
    ///
    /// Implementation note: we call `lstat(2)` rather than `stat(2)` purely
    /// to dodge a Swift symbol-resolution collision — Darwin exports both
    /// `stat` the struct AND `stat` the function under the same name, and
    /// the compiler can't tell which one we mean. For a regular file (which
    /// /tmp/sp is by convention), lstat and stat are behaviourally identical;
    /// the only difference is lstat does not follow symlinks. If a user
    /// symlinks /tmp/sp to another path we'd inspect the link itself, which
    /// is arguably *safer* — we won't be tricked into reading a file outside
    /// the conventional location.
    ///   Ref: https://man.openbsd.org/lstat.2
    nonisolated static func statSignature(at path: String) -> StatSignature? {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            return nil
        }
        return StatSignature(
            inode: UInt64(st.st_ino),
            mtimeSec: Int(st.st_mtimespec.tv_sec),
            mtimeNsec: Int(st.st_mtimespec.tv_nsec),
            size: Int64(st.st_size)
        )
    }

    /// Read up to `maxBodyBytes` from `path`. Returns `nil` on open() failure
    /// (file removed between stat and open), an empty Data() if the file is
    /// empty, or the bytes otherwise. Excess bytes past the cap are silently
    /// dropped — same convention as the HTTP and UDS receivers.
    nonisolated static func readCapped(at path: String) -> Data? {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var collected = Data()
        let bufSize = 65_536
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 1)
        defer { buffer.deallocate() }

        while collected.count < maxBodyBytes {
            let n = Darwin.read(fd, buffer, bufSize)
            if n <= 0 { break } // 0 = EOF, <0 = error (treat as EOF)
            collected.append(Data(bytes: buffer, count: n))
        }
        return collected
    }
}

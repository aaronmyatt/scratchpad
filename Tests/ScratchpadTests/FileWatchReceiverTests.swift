// FileWatchReceiverTests — coverage for the pure helpers behind the polling
// file-watch transport (TASK-46).
//
// The full receiver is tightly coupled to MainActor singletons (EventStore,
// WindowController) and to the fixed path /tmp/sp, so we don't drive `start()`
// from tests. Instead we exercise the two static helpers that carry all the
// real logic — `statSignature(at:)` and `readCapped(at:)` — against per-test
// temp files. Together they cover the trigger and gate paths the live tick()
// composes.
//
// Why pure-helper tests are enough:
//   - tick()'s logic is a thin orchestration: stat→compare→read→hash→deliver.
//   - The interesting bugs live in the helpers (stat field plumbing, read cap,
//     empty-file handling).
//   - Driving the timer end-to-end would require a fake EventStore and a way
//     to override the path constant; both are net-new test seams that pay
//     for themselves only if this transport grows more logic. v1 is too thin.
//
// Refs:
//   - Swift Testing #expect:    https://developer.apple.com/documentation/testing/expectations
//   - FileManager.temporaryDirectory: https://developer.apple.com/documentation/foundation/filemanager/1409984-temporarydirectory

import Foundation
import Testing
@testable import Scratchpad

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build a fresh temp-file path. Returns the path string (the receiver's
/// helpers take String, not URL). Caller is responsible for any cleanup —
/// macOS evicts /var/folders/T/ aggressively on its own, so tests don't bother.
private func tempFilePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("scratchpad-fw-\(UUID().uuidString)")
        .path
}

// ── statSignature ────────────────────────────────────────────────────────────

/// AC: a missing file returns nil. This is the steady-state when no producer
/// has written yet, so it must be cheap and not throw.
@Test
func statSignatureReturnsNilForMissingFile() {
    let path = tempFilePath()
    #expect(FileWatchReceiver.statSignature(at: path) == nil)
}

/// AC: writing distinct content twice yields distinct signatures. This is the
/// happy path for the trigger layer — content change must register, otherwise
/// dumps would be invisible.
@Test
func statSignatureChangesAfterWrite() throws {
    let path = tempFilePath()
    try "alpha".write(toFile: path, atomically: true, encoding: .utf8)
    let first = FileWatchReceiver.statSignature(at: path)
    #expect(first != nil)

    // mtime resolution on APFS is nanoseconds, but successive Swift writes can
    // land in the same nanosecond on fast hardware. Bumping the byte count
    // guarantees a different signature via the size field alone — orthogonal
    // proof that the trigger doesn't depend solely on mtime.
    try "alpha-bravo".write(toFile: path, atomically: true, encoding: .utf8)
    let second = FileWatchReceiver.statSignature(at: path)
    #expect(second != nil)
    #expect(first != second, "signature must differ after content change")
}

// ── readCapped ───────────────────────────────────────────────────────────────

/// AC: small writes round-trip exactly. The receiver hands raw bytes to
/// EventStore, so any silent transformation here would corrupt display text.
@Test
func readCappedRoundTripsSmallContent() throws {
    let path = tempFilePath()
    let payload = "hello\nworld\n"
    try payload.write(toFile: path, atomically: true, encoding: .utf8)
    let bytes = FileWatchReceiver.readCapped(at: path)
    #expect(bytes != nil)
    #expect(String(data: bytes!, encoding: .utf8) == payload)
}

/// AC: a missing file returns nil (not empty Data()). Important because tick()
/// distinguishes "file gone" (skip, no state change) from "file empty"
/// (skip, but trigger state already updated).
@Test
func readCappedReturnsNilForMissingFile() {
    #expect(FileWatchReceiver.readCapped(at: tempFilePath()) == nil)
}

/// AC: an empty file reads as Data() of length zero. This is the case our
/// own start-up truncate produces; tick() relies on `payload.isEmpty` to skip
/// emission, so the read must surface zero bytes (not nil) here.
@Test
func readCappedReturnsEmptyForEmptyFile() throws {
    let path = tempFilePath()
    FileManager.default.createFile(atPath: path, contents: Data())
    let bytes = FileWatchReceiver.readCapped(at: path)
    #expect(bytes != nil)
    #expect(bytes!.isEmpty)
}

/// AC: reads past maxBodyBytes are discarded, not crashed on.
/// We deliberately write *one byte past* the cap rather than a huge payload —
/// this proves the cap rather than just exercising it, and keeps the test fast.
@Test
func readCappedTruncatesOversizedFile() throws {
    let path = tempFilePath()
    // 16 MiB + 1. Allocating once and writing is faster than appending in a
    // loop.
    let oversize = Data(repeating: 0x41 /* 'A' */,
                        count: FileWatchReceiver.maxBodyBytes + 1)
    try oversize.write(to: URL(fileURLWithPath: path))

    let bytes = FileWatchReceiver.readCapped(at: path)
    #expect(bytes != nil)
    #expect(bytes!.count == FileWatchReceiver.maxBodyBytes,
            "expected read to cap at maxBodyBytes; got \(bytes!.count)")
}

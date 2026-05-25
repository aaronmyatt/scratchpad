// ShellRunner — execute a user-typed shell command with a dump piped to stdin.
//
// Scope (M4, TASK-9 + TASK-10): given a command string and a Data payload,
// run `/bin/sh -c <command>` with the payload on stdin, return stdout/stderr
// and exit code. All safety defaults from decision-2 enforced here.
//
// Why not a higher-level wrapper or third-party lib: this is exactly one
// `Process` invocation. The interesting parts (timeout, output cap, stdin
// feeding without pipe-buffer deadlock) need careful handling and reading
// foundational Foundation APIs is the clearest way to get them right.
//
// Refs:
//   - Process:     https://developer.apple.com/documentation/foundation/process
//   - Pipe:        https://developer.apple.com/documentation/foundation/pipe
//   - FileHandle:  https://developer.apple.com/documentation/foundation/filehandle
//
// Usage:
//   let result = try await ShellRunner.run("jq .", input: dumpBytes)
//   print(result.exitCode)        // 0 on success
//   print(String(decoding: result.stdout, as: UTF8.self))

import Foundation

struct ShellRunner {

    // ── Tunables (decision-2) ────────────────────────────────────────────────

    /// Hard timeout. Commands that haven't exited by this point are killed.
    /// Overridable per-process via `SCRATCHPAD_SHELL_TIMEOUT` (seconds).
    nonisolated static var defaultTimeoutSeconds: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["SCRATCHPAD_SHELL_TIMEOUT"],
           let parsed = TimeInterval(raw), parsed > 0 {
            return parsed
        }
        return 10
    }

    /// Per-stream output cap. Truncates beyond this with a banner so the user
    /// knows the result is incomplete. 4 MiB is enough for almost any text
    /// processing output but stops `find /` from eating the UI.
    nonisolated static let maxOutputBytes = 4 * 1024 * 1024

    // ── Result ───────────────────────────────────────────────────────────────

    struct Result: Sendable {
        let stdout: Data
        let stderr: Data
        let exitCode: Int32
        /// True when we killed the process because it exceeded the timeout.
        let timedOut: Bool
        /// True when stdout or stderr was truncated by `maxOutputBytes`.
        let truncated: Bool
    }

    enum Failure: Error {
        case launchFailed(String)
    }

    // ── run ──────────────────────────────────────────────────────────────────

    /// Execute the command. `nonisolated` because Process work happens on a
    /// background queue; nothing here touches MainActor state.
    nonisolated static func run(
        _ command: String,
        input: Data,
        timeout: TimeInterval? = nil
    ) async throws -> Result {

        let effectiveTimeout = timeout ?? defaultTimeoutSeconds

        // ── Wire up the process ──────────────────────────────────────────
        let process = Process()
        // Absolute path avoids PATH lookup surprises and matches decision-2.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        // Environment intentionally inherited — see decision-2.

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw Failure.launchFailed(error.localizedDescription)
        }

        // ── Feed stdin on a detached task ───────────────────────────────
        // We MUST do this off the awaiting thread: if the input is bigger
        // than the OS pipe buffer (~64KiB on macOS), a synchronous write
        // blocks until the subprocess drains, and we'd deadlock if we were
        // also serialising reads from stdout/stderr on the same thread.
        let inputCopy = input
        Task.detached {
            let handle = stdinPipe.fileHandleForWriting
            // Best effort — ignore errors. If the command isn't reading
            // stdin, the write fails with a broken pipe, which is normal.
            try? handle.write(contentsOf: inputCopy)
            try? handle.close()
        }

        // ── Collect output (capped) on detached tasks ───────────────────
        // We read incrementally with a byte budget. `readToEnd` would also
        // work, but capped reads guarantee we don't hold gigabytes if the
        // user accidentally types `cat /dev/urandom`.
        async let outBytes = Self.readCapped(stdoutPipe.fileHandleForReading)
        async let errBytes = Self.readCapped(stderrPipe.fileHandleForReading)

        // ── Timeout watchdog ────────────────────────────────────────────
        let timeoutTask = Task<Bool, Never> {
            let nanos = UInt64(effectiveTimeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return false }
            if process.isRunning {
                process.terminate()
                return true
            }
            return false
        }

        // ── Wait for exit on a background queue ─────────────────────────
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }

        // CRITICAL: cancel the watchdog the moment the process exits.
        // Without this, `await timeoutTask.value` below blocks until the
        // sleep finishes naturally — i.e. every command takes the full
        // timeout duration regardless of how fast it actually ran.
        // `Task.sleep` throws `CancellationError` on cancel; we swallow it
        // with `try?` and let the task fall through to the isCancelled
        // check, where it returns `false` (no timeout).
        timeoutTask.cancel()
        let didTimeout = await timeoutTask.value

        // Readers complete when the subprocess closes its end of the pipes,
        // which happens on exit. They may have a final partial read pending.
        let (stdout, stdoutTruncated) = await outBytes
        let (stderr, stderrTruncated) = await errBytes

        return Result(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            timedOut: didTimeout,
            truncated: stdoutTruncated || stderrTruncated
        )
    }

    // ── readCapped ───────────────────────────────────────────────────────────

    /// Read up to `maxOutputBytes` from `handle`, then drain and discard.
    /// Returns the captured bytes and a flag indicating truncation.
    nonisolated private static func readCapped(
        _ handle: FileHandle
    ) async -> (Data, Bool) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(Data, Bool), Never>) in
            DispatchQueue.global().async {
                var captured = Data()
                captured.reserveCapacity(min(maxOutputBytes, 64 * 1024))
                var truncated = false

                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    if captured.count < maxOutputBytes {
                        let remaining = maxOutputBytes - captured.count
                        captured.append(chunk.prefix(remaining))
                        if chunk.count > remaining { truncated = true }
                    } else {
                        truncated = true
                        // Keep draining so the writer (the subprocess) doesn't
                        // block on a full pipe — but discard the bytes.
                    }
                }
                continuation.resume(returning: (captured, truncated))
            }
        }
    }
}

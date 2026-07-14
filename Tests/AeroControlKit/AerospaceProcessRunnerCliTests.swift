import Testing
import Foundation
@testable import AeroControlKit
@testable import Common

/// Real-process tests for `AerospaceProcessRunnerCli.run`. These drive an actual
/// child process (via `/bin/sh`) so the concurrency machinery — draining both pipes
/// to EOF, awaiting exit, timeout, non-zero-exit and cancellation — is exercised for
/// real, not through a fake. This is the only coverage of that machinery.
@Suite("AerospaceProcessRunnerCli.run")
struct AerospaceProcessRunnerCliTests {
    private static let sh = "/bin/sh"

    private func runner(timeout: Duration = .seconds(2)) -> AerospaceProcessRunnerCli {
        AerospaceProcessRunnerCli(binaryPath: Self.sh, timeout: timeout)
    }

    @Test("returns trimmed stdout on success")
    func success() async throws {
        let out = try await runner().run(["-c", "printf '  hello world  \\n'"])
        #expect(out == "hello world")
    }

    @Test("throws nonZeroExit with status and stderr")
    func nonZeroExit() async throws {
        do {
            _ = try await runner().run(["-c", "printf 'boom' >&2; exit 3"])
            Issue.record("expected nonZeroExit to throw")
        } catch let error as CLIError {
            guard case .nonZeroExit(_, let status, let stderr) = error else {
                Issue.record("expected nonZeroExit, got \(error)")
                return
            }
            #expect(status == 3)
            #expect(stderr == "boom")
        }
    }

    @Test("throws timeout (not nonZeroExit) when the child overruns")
    func timeout() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await runner(timeout: .milliseconds(300)).run(["-c", "sleep 5"])
            Issue.record("expected timeout to throw")
        } catch let error as CLIError {
            guard case .timeout = error else {
                Issue.record("expected timeout, got \(error)")
                return
            }
        }
        // Returns near the timeout, never the full 5s sleep.
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test("drains large stdout without deadlocking on a full pipe buffer")
    func largeOutput() async throws {
        // ~200 KiB, well past the ~64 KiB pipe buffer that would deadlock if the
        // reader didn't drain before we await exit.
        let out = try await runner().run(["-c", "yes 0123456789 | head -n 20000"])
        #expect(out.count >= 200_000)
    }

    @Test("terminates the child and unwinds when the task is cancelled")
    func cancellation() async throws {
        let r = runner(timeout: .seconds(30))
        let task = Task { try await r.run(["-c", "sleep 30"]) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        // Must unwind promptly (terminate on cancel), not wait out the 30s sleep.
        let start = ContinuousClock.now
        _ = await task.result
        #expect(start.duration(to: .now) < .seconds(5))
    }
}

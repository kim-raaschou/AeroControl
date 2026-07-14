import Foundation
import Common

/// The dumb process pipe to the aerospace binary — spawns processes, returns raw output.
/// Holds no aerospace-specific knowledge; callers supply args from `AerospaceCommand` (Core).
public struct AerospaceProcessRunnerCli: AerospaceProcessRunner {
    private let binaryPath: String
    private let timeout: Duration

    public init(binaryPath: String = defaultBinaryPath) {
        self.init(binaryPath: binaryPath, timeout: .seconds(2))
    }

    /// Testing seam: lets specs drive the timeout path without waiting the full 2s.
    init(binaryPath: String, timeout: Duration) {
        self.binaryPath = binaryPath
        self.timeout = timeout
    }

    public func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        let path = binaryPath
        return AsyncThrowingStream { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { _ in
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let fileHandle = pipe.fileHandleForReading
            Task.detached {
                do {
                    for try await line in fileHandle.bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                process.terminate()
            }
        }
    }

    public func run(_ args: [String]) async throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try process.run()
                    // Drain both pipes to EOF first (never blocking a pool thread). The
                    // child's write ends close as it exits, so both reads complete right
                    // as the process finishes.
                    async let outData = Self.readAll(stdoutPipe.fileHandleForReading)
                    async let errData = Self.readAll(stderrPipe.fileHandleForReading)
                    let (out, err) = await (outData, errData)
                    // EOF means the child is exiting but `terminationStatus` isn't valid
                    // until it's reaped; `reap` runs off the cooperative pool and, coming
                    // after EOF, returns almost immediately.
                    await Self.reap(process)

                    if process.terminationStatus != 0 {
                        let stderr = String(data: err, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        throw CLIError.nonZeroExit(arguments: args, status: process.terminationStatus, stderr: stderr)
                    }
                    return String(data: out, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }

                group.addTask {
                    try await Task.sleep(for: self.timeout)
                    if process.isRunning {
                        process.terminate()
                    }
                    throw CLIError.timeout(arguments: args)
                }

                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw CLIError.timeout(arguments: args)
                }
                return result
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// Reaps the child so `terminationStatus` becomes valid, off the cooperative pool.
    /// Called only after both pipes hit EOF — the child is already exiting, so the
    /// blocking `waitUntilExit()` returns almost immediately and never parks a pool
    /// thread on a live process.
    private static func reap(_ process: Process) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                cont.resume()
            }
        }
    }

    /// Reads a file handle to EOF, off the cooperative pool. Bulk `readToEnd()` on a
    /// utility queue avoids both the per-byte accumulation of an async byte stream and
    /// blocking a cooperative-pool thread.
    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { (cont: CheckedContinuation<Data, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let data = (try? handle.readToEnd()) ?? Data()
                cont.resume(returning: data)
            }
        }
    }
}

import Foundation
import Common

public struct AerospaceProcessRunnerCli: AerospaceProcessRunner {
    private let binaryPath: String
    private let timeout: Duration

    public init(binaryPath: String = defaultBinaryPath) {
        self.init(binaryPath: binaryPath, timeout: .seconds(2))
    }

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
                    async let outData = Self.readAll(stdoutPipe.fileHandleForReading)
                    async let errData = Self.readAll(stderrPipe.fileHandleForReading)
                    let (out, err) = await (outData, errData)
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
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func reap(_ process: Process) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                cont.resume()
            }
        }
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { (cont: CheckedContinuation<Data, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let data = (try? handle.readToEnd()) ?? Data()
                cont.resume(returning: data)
            }
        }
    }
}

import Foundation

/// The single I/O port to the aerospace binary — a dumb "send args → get output/stream" pipe.
/// Conceptually equivalent to aerospace's own CLI client: it has no typed knowledge of
/// specific commands. All aerospace-specific knowledge (which args, how to parse) lives in Core.
public protocol AerospaceProcessRunner: Sendable {
    /// Runs a one-shot command and returns its stdout.
    func run(_ args: [String]) async throws -> String

    /// Subscribes to a long-lived command, yielding raw stdout lines.
    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error>
}

/// Default location of the aerospace binary (Homebrew on Apple Silicon).
public let defaultBinaryPath = "/opt/homebrew/bin/aerospace"

/// Failures surfaced by the CLI transport.
public enum CLIError: Error, CustomStringConvertible {
    case timeout(arguments: [String])
    case nonZeroExit(arguments: [String], status: Int32, stderr: String)

    public var description: String {
        switch self {
        case .timeout(let args): "CLI timeout: aerospace \(args.joined(separator: " "))"
        case .nonZeroExit(let args, let status, let stderr):
            "CLI failed (exit \(status)): aerospace \(args.joined(separator: " "))\(stderr.isEmpty ? "" : " — \(stderr)")"
        }
    }
}

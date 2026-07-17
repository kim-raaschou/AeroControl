import Foundation

public protocol AerospaceProcessRunner: Sendable {
    func run(_ args: [String]) async throws -> String

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error>
}

public let defaultBinaryPath = "/opt/homebrew/bin/aerospace"

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

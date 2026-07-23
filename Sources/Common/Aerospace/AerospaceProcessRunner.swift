import Foundation

public protocol AerospaceProcessRunner: Sendable {
    func run(_ args: [String]) async throws -> String

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error>
}

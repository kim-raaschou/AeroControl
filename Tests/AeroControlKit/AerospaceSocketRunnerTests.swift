import Darwin
import Foundation
import Testing

@testable import AeroControlKit
@testable import Common

// Exercises `AerospaceSocketRunner` against a mock AeroSpace server that speaks
// the wire protocol independently (its own raw framing), so the tests validate
// our client, not our own helpers echoed back. A final live smoke test talks to
// the real AeroSpace socket when one is present.
@Suite struct AerospaceSocketRunnerTests {

    @Test func runReturnsTrimmedStdoutOnSuccess() async throws {
        let server = try MockAerospaceServer { _ in
            MockAnswer(exitCode: 0, stdout: "window one\nwindow two\n", stderr: "")
        }
        defer { server.stop() }
        let runner = AerospaceSocketRunner(socketPath: server.path)

        let output = try await runner.run(["list-windows"])

        #expect(output == "window one\nwindow two")
    }

    @Test func runForwardsArgumentsInRequest() async throws {
        let captured = Captured()
        let server = try MockAerospaceServer { request in
            captured.set(request)
            return MockAnswer(exitCode: 0, stdout: "ok", stderr: "")
        }
        defer { server.stop() }
        let runner = AerospaceSocketRunner(socketPath: server.path)

        _ = try await runner.run(["move", "left"])

        let request = try #require(captured.value)
        let args = try #require(request["args"] as? [String])
        #expect(args == ["move", "left"])
        #expect(request["stdin"] as? String == "")
        #expect(request["windowId"] is NSNull)
        #expect(request["workspace"] is NSNull)
    }

    @Test func runThrowsOnNonZeroExit() async throws {
        let server = try MockAerospaceServer { _ in
            MockAnswer(exitCode: 3, stdout: "", stderr: "no such workspace")
        }
        defer { server.stop() }
        let runner = AerospaceSocketRunner(socketPath: server.path)

        await #expect(throws: AerospaceSocketError.self) {
            try await runner.run(["workspace", "nope"])
        }
    }

    @Test func runThrowsOnProtocolMismatch() async throws {
        let server = try MockAerospaceServer(serverVersion: 999) { _ in
            MockAnswer(exitCode: 0, stdout: "", stderr: "")
        }
        defer { server.stop() }
        let runner = AerospaceSocketRunner(socketPath: server.path)

        do {
            _ = try await runner.run(["list-windows"])
            Issue.record("expected protocolMismatch to throw")
        } catch let error as AerospaceSocketError {
            guard case .protocolMismatch(let version) = error else {
                Issue.record("expected protocolMismatch, got \(error)")
                return
            }
            #expect(version == 999)
        }
    }

    @Test func subscribeStreamsEventLines() async throws {
        let events = [#"{"_event":"focus-changed","windowId":1}"#, #"{"_event":"workspace-changed"}"#]
        let server = try MockAerospaceServer(subscribeEvents: events) { _ in
            MockAnswer(exitCode: 0, stdout: "", stderr: "")
        }
        defer { server.stop() }
        let runner = AerospaceSocketRunner(socketPath: server.path)

        var received: [String] = []
        for try await line in runner.subscribe(["subscribe", "--all"]) {
            received.append(line)
            if received.count == events.count { break }
        }

        #expect(received == events)
    }

    // Talks to the actual AeroSpace socket if it exists on this machine; skipped
    // in environments (like CI) where AeroSpace is not running.
    @Test func liveSmokeAgainstRealAerospace() async throws {
        let path = AerospaceSocket.defaultSocketPath()
        guard FileManager.default.fileExists(atPath: path) else { return }
        let runner = AerospaceSocketRunner()

        let output = try await runner.run(["list-workspaces", "--all"])

        #expect(!output.isEmpty)
    }
}

// MARK: - Mock server

private struct MockAnswer {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private final class Captured: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Any]?
    func set(_ value: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        stored = value
    }
    var value: [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

/// A minimal AF_UNIX server implementing the AeroSpace handshake + length-framing
/// independently of the production helpers, used to drive the runner under test.
private final class MockAerospaceServer: @unchecked Sendable {
    let path: String
    private let listenFd: Int32
    private var running = true

    init(
        serverVersion: UInt32 = 1,
        subscribeEvents: [String] = [],
        handle: @escaping @Sendable ([String: Any]) -> MockAnswer
    ) throws {
        path = "/tmp/ac-mock-\(UUID().uuidString.prefix(8)).sock"
        listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFd >= 0 else { throw MockError.setup("socket") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        unsafe withUnsafeMutableBytes(of: &addr.sun_path) { unsafe $0.copyBytes(from: bytes) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = unsafe withUnsafePointer(to: &addr) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { unsafe bind(listenFd, $0, size) }
        }
        guard bound == 0 else { throw MockError.setup("bind errno=\(errno)") }
        guard listen(listenFd, 4) == 0 else { throw MockError.setup("listen") }

        let serverFd = listenFd
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(serverFd, nil, nil)
                if client < 0 { break }
                guard let self, self.running else { close(client); break }
                self.serve(client, serverVersion: serverVersion, subscribeEvents: subscribeEvents, handle: handle)
                close(client)
            }
        }
    }

    func stop() {
        running = false
        shutdown(listenFd, SHUT_RDWR)
        close(listenFd)
        unsafe unlink(path)
    }

    private func serve(
        _ fd: Int32,
        serverVersion: UInt32,
        subscribeEvents: [String],
        handle: @escaping @Sendable ([String: Any]) -> MockAnswer
    ) {
        do {
            _ = try readUInt32(fd)  // client protocol version
            try writeUInt32(fd, serverVersion)
            if serverVersion != 1 { return }

            let request = try readFrame(fd)
            let object = (try? JSONSerialization.jsonObject(with: request)) as? [String: Any] ?? [:]
            let answer = handle(object)

            if (object["args"] as? [String])?.first == "subscribe" {
                for event in subscribeEvents {
                    try writeFrame(fd, Array(event.utf8))
                }
                return
            }

            let payload: [String: Any] = [
                "exitCode": Int(answer.exitCode), "stdout": answer.stdout,
                "stderr": answer.stderr, "serverVersionAndHash": "mock",
            ]
            try writeFrame(fd, [UInt8](try JSONSerialization.data(withJSONObject: payload)))
        } catch {
            // Client hung up; nothing to do.
        }
    }

    // Independent framing helpers (do not reuse production internals).
    private func readUInt32(_ fd: Int32) throws -> UInt32 {
        var value: UInt32 = 0
        try unsafe readExactly(fd, into: &value, count: 4)
        return UInt32(littleEndian: value)
    }

    private func writeUInt32(_ fd: Int32, _ value: UInt32) throws {
        var little = value.littleEndian
        try unsafe withUnsafeBytes(of: &little) { try writeAll(fd, unsafe Array($0)) }
    }

    private func readFrame(_ fd: Int32) throws -> Data {
        let count = Int(try readUInt32(fd))
        var buffer = [UInt8](repeating: 0, count: count)
        try unsafe buffer.withUnsafeMutableBytes { try unsafe readExactly(fd, into: $0.baseAddress!, count: count) }
        return Data(buffer)
    }

    private func writeFrame(_ fd: Int32, _ payload: [UInt8]) throws {
        try writeUInt32(fd, UInt32(payload.count))
        try writeAll(fd, payload)
    }

    private func readExactly(_ fd: Int32, into pointer: UnsafeMutableRawPointer, count: Int) throws {
        var offset = 0
        while offset < count {
            let n = unsafe recv(fd, pointer.advanced(by: offset), count - offset, 0)
            if n <= 0 { throw MockError.io }
            offset += n
        }
    }

    private func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = unsafe bytes.withUnsafeBytes { unsafe send(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset, 0) }
            if n <= 0 { throw MockError.io }
            offset += n
        }
    }

    enum MockError: Error { case setup(String), io }
}

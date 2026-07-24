import Common
import Darwin
import Foundation

/// The AeroSpace socket wire-protocol version this runner speaks.
public let aerospaceSocketProtocolVersion: UInt32 = 1

public enum AerospaceSocketError: Error, CustomStringConvertible {
    case io(String)
    case protocolMismatch(UInt32)
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .io(let m): "AeroSpace socket: \(m)"
        case .protocolMismatch(let v):
            "AeroSpace socket protocol version \(v) (expected \(aerospaceSocketProtocolVersion))"
        case .commandFailed(let args, let code, let stderr):
            "AeroSpace command failed (exit \(code)): \(args.joined(separator: " "))\(stderr.isEmpty ? "" : " — \(stderr)")"
        }
    }
}

/// Sends AeroSpace commands over its Unix socket instead of spawning the
/// `aerospace` CLI. It speaks AeroSpace's wire protocol: AF_UNIX connect, a
/// `UInt32` protocol-version handshake in both directions, then length-prefixed
/// (`[UInt32 little-endian length][JSON]`) request/response framing.
///
/// Each `run` uses a fresh connection (connect + handshake are sub-millisecond
/// on a Unix socket, measured indistinguishable from a reused connection), so
/// there is no persistent state, no reconnect logic, and no ambiguous command
/// replay. `subscribe` streams events over its own dedicated connection on a
/// background thread. We trust AeroSpace as the source of truth: the only guard
/// is the protocol-version handshake, and any transport failure surfaces as a
/// thrown error rather than a fallback.
///
/// The blocking `connect`/`send`/`recv` syscalls run on a private concurrent
/// `DispatchQueue`, never on the Swift cooperative pool: those calls have no
/// timeout (we trust AeroSpace), so an alive-but-hung daemon would otherwise
/// park a fixed cooperative thread — and `Task` cancellation can't interrupt a
/// blocking `recv`. Offloading confines that cost to an elastic GCD worker.
public struct AerospaceSocketRunner: AerospaceProcessRunner {
    private let socketPath: String

    /// Concurrent queue for blocking socket round-trips, keeping them off the
    /// cooperative pool. Elastic: each in-flight `run` gets its own worker.
    private static let ioQueue = DispatchQueue(
        label: "com.aerocontrol.aerospace-socket.run",
        attributes: .concurrent
    )

    public init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? AerospaceSocket.defaultSocketPath()
    }

    public func run(_ args: [String]) async throws -> String {
        let socketPath = socketPath
        return try await withCheckedThrowingContinuation { continuation in
            Self.ioQueue.async {
                continuation.resume(with: Result {
                    try AerospaceSocketRunner.runBlocking(socketPath: socketPath, args: args)
                })
            }
        }
    }

    private static func runBlocking(socketPath: String, args: [String]) throws -> String {
        let fd = try AerospaceSocket.connectAndHandshake(socketPath)
        defer { Darwin.close(fd) }
        try AerospaceSocket.writeFrame(fd, AerospaceSocket.encodeRequest(args))
        let answer = try AerospaceSocket.decodeAnswer(AerospaceSocket.readFrame(fd))
        if answer.exitCode != 0 {
            throw AerospaceSocketError.commandFailed(
                arguments: args,
                exitCode: answer.exitCode,
                stderr: answer.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return answer.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        AerospaceSocket.subscribeStream(socketPath: socketPath, args: args)
    }
}

/// Low-level socket framing shared by the command and subscribe paths, split out
/// so tests can drive the runner against a mock AF_UNIX server.
enum AerospaceSocket {
    struct ServerAnswer: Decodable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func defaultSocketPath() -> String {
        "/tmp/bobko.aerospace-\(NSUserName()).sock"
    }

    static func encodeRequest(_ args: [String]) throws -> [UInt8] {
        // Mirror the CLI's ClientRequest, with explicit nulls for the window-id /
        // workspace context fields AeroSpace forwards from the environment.
        let object: [String: Any] = [
            "args": args, "stdin": "", "windowId": NSNull(), "workspace": NSNull(),
        ]
        return [UInt8](try JSONSerialization.data(withJSONObject: object))
    }

    static func decodeAnswer(_ data: Data) throws -> ServerAnswer {
        do {
            return try JSONDecoder().decode(ServerAnswer.self, from: data)
        } catch {
            throw AerospaceSocketError.io("could not decode server answer: \(error)")
        }
    }

    /// Streams raw ServerEvent JSON lines over a dedicated subscribe connection.
    /// A dedicated `Thread` owns the blocking read loop so it never parks a
    /// Swift-concurrency cooperative thread; `shutdown` + `close` from the
    /// stream's termination handler unblocks and tears it down.
    static func subscribeStream(socketPath: String, args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let handle = SocketHandle()
            let thread = Thread {
                let fd: Int32
                do {
                    fd = try connectAndHandshake(socketPath)
                } catch {
                    continuation.finish(throwing: handle.isCancelled ? nil : error)
                    return
                }
                // The worker owns the fd for its whole lifetime and is the only
                // one that closes it; cancellation merely shuts it down to
                // interrupt the blocking read, so the descriptor is never freed
                // out from under this thread (no fd-reuse race). A cancel during
                // the handshake itself is intentionally not interrupted — that
                // only matters if AeroSpace accepts then hangs mid-handshake,
                // which our trust model rules out.
                defer { handle.closeOwned(fd) }
                do {
                    if handle.register(fd) {
                        try writeFrame(fd, encodeRequest(args))
                        while !handle.isCancelled {
                            let body = try readFrame(fd)
                            if let line = String(data: body, encoding: .utf8) {
                                continuation.yield(line)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: handle.isCancelled ? nil : error)
                }
            }
            thread.stackSize = 512 * 1024
            thread.start()
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    static func connectAndHandshake(_ socketPath: String) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw AerospaceSocketError.io("socket() errno=\(errno)") }
        var ok = false
        defer { if !ok { Darwin.close(fd) } }

        // Turn a peer close/restart mid-write into an EPIPE error instead of a
        // process-killing SIGPIPE; without it our error handling never runs.
        var noSigPipe: Int32 = 1
        if unsafe setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) != 0 {
            throw AerospaceSocketError.io("setsockopt(SO_NOSIGPIPE) errno=\(errno)")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        if pathBytes.count >= MemoryLayout.size(ofValue: addr.sun_path) {
            throw AerospaceSocketError.io("socket path too long: \(socketPath)")
        }
        unsafe withUnsafeMutableBytes(of: &addr.sun_path) { unsafe $0.copyBytes(from: pathBytes) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = unsafe withUnsafePointer(to: &addr) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { unsafe connect(fd, $0, size) }
        }
        if rc != 0 { throw AerospaceSocketError.io("connect() errno=\(errno) path=\(socketPath)") }

        try writeUInt32(fd, aerospaceSocketProtocolVersion)
        // The server always sends its version next; we must read it to stay
        // frame-aligned, and a mismatch means we cannot trust the framing.
        let serverVersion = try readUInt32(fd)
        if serverVersion != aerospaceSocketProtocolVersion {
            throw AerospaceSocketError.protocolMismatch(serverVersion)
        }
        ok = true
        return fd
    }

    static func writeFrame(_ fd: Int32, _ payload: [UInt8]) throws {
        try writeUInt32(fd, UInt32(payload.count))
        try writeAll(fd, payload)
    }

    static func readFrame(_ fd: Int32) throws -> Data {
        Data(try readExactly(fd, Int(try readUInt32(fd))))
    }

    private static func writeUInt32(_ fd: Int32, _ value: UInt32) throws {
        var little = value.littleEndian
        try writeAll(fd, unsafe withUnsafeBytes(of: &little) { unsafe Array($0) })
    }

    private static func readUInt32(_ fd: Int32) throws -> UInt32 {
        let bytes = try readExactly(fd, 4)
        return unsafe bytes.withUnsafeBytes { unsafe UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }

    private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = unsafe bytes.withUnsafeBytes { unsafe send(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset, 0) }
            if n <= 0 { throw AerospaceSocketError.io("send errno=\(errno)") }
            offset += n
        }
    }

    private static func readExactly(_ fd: Int32, _ count: Int) throws -> [UInt8] {
        if count == 0 { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let n = unsafe buffer.withUnsafeMutableBytes { unsafe recv(fd, $0.baseAddress!.advanced(by: offset), count - offset, 0) }
            if n <= 0 { throw AerospaceSocketError.io("recv errno=\(errno) (eof=\(n == 0))") }
            offset += n
        }
        return buffer
    }
}

/// Coordinates ownership of the subscribe connection's descriptor between the
/// worker thread that performs the blocking reads and the stream's termination
/// handler. The worker is the sole closer of the fd; cancellation only flips the
/// flag and `shutdown`s the socket to interrupt the blocking read, so the
/// descriptor number is never freed while the worker might still use it.
private final class SocketHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Registers the worker-owned fd. Returns false if the stream was already
    /// cancelled, in which case the worker should not start the read loop (it
    /// still owns and must close the fd via `closeOwned`).
    func register(_ value: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        fd = value
        return true
    }

    /// Called from the stream's termination handler on any thread: request stop
    /// and interrupt the blocking read without freeing the descriptor.
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if fd >= 0 { Darwin.shutdown(fd, SHUT_RDWR) }
    }

    /// Called once by the owning worker thread as it exits; performs the sole
    /// `close` of the descriptor.
    func closeOwned(_ value: Int32) {
        lock.lock(); defer { lock.unlock() }
        fd = -1
        Darwin.close(value)
    }
}

import Foundation

/// Enforces a single running instance per user via an advisory file lock.
///
/// The first process to acquire an exclusive, non-blocking `flock` on the lock
/// file wins; subsequent processes fail to acquire it and should exit. The lock
/// is held for the lifetime of the process — the kernel releases it
/// automatically when the file descriptor is closed or the process terminates,
/// so a crash never leaves a stale lock behind.
public final class SingleInstanceGuard {
    private var fileDescriptor: Int32 = -1

    public init() {}

    /// Attempts to acquire the lock. Returns `true` if this is the only running
    /// instance, `false` if another instance already holds the lock.
    public func tryAcquire(name: String) -> Bool {
        // NSTemporaryDirectory() is per-user on macOS, so the lock is scoped to
        // the current user.
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        let fd = unsafe open(path, O_CREAT | O_RDWR, 0o600)
        guard fd != -1 else { return false }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }

        fileDescriptor = fd

        // Record our PID so a later invocation can find and signal us (toggle
        // behavior): "run again" sends SIGUSR1 to the holder, which toggles visibility.
        ftruncate(fd, 0)
        let pidLine = "\(getpid())\n"
        _ = unsafe pidLine.withCString { unsafe write(fd, $0, strlen($0)) }

        return true
    }

    /// Reads the PID recorded by the instance currently holding the lock, if any.
    /// Used by a second invocation to signal the running instance to toggle visibility.
    public func runningInstancePID(name: String) -> pid_t? {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(trimmed), pid > 0 else { return nil }
        return pid
    }

    deinit {
        if fileDescriptor != -1 {
            flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
        }
    }
}

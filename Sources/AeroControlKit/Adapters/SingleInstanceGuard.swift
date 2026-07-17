import Foundation

public final class SingleInstanceGuard {
    private var fileDescriptor: Int32 = -1

    public init() {}

    public func tryAcquire(name: String) -> Bool {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        let fd = unsafe open(path, O_CREAT | O_RDWR, 0o600)
        guard fd != -1 else { return false }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }

        fileDescriptor = fd

        ftruncate(fd, 0)
        let pidLine = "\(getpid())\n"
        _ = unsafe pidLine.withCString { unsafe write(fd, $0, strlen($0)) }

        return true
    }

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

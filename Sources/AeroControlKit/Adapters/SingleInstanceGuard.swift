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
        return true
    }

    deinit {
        if fileDescriptor != -1 {
            flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
        }
    }
}

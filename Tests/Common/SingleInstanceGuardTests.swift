import Foundation
import Testing
@testable import AeroControlKit

private func uniqueName() -> String {
    "aerocontrol.test.\(UUID().uuidString).lock"
}

@Suite("SingleInstanceGuard")
struct SingleInstanceGuardTests {

    @Test("first acquire succeeds")
    func firstAcquireSucceeds() {
        let guard1 = SingleInstanceGuard()
        #expect(guard1.tryAcquire(name: uniqueName()))
    }

    @Test("second acquire on the same name fails while the first is alive")
    func secondAcquireOnSameNameFails() {
        let name = uniqueName()
        let guard1 = SingleInstanceGuard()
        #expect(guard1.tryAcquire(name: name))

        let guard2 = SingleInstanceGuard()
        #expect(!guard2.tryAcquire(name: name))

        // Keep guard1 alive until after the second attempt.
        withExtendedLifetime(guard1) {}
    }

    @Test("acquire succeeds again after the first guard is released")
    func acquireSucceedsAgainAfterFirstGuardReleased() {
        let name = uniqueName()

        do {
            let guard1 = SingleInstanceGuard()
            #expect(guard1.tryAcquire(name: name))
        } // guard1 deinit's here, releasing the lock

        let guard2 = SingleInstanceGuard()
        #expect(guard2.tryAcquire(name: name))
    }

    @Test("runningInstancePID returns the holder's pid")
    func runningInstancePIDReturnsHolderPID() {
        let name = uniqueName()
        let guard1 = SingleInstanceGuard()
        #expect(guard1.tryAcquire(name: name))

        // A second invocation can discover the running instance's PID to signal it.
        let guard2 = SingleInstanceGuard()
        #expect(guard2.runningInstancePID(name: name) == getpid())

        withExtendedLifetime(guard1) {}
    }

    @Test("runningInstancePID is nil when there is no lock file")
    func runningInstancePIDNilWhenNoLockFile() {
        let guard1 = SingleInstanceGuard()
        #expect(guard1.runningInstancePID(name: uniqueName()) == nil)
    }
}

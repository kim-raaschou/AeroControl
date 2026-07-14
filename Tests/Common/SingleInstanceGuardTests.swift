import XCTest
@testable import AeroControlKit

final class SingleInstanceGuardTests: XCTestCase {
    private func uniqueName() -> String {
        "aerocontrol.test.\(UUID().uuidString).lock"
    }

    func testFirstAcquireSucceeds() {
        let guard1 = SingleInstanceGuard()
        XCTAssertTrue(guard1.tryAcquire(name: uniqueName()))
    }

    func testSecondAcquireOnSameNameFails() {
        let name = uniqueName()
        let guard1 = SingleInstanceGuard()
        XCTAssertTrue(guard1.tryAcquire(name: name))

        let guard2 = SingleInstanceGuard()
        XCTAssertFalse(guard2.tryAcquire(name: name))

        // Keep guard1 alive until after the second attempt.
        withExtendedLifetime(guard1) {}
    }

    func testAcquireSucceedsAgainAfterFirstGuardReleased() {
        let name = uniqueName()

        do {
            let guard1 = SingleInstanceGuard()
            XCTAssertTrue(guard1.tryAcquire(name: name))
        } // guard1 deinit's here, releasing the lock

        let guard2 = SingleInstanceGuard()
        XCTAssertTrue(guard2.tryAcquire(name: name))
    }

    func testRunningInstancePIDReturnsHolderPID() {
        let name = uniqueName()
        let guard1 = SingleInstanceGuard()
        XCTAssertTrue(guard1.tryAcquire(name: name))

        // A second invocation can discover the running instance's PID to signal it.
        let guard2 = SingleInstanceGuard()
        XCTAssertEqual(guard2.runningInstancePID(name: name), getpid())

        withExtendedLifetime(guard1) {}
    }

    func testRunningInstancePIDNilWhenNoLockFile() {
        let guard1 = SingleInstanceGuard()
        XCTAssertNil(guard1.runningInstancePID(name: uniqueName()))
    }
}

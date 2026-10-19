import XCTest
@testable import AutoCleanMacCore

private final class FakeApp: TerminatableApp, @unchecked Sendable {
    let quitsOnTerminate: Bool
    let diesOnForce: Bool
    private(set) var terminateCalls = 0
    private(set) var forceCalls = 0
    private(set) var hasExited = false

    init(quitsOnTerminate: Bool, diesOnForce: Bool = true) {
        self.quitsOnTerminate = quitsOnTerminate
        self.diesOnForce = diesOnForce
    }

    func terminate() -> Bool {
        terminateCalls += 1
        if quitsOnTerminate { hasExited = true }
        return true
    }

    func forceTerminate() -> Bool {
        forceCalls += 1
        if diesOnForce { hasExited = true }
        return true
    }
}

final class AppTerminatorTests: XCTestCase {
    private func makeTerminator(_ apps: [FakeApp]) -> ShellAppTerminator {
        ShellAppTerminator(
            runningApps: { _ in apps },
            gracefulTimeout: 0.2,
            forceTimeout: 0.2,
            pollInterval: 0.01
        )
    }

    func test_not_running_returns_true_without_signals() async {
        let result = await makeTerminator([]).terminate(bundleID: "com.example.App", executableName: nil)
        XCTAssertTrue(result)
    }

    func test_graceful_quit_does_not_force() async {
        let app = FakeApp(quitsOnTerminate: true)
        let result = await makeTerminator([app]).terminate(bundleID: "com.example.App", executableName: nil)
        XCTAssertTrue(result)
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceCalls, 0)
    }

    func test_force_terminates_after_graceful_timeout() async {
        let app = FakeApp(quitsOnTerminate: false)
        let result = await makeTerminator([app]).terminate(bundleID: "com.example.App", executableName: nil)
        XCTAssertTrue(result)
        XCTAssertEqual(app.forceCalls, 1)
    }

    func test_returns_false_within_timeout_when_app_survives() async {
        let app = FakeApp(quitsOnTerminate: false, diesOnForce: false)
        let start = Date()
        let result = await makeTerminator([app]).terminate(bundleID: "com.example.App", executableName: nil)
        XCTAssertFalse(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}

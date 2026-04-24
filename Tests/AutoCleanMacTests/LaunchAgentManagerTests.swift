import XCTest
@testable import AutoCleanMac

final class LaunchAgentManagerTests: XCTestCase {
    func test_launchAgentPlist_contains_expected_program_arguments_and_logs() throws {
        let plist = LaunchAgentManager.launchAgentPlist(
            appBinaryPath: "/Users/test/Applications/AutoCleanMac.app/Contents/MacOS/AutoCleanMac",
            logsDirectoryPath: "/Users/test/Library/Logs/AutoCleanMac"
        )
        let data = try XCTUnwrap(plist.data(using: .utf8))
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dict = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(dict["Label"] as? String, "com.micz.autocleanmac")
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(dict["KeepAlive"] as? Bool, false)
        XCTAssertEqual(dict["ProcessType"] as? String, "Interactive")
        XCTAssertEqual(dict["ProgramArguments"] as? [String], [
            "/Users/test/Applications/AutoCleanMac.app/Contents/MacOS/AutoCleanMac",
            "--launch-agent",
        ])
        XCTAssertEqual(
            dict["StandardOutPath"] as? String,
            "/Users/test/Library/Logs/AutoCleanMac/launchd.out.log"
        )
        XCTAssertEqual(
            dict["StandardErrorPath"] as? String,
            "/Users/test/Library/Logs/AutoCleanMac/launchd.err.log"
        )
    }
}

import Testing
@testable import AutoCleanMacCore

@Suite struct SmokeTests {
    @Test func test_version_is_defined() {
        #expect(!AutoCleanMacCore.version.isEmpty)
    }
}

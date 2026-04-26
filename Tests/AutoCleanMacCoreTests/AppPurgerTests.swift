import XCTest
@testable import AutoCleanMacCore

final class SpyPreferencesDaemon: PreferencesDaemonClient, @unchecked Sendable {
    var calls: [String] = []
    func deleteAll(bundleID: String) -> Bool {
        calls.append(bundleID)
        return true
    }
}

final class SpyLaunchAgentClient: LaunchAgentClient, @unchecked Sendable {
    struct Call: Equatable { let plist: URL; let isSystem: Bool }
    var calls: [Call] = []
    func unload(plist: URL, domain: LaunchAgentDomain) -> Bool {
        calls.append(Call(plist: plist, isSystem: { if case .system = domain { return true } else { return false } }()))
        return true
    }
}

final class AppPurgerTests: XCTestCase {
    // Faktyczne testy w Phase 3.
}

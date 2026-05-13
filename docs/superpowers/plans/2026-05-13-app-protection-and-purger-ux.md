# AppProtectionGuard + AppPurger UX Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) Add a hard safety gate that prevents `AppPurger` from removing system-critical apps (Finder, Dock, Settings, etc.) while still permitting uninstall of user-installed Apple apps (Xcode, iWork, etc.). (2) Bring AppPurger to feature parity with `__mole/lib/uninstall/batch.sh` for the UX-critical small-effort items: graceful-then-forceful process termination, removal from macOS Login Items, and LaunchServices unregister + post-batch rebuild.

**Architecture:** Each new responsibility becomes a `Sendable` protocol + shell-backed implementation, mirroring the existing `LaunchAgentClient`/`PreferencesDaemonClient` pattern. `AppProtectionGuard` is a value-only struct with bundle ID matching (no I/O). `AppPurger` gains four new injected dependencies and a new pre-flight `guard` check that returns a `protected` failure without touching disk. Post-batch LaunchServices rebuild is fired once by `AppDelegate` after `onUninstall` iterates all selected apps. TDD throughout with `XCTest` spies modeled after `SpyPreferencesDaemon` in `AppPurgerTests.swift`.

**Tech Stack:** Swift 5.9, XCTest, Foundation, `Process` for shell calls (`/usr/bin/osascript`, `/bin/launchctl`, `/usr/bin/pkill`, `/System/Library/Frameworks/CoreServices.framework/.../lsregister`).

---

## File Structure

**New files (5):**

- `Sources/AutoCleanMacCore/AppProtectionGuard.swift` — pure-Swift bundle-ID protection logic. No I/O. Exports `AppProtectionGuard.isProtected(bundleID:) -> Bool` and protection metadata.
- `Sources/AutoCleanMacCore/AppTerminator.swift` — protocol + `ShellAppTerminator` for graceful Quit → SIGTERM → SIGKILL → admin SIGKILL ladder.
- `Sources/AutoCleanMacCore/LoginItemsClient.swift` — protocol + `ShellLoginItemsClient` for osascript-driven removal from Login Items.
- `Sources/AutoCleanMacCore/LaunchServicesClient.swift` — protocol + `ShellLaunchServicesClient` exposing `unregister(app:)` and `rebuild()`.
- `Tests/AutoCleanMacCoreTests/AppProtectionGuardTests.swift` — covers protection patterns & allow-list.

**Modified files (3):**

- `Sources/AutoCleanMacCore/AppPurger.swift` — adds guard rejection path, new injected dependencies (`terminator`, `loginItems`, `launchServices`), and call ordering (terminate → unregister → loginItems → delete).
- `Sources/AutoCleanMacCore/AppScanner.swift` — filters out protected bundle IDs (replaces hand-coded `com.apple.` prefix check at line 57).
- `Sources/AutoCleanMac/AppDelegate.swift` — instantiates shell clients, threads them into `AppPurger`, and calls `launchServices.rebuild()` once after batch.
- `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift` — new spies and integration tests for guard rejection + call ordering.

---

## Task 1: AppProtectionGuard — bundle ID protection data

**Files:**
- Create: `Sources/AutoCleanMacCore/AppProtectionGuard.swift`
- Test: `Tests/AutoCleanMacCoreTests/AppProtectionGuardTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AutoCleanMacCoreTests/AppProtectionGuardTests.swift`:

```swift
import XCTest
@testable import AutoCleanMacCore

final class AppProtectionGuardTests: XCTestCase {
    func test_finder_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.finder"))
    }

    func test_dock_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.dock"))
    }

    func test_system_settings_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.systempreferences"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.SystemSettings"))
    }

    func test_system_settings_panel_wildcard_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.Settings.AppleAccount"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.Settings.Wifi"))
    }

    func test_control_center_wildcard_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.controlcenter"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.controlcenter.Bluetooth"))
    }

    func test_xcode_is_uninstallable_despite_apple_prefix() {
        // com.apple.dt.* is on the explicit allow-list (Xcode, Instruments, etc.)
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.dt.Xcode"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.dt.Instruments"))
    }

    func test_iwork_apps_are_uninstallable() {
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.iWork.Pages"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.iWork.Numbers"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.iWork.Keynote"))
    }

    func test_final_cut_pro_is_uninstallable() {
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.FinalCut"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.FinalCutPro"))
    }

    func test_third_party_apps_are_not_protected() {
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.example.MyApp"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.spotify.client"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.google.Chrome"))
    }

    func test_empty_bundle_id_is_protected_defensively() {
        // Defensive default: refuse to act on an empty/unknown bundle id.
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: ""))
    }

    func test_loginwindow_legacy_token_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "loginwindow"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.loginwindow"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppProtectionGuardTests`
Expected: build failure — `AppProtectionGuard` is not defined.

- [ ] **Step 3: Create AppProtectionGuard implementation**

Create `Sources/AutoCleanMacCore/AppProtectionGuard.swift`:

```swift
import Foundation

/// Bezpiecznościowa zapora przed usunięciem komponentów systemowych.
/// Czysto wartościowa — bez I/O. Logika oparta na `__mole/lib/core/app_protection.sh`.
///
/// Reguła: `isProtected = matchesSystemCritical && !matchesAppleUninstallable`.
/// Pusty bundle ID jest traktowany jako chroniony (defensywny default).
public enum AppProtectionGuard {

    /// Lista wzorców bundle ID krytycznych dla systemu — chronione przed odinstalowaniem.
    /// Wzorce wspierają `*` jako wildcard (konwertowany do `.*` w regex).
    public static let systemCriticalPatterns: [String] = [
        // Core macOS shell
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.Settings.*",
        "com.apple.controlcenter",
        "com.apple.controlcenter.*",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.AppStore",

        // System utility apps (built-in, in /System/Applications)
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.Photos",
        "com.apple.calculator",
        "com.apple.Dictionary",
        "com.apple.ScreenSharing",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility",
        "com.apple.KeychainAccess",
        "com.apple.Terminal",
        "com.apple.ScriptEditor2",
        "com.apple.FontBook",
        "com.apple.SystemProfiler",
        "com.apple.audio.AudioMIDISetup",
        "com.apple.MigrateAssistant",
        "com.apple.BootCampAssistant",

        // System services / daemons / frameworks
        "com.apple.SecurityAgent",
        "com.apple.CoreServices.*",
        "com.apple.SystemUIServer",
        "com.apple.backgroundtaskmanagement.*",
        "com.apple.loginitems.*",
        "com.apple.sharedfilelist.*",
        "com.apple.sfl.*",
        "com.apple.installer.*",
        "com.apple.security.*",
        "com.apple.keychain.*",
        "com.apple.trustd",
        "com.apple.securityd",
        "com.apple.cloudd",
        "com.apple.iCloud.*",
        "com.apple.WiFi.*",
        "com.apple.Bluetooth.*",

        // Input methods (system built-in)
        "com.apple.inputmethod.*",
        "com.apple.inputsource.*",
        "com.apple.TextInput.*",
        "com.apple.CharacterPicker.*",
        "com.apple.PressAndHold.*",

        // Legacy short tokens (some apps use plain names, not reverse-DNS)
        "loginwindow",
        "dock",
        "systempreferences",
        "finder",
        "safari",
    ]

    /// Lista aplikacji od Apple, które MOGĄ być odinstalowane (App Store / developer.apple.com).
    /// Te wzorce nadpisują `systemCriticalPatterns` gdy oba pasują.
    public static let appleUninstallablePatterns: [String] = [
        "com.apple.dt.*",          // Xcode, Instruments, FileMerge
        "com.apple.FinalCut.*",
        "com.apple.FinalCut",
        "com.apple.FinalCutPro",
        "com.apple.Motion",
        "com.apple.Compressor",
        "com.apple.logic.*",
        "com.apple.garageband.*",
        "com.apple.iMovie",
        "com.apple.iWork.*",
        "com.apple.MainStage.*",
        "com.apple.server.*",
        "com.apple.Playgrounds",
    ]

    /// Zwraca `true` jeśli aplikacji o danym bundle ID nie wolno odinstalowywać.
    public static func isProtected(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return true }
        if matches(bundleID: bundleID, patterns: appleUninstallablePatterns) {
            return false
        }
        return matches(bundleID: bundleID, patterns: systemCriticalPatterns)
    }

    private static func matches(bundleID: String, patterns: [String]) -> Bool {
        for pattern in patterns where wildcardMatch(bundleID, pattern: pattern) {
            return true
        }
        return false
    }

    /// Glob-style match: `*` w pattern = `.*` w regex. Reszta znaków eskejpowana.
    /// Case-sensitive (bundle ID-y są case-sensitive na APFS i w LaunchServices).
    private static func wildcardMatch(_ input: String, pattern: String) -> Bool {
        var regex = "^"
        for ch in pattern {
            if ch == "*" {
                regex += ".*"
            } else if ".\\+?()[]{}|^$".contains(ch) {
                regex += "\\\(ch)"
            } else {
                regex += String(ch)
            }
        }
        regex += "$"
        return input.range(of: regex, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppProtectionGuardTests`
Expected: all 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/AppProtectionGuard.swift Tests/AutoCleanMacCoreTests/AppProtectionGuardTests.swift
git commit -m "feat: add AppProtectionGuard with system-critical bundle ID lists"
```

---

## Task 2: AppScanner filters out protected apps

**Files:**
- Modify: `Sources/AutoCleanMacCore/AppScanner.swift:56-58`

Replaces the hand-rolled `bundleID.hasPrefix("com.apple.")` filter with the centralized guard so user-installed Apple apps (Xcode, iWork) re-appear in the uninstaller list.

- [ ] **Step 1: Write the failing test**

Append to `Tests/AutoCleanMacCoreTests/AppProtectionGuardTests.swift`:

```swift
    func test_appscanner_uses_guard_for_filtering() async throws {
        // This is a small integration check — we don't spin up a real bundle,
        // we just confirm the guard would let Xcode through.
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.dt.Xcode"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.finder"))
    }
```

Then add to `Tests/AutoCleanMacCoreTests/SmokeTests.swift` (or create new `AppScannerTests.swift` if cleaner) a test using a fake bundle directory. Simpler: rely on the guard tests for behaviour; this task is a refactor.

- [ ] **Step 2: Run tests to verify it fails or that current state is unchanged**

Run: `swift test --filter AppProtectionGuardTests`
Expected: test from Task 1 still passes. Add `appscanner_uses_guard_for_filtering` test — should pass once we make the AppScanner change (it only asserts on the guard itself).

- [ ] **Step 3: Replace the filter in AppScanner**

Open `Sources/AutoCleanMacCore/AppScanner.swift`, replace lines 55-59 (the Bundle/bundleID extraction block) with:

```swift
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !AppProtectionGuard.isProtected(bundleID: bundleID) else {
            return nil
        }
```

Also remove the no-longer-needed `/System/` and `/Applications/Utilities/` path prefix guards on lines 52-53 — the bundle-ID check is now authoritative (Finder, Dock etc. all match their bundle IDs regardless of disk path). Leave them in for now if you prefer belt-and-suspenders; they are not wrong, just redundant.

Conservative version (keep path guards as defense-in-depth):

```swift
    private func processApp(at url: URL, homeDirectory: URL, fileManager: FileManager) async -> AppInfo? {
        guard !url.path.hasPrefix("/System/") else { return nil }

        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !AppProtectionGuard.isProtected(bundleID: bundleID) else {
            return nil
        }
```

(Drop the `/Applications/Utilities/` line — it incorrectly filtered out third-party utilities. The guard now handles built-in utilities by bundle ID.)

- [ ] **Step 4: Run full test suite**

Run: `swift test`
Expected: all existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/AppScanner.swift Tests/AutoCleanMacCoreTests/AppProtectionGuardTests.swift
git commit -m "refactor(AppScanner): use AppProtectionGuard to filter system apps"
```

---

## Task 3: AppPurger refuses to purge protected apps

**Files:**
- Modify: `Sources/AutoCleanMacCore/AppPurger.swift`
- Modify: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`

Defense in depth: even if AppScanner is bypassed, AppPurger must refuse.

- [ ] **Step 1: Write the failing test**

Append to `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift` (inside `final class AppPurgerTests`):

```swift
    func test_purge_refuses_to_remove_protected_app() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Finder.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: appURL.appendingPathComponent("contents"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let prefs = SpyPreferencesDaemon()
        let purger = AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: prefs,
            launchAgents: SpyLaunchAgentClient(),
            elevatedRemove: { _ in XCTFail("Protected app must not trigger elevation") },
            logger: logger
        )

        let outcome = await purger.purge(
            bundleID: "com.apple.finder",
            displayName: "Finder",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertFalse(outcome.appRemoved)
        XCTAssertEqual(outcome.bytesFreed, 0)
        XCTAssertEqual(outcome.itemsDeleted, 0)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures.first?.path, appURL.path)
        XCTAssertTrue(outcome.failures.first?.reason.contains("protected") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(prefs.calls.isEmpty, "prefs daemon must not be called for protected apps")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppPurgerTests/test_purge_refuses_to_remove_protected_app`
Expected: FAIL — `appRemoved` is `true` (Finder.app gets deleted because there is no guard yet).

- [ ] **Step 3: Add guard check at top of `purge` in AppPurger.swift**

In `Sources/AutoCleanMacCore/AppPurger.swift`, insert at the very top of the `purge` function body (right after `let fm = FileManager.default`):

```swift
        // Hard safety gate: never act on a protected bundle ID.
        if AppProtectionGuard.isProtected(bundleID: bundleID) {
            logger.log(event: "purge_refused", fields: ["bundle": bundleID, "reason": "protected"])
            return PurgeOutcome(
                appRemoved: false,
                bytesFreed: 0,
                itemsDeleted: 0,
                elevatedFallbackUsed: false,
                failures: [PurgeFailure(path: appURL.path, reason: "Aplikacja chroniona przez AppProtectionGuard (\(bundleID))")]
            )
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppPurgerTests`
Expected: all AppPurger tests including the new one PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/AppPurger.swift Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "feat(AppPurger): refuse to purge bundle IDs covered by AppProtectionGuard"
```

---

## Task 4: AppTerminator protocol + shell implementation

**Files:**
- Create: `Sources/AutoCleanMacCore/AppTerminator.swift`

The terminator is best-effort — there is no point unit-testing the shell ladder live (it touches global process state). We define the protocol and a thin shell impl; the integration test in Task 5 uses a spy.

- [ ] **Step 1: Create the protocol + shell impl**

Create `Sources/AutoCleanMacCore/AppTerminator.swift`:

```swift
import Foundation

/// Best-effort terminacja działającej aplikacji przed jej usunięciem.
/// Logika oparta na `__mole/lib/core/app_protection.sh:force_kill_app`.
public protocol AppTerminator: Sendable {
    /// Próbuje zamknąć aplikację. Sukces oznacza, że proces nie żyje po wywołaniu;
    /// zwrócenie `false` oznacza, że proces *może* nadal żyć (uninstall powinien iść dalej —
    /// macOS pozwala usunąć działający bundle).
    func terminate(bundleID: String, executableName: String?) async -> Bool
}

public struct ShellAppTerminator: AppTerminator {
    public init() {}

    public func terminate(bundleID: String, executableName: String?) async -> Bool {
        let match = executableName?.isEmpty == false ? executableName! : bundleID

        guard isRunning(match: match) else { return true }

        // 1) Apple Event "quit" przez osascript — zarządza Tauri/Electron/SwiftUI poprawnie.
        if !bundleID.isEmpty {
            _ = await runWithTimeout(seconds: 3) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", "tell application id \"\(bundleID)\" to quit"]
                let null = FileHandle(forWritingAtPath: "/dev/null")
                p.standardOutput = null
                p.standardError = null
                try? p.run()
                p.waitUntilExit()
            }
            // Daj procesowi do 2s na łagodne zamknięcie.
            for _ in 0..<20 {
                if !isRunning(match: match) { return true }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        // 2) SIGTERM
        runPkill(args: ["-x", match])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if !isRunning(match: match) { return true }

        // 3) SIGKILL
        runPkill(args: ["-9", "-x", match])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        return !isRunning(match: match)
    }

    private func isRunning(match: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", match]
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runPkill(args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = args
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null
        try? p.run()
        p.waitUntilExit()
    }

    private func runWithTimeout(seconds: TimeInterval, _ work: @escaping @Sendable () -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                work()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: build succeeds. (No tests yet — integration test comes in Task 5.)

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCleanMacCore/AppTerminator.swift
git commit -m "feat: add AppTerminator protocol and ShellAppTerminator (quit→TERM→KILL ladder)"
```

---

## Task 5: AppPurger calls AppTerminator before deletion

**Files:**
- Modify: `Sources/AutoCleanMacCore/AppPurger.swift`
- Modify: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift` (above the closing `}` of `AppPurgerTests` class):

```swift
    func test_purge_invokes_terminator_before_deletion() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let terminator = SpyAppTerminator()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: terminator,
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertEqual(terminator.calls, [SpyAppTerminator.Call(bundleID: "com.example.Tiny", executableName: nil)])
    }

    func test_purge_dryRun_skips_terminator() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let terminator = SpyAppTerminator()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: terminator,
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertTrue(terminator.calls.isEmpty)
    }
```

And add the spies at the top of the file (after `SpyLaunchAgentClient`):

```swift
final class SpyAppTerminator: AppTerminator, @unchecked Sendable {
    struct Call: Equatable { let bundleID: String; let executableName: String? }
    var calls: [Call] = []
    func terminate(bundleID: String, executableName: String?) async -> Bool {
        calls.append(Call(bundleID: bundleID, executableName: executableName))
        return true
    }
}

final class SpyLoginItemsClient: LoginItemsClient, @unchecked Sendable {
    struct Call: Equatable { let appName: String?; let bundleID: String }
    var calls: [Call] = []
    func removeLoginItem(appName: String?, bundleID: String) {
        calls.append(Call(appName: appName, bundleID: bundleID))
    }
}

final class SpyLaunchServicesClient: LaunchServicesClient, @unchecked Sendable {
    var unregisterCalls: [URL] = []
    var rebuildCalls: Int = 0
    func unregister(app: URL) {
        unregisterCalls.append(app)
    }
    func rebuild() {
        rebuildCalls += 1
    }
}
```

- [ ] **Step 2: Run test to verify it fails to compile**

Run: `swift test --filter AppPurgerTests`
Expected: build failure — `AppPurger.init` does not yet accept `terminator`/`loginItems`/`launchServices`, and the spy protocols are not defined.

- [ ] **Step 3: Add stub protocols (will be properly implemented in tasks 6 + 7)**

In `Sources/AutoCleanMacCore/LoginItemsClient.swift` (create):

```swift
import Foundation

public protocol LoginItemsClient: Sendable {
    /// Best-effort: usuwa wpis o danej nazwie/bundle ID z Login Items.
    /// Brak gwarancji — wymaga uprawnień AppleScript do System Events.
    func removeLoginItem(appName: String?, bundleID: String)
}
```

In `Sources/AutoCleanMacCore/LaunchServicesClient.swift` (create):

```swift
import Foundation

public protocol LaunchServicesClient: Sendable {
    /// `lsregister -u <app>` — usuwa wpis bundla z bazy LaunchServices.
    /// Wywoływane PRZED skasowaniem `.app` z dysku.
    func unregister(app: URL)

    /// `lsregister -gc` + `-r -f -domain ...` — pełna przebudowa bazy.
    /// Drogie (~kilka sekund). Wywoływać RAZ po całym batchu uninstalla.
    func rebuild()
}
```

- [ ] **Step 4: Extend AppPurger to accept and call terminator**

Modify `Sources/AutoCleanMacCore/AppPurger.swift`. Replace the `init` and add stored properties + the call:

```swift
public final class AppPurger: Sendable {
    private let deleter: SafeDeleter
    private let prefsDaemon: PreferencesDaemonClient
    private let launchAgents: LaunchAgentClient
    private let terminator: AppTerminator
    private let loginItems: LoginItemsClient
    private let launchServices: LaunchServicesClient
    private let elevatedRemove: @Sendable (URL) async throws -> Void
    private let logger: Logger

    public init(
        deleter: SafeDeleter,
        prefsDaemon: PreferencesDaemonClient,
        launchAgents: LaunchAgentClient,
        terminator: AppTerminator,
        loginItems: LoginItemsClient,
        launchServices: LaunchServicesClient,
        elevatedRemove: @escaping @Sendable (URL) async throws -> Void,
        logger: Logger
    ) {
        self.deleter = deleter
        self.prefsDaemon = prefsDaemon
        self.launchAgents = launchAgents
        self.terminator = terminator
        self.loginItems = loginItems
        self.launchServices = launchServices
        self.elevatedRemove = elevatedRemove
        self.logger = logger
    }
```

And, **inside `purge`**, between the guard check (Task 3) and the `let appRoot = ...` line, add:

```swift
        // Best-effort process termination before deletion. macOS allows deleting a
        // running bundle, so we never abort on terminator failure.
        if deleter.mode != .dryRun {
            _ = await terminator.terminate(bundleID: bundleID, executableName: nil)
        }
```

- [ ] **Step 5: Update the three existing AppPurger tests to pass the new init args**

In `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`, every existing `AppPurger(...)` call needs the three new arguments. Replace each occurrence of:

```swift
let purger = AppPurger(
    deleter: SafeDeleter(mode: .dryRun, logger: logger),
    prefsDaemon: SpyPreferencesDaemon(),
    launchAgents: SpyLaunchAgentClient(),
    elevatedRemove: { ... },
    logger: logger
)
```

with:

```swift
let purger = AppPurger(
    deleter: SafeDeleter(mode: .dryRun, logger: logger),
    prefsDaemon: SpyPreferencesDaemon(),
    launchAgents: SpyLaunchAgentClient(),
    terminator: SpyAppTerminator(),
    loginItems: SpyLoginItemsClient(),
    launchServices: SpyLaunchServicesClient(),
    elevatedRemove: { ... },
    logger: logger
)
```

(Mode and other args unchanged.) Apply to all four existing test functions.

- [ ] **Step 6: Run tests**

Run: `swift test --filter AppPurgerTests`
Expected: all old + new tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoCleanMacCore/AppPurger.swift Sources/AutoCleanMacCore/LoginItemsClient.swift Sources/AutoCleanMacCore/LaunchServicesClient.swift Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "feat(AppPurger): inject AppTerminator and call it before deletion"
```

---

## Task 6: LoginItemsClient shell implementation + call site

**Files:**
- Modify: `Sources/AutoCleanMacCore/LoginItemsClient.swift`
- Modify: `Sources/AutoCleanMacCore/AppPurger.swift`
- Modify: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `AppPurgerTests`:

```swift
    func test_purge_invokes_loginItems_removal_in_live_mode() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let loginItems = SpyLoginItemsClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: loginItems,
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertEqual(loginItems.calls, [SpyLoginItemsClient.Call(appName: "Tiny", bundleID: "com.example.Tiny")])
    }

    func test_purge_dryRun_skips_loginItems() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let loginItems = SpyLoginItemsClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: loginItems,
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: nil,
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertTrue(loginItems.calls.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppPurgerTests/test_purge_invokes_loginItems_removal_in_live_mode`
Expected: FAIL — `loginItems.calls` is empty (purge never invokes it).

- [ ] **Step 3: Add the call in `AppPurger.purge`**

In `Sources/AutoCleanMacCore/AppPurger.swift`, immediately after the terminator call added in Task 5:

```swift
        if deleter.mode != .dryRun {
            loginItems.removeLoginItem(appName: displayName, bundleID: bundleID)
        }
```

- [ ] **Step 4: Add shell impl in LoginItemsClient.swift**

Replace `Sources/AutoCleanMacCore/LoginItemsClient.swift` with:

```swift
import Foundation

public protocol LoginItemsClient: Sendable {
    func removeLoginItem(appName: String?, bundleID: String)
}

public struct ShellLoginItemsClient: LoginItemsClient {
    public init() {}

    public func removeLoginItem(appName: String?, bundleID: String) {
        let cleanName = (appName ?? "").replacingOccurrences(of: ".app", with: "")
        guard !cleanName.isEmpty else { return }

        let escaped = cleanName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "System Events"
            try
                set itemCount to count of login items
                repeat with i from itemCount to 1 by -1
                    try
                        set itemName to name of login item i
                        if itemName is "\(escaped)" then
                            delete login item i
                        end if
                    end try
                end repeat
            end try
        end tell
        """

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null
        try? p.run()
        p.waitUntilExit()
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter AppPurgerTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/LoginItemsClient.swift Sources/AutoCleanMacCore/AppPurger.swift Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "feat(AppPurger): remove macOS Login Items entries via osascript"
```

---

## Task 7: LaunchServicesClient shell implementation + per-app unregister

**Files:**
- Modify: `Sources/AutoCleanMacCore/LaunchServicesClient.swift`
- Modify: `Sources/AutoCleanMacCore/AppPurger.swift`
- Modify: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`

`rebuild()` is **not** called from AppPurger — it's called once by AppDelegate after the batch. AppPurger only calls `unregister(app:)` per app.

- [ ] **Step 1: Write the failing test**

Append inside `AppPurgerTests`:

```swift
    func test_purge_unregisters_bundle_from_launchservices_in_live_mode() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let launchServices = SpyLaunchServicesClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: launchServices,
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertEqual(launchServices.unregisterCalls, [appURL])
        XCTAssertEqual(launchServices.rebuildCalls, 0, "AppPurger must not call rebuild — that is a batch-level concern")
    }

    func test_purge_dryRun_skips_launchservices_unregister() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let launchServices = SpyLaunchServicesClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: launchServices,
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: nil,
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertTrue(launchServices.unregisterCalls.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppPurgerTests/test_purge_unregisters_bundle_from_launchservices_in_live_mode`
Expected: FAIL — `unregisterCalls` is empty.

- [ ] **Step 3: Add unregister call in AppPurger.purge (BEFORE deletion)**

In `Sources/AutoCleanMacCore/AppPurger.swift`, between the loginItems call and `let appRoot = appURL.deletingLastPathComponent()`:

```swift
        if deleter.mode != .dryRun, appURL.pathExtension == "app" {
            launchServices.unregister(app: appURL)
        }
```

- [ ] **Step 4: Replace LaunchServicesClient.swift with full impl**

Replace `Sources/AutoCleanMacCore/LaunchServicesClient.swift`:

```swift
import Foundation

public protocol LaunchServicesClient: Sendable {
    func unregister(app: URL)
    func rebuild()
}

public struct ShellLaunchServicesClient: LaunchServicesClient {
    public init() {}

    private static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    public func unregister(app: URL) {
        run(args: ["-u", app.path], timeout: 5)
    }

    public func rebuild() {
        // GC first (cheap), then full rebuild. Both swallow failures — this is best-effort
        // cosmetic cleanup of Spotlight/Dock app metadata.
        run(args: ["-gc"], timeout: 10)
        let primary = run(args: ["-r", "-f", "-domain", "local", "-domain", "user", "-domain", "system"], timeout: 15)
        if !primary {
            // Lighter fallback: drop system domain (requires sudo on some setups).
            _ = run(args: ["-r", "-f", "-domain", "local", "-domain", "user"], timeout: 10)
        }
    }

    @discardableResult
    private func run(args: [String], timeout: TimeInterval) -> Bool {
        let exec = URL(fileURLWithPath: Self.lsregisterPath)
        guard FileManager.default.isExecutableFile(atPath: exec.path) else { return false }

        let p = Process()
        p.executableURL = exec
        p.arguments = args
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null

        do {
            try p.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline {
                p.terminate()
                return false
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return p.terminationStatus == 0
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter AppPurgerTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/LaunchServicesClient.swift Sources/AutoCleanMacCore/AppPurger.swift Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "feat(AppPurger): unregister bundle from LaunchServices before deletion"
```

---

## Task 8: Call ordering integration test

**Files:**
- Modify: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`

Confirms the four pre-deletion steps fire in the correct order: terminate → loginItems → launchServices.unregister → deleter.delete. We use a shared `OrderRecorder` to interleave events.

- [ ] **Step 1: Add the OrderRecorder + test**

Append to `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`:

```swift
    final class OrderRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        func record(_ event: String) {
            lock.lock(); defer { lock.unlock() }
            events.append(event)
        }
        func snapshot() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return events
        }
    }

    func test_purge_runs_pre_deletion_steps_in_correct_order() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let recorder = OrderRecorder()

        final class RecordingTerminator: AppTerminator, @unchecked Sendable {
            let r: OrderRecorder
            init(_ r: OrderRecorder) { self.r = r }
            func terminate(bundleID: String, executableName: String?) async -> Bool {
                r.record("terminate"); return true
            }
        }
        final class RecordingLoginItems: LoginItemsClient, @unchecked Sendable {
            let r: OrderRecorder
            init(_ r: OrderRecorder) { self.r = r }
            func removeLoginItem(appName: String?, bundleID: String) {
                r.record("loginItems")
            }
        }
        final class RecordingLaunchServices: LaunchServicesClient, @unchecked Sendable {
            let r: OrderRecorder
            init(_ r: OrderRecorder) { self.r = r }
            func unregister(app: URL) { r.record("unregister") }
            func rebuild() { r.record("rebuild") }
        }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: RecordingTerminator(recorder),
            loginItems: RecordingLoginItems(recorder),
            launchServices: RecordingLaunchServices(recorder),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        // We do not assert on what comes after `unregister` — the deleter itself is
        // not on the recorder. The key invariant is the prefix.
        let events = recorder.snapshot()
        XCTAssertEqual(Array(events.prefix(3)), ["terminate", "loginItems", "unregister"])
        XCTAssertFalse(events.contains("rebuild"), "rebuild() is a batch concern, not per-app")
    }
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter AppPurgerTests/test_purge_runs_pre_deletion_steps_in_correct_order`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "test(AppPurger): assert pre-deletion step ordering"
```

---

## Task 9: Wire shell clients in AppDelegate and call rebuild() once after batch

**Files:**
- Modify: `Sources/AutoCleanMac/AppDelegate.swift` (around lines 514-560)

- [ ] **Step 1: Replace the `AppPurger` construction inside the `onUninstall:` closure**

In `Sources/AutoCleanMac/AppDelegate.swift`, locate the `onUninstall: { [weak self] apps, mode in` closure (currently starts ~line 514). Replace the body so that:

1. The shell clients are constructed **once** outside the per-app loop.
2. `AppPurger` is constructed **once** with all four new dependencies.
3. After the per-app loop ends, `launchServices.rebuild()` is called exactly once (only in live/trash mode, never in dryRun).

```swift
            onUninstall: { [weak self] apps, mode in
                guard let self else {
                    return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: [])
                }
                let launchServices = ShellLaunchServicesClient()
                let purger = AppPurger(
                    deleter: SafeDeleter(mode: mode, logger: self.logger),
                    prefsDaemon: ShellPreferencesDaemonClient(),
                    launchAgents: ShellLaunchAgentClient(),
                    terminator: ShellAppTerminator(),
                    loginItems: ShellLoginItemsClient(),
                    launchServices: launchServices,
                    elevatedRemove: { url in
                        try await MainActor.run {
                            if mode == .trash {
                                do {
                                    try ElevatedUninstall.trashViaFinder(url)
                                    if !FileManager.default.fileExists(atPath: url.path) { return }
                                } catch ElevatedUninstallError.userCancelled {
                                    throw ElevatedUninstallError.userCancelled
                                } catch {
                                    // fallback to admin rm
                                }
                            }
                            try ElevatedUninstall.removeWithAdmin(url)
                        }
                    },
                    logger: self.logger
                )

                var freed: Int64 = 0
                var succeeded = 0
                var failures: [UninstallFailure] = []
                for app in apps {
                    let outcome = await purger.purge(
                        bundleID: app.bundleIdentifier,
                        displayName: app.name,
                        appURL: app.url,
                        homeDirectory: home,
                        includeSystemPaths: app.url.path.hasPrefix("/Applications/")
                    )
                    if outcome.appRemoved {
                        freed += outcome.bytesFreed
                        succeeded += 1
                    }
                    for f in outcome.failures {
                        failures.append(UninstallFailure(appName: app.name, reason: f.reason))
                    }
                }

                if mode != .dryRun, succeeded > 0 {
                    // Fire-and-forget: LaunchServices rebuild can take ~5–15s. The UI
                    // already shows the uninstall summary; we don't want to block on it.
                    Task.detached(priority: .utility) {
                        launchServices.rebuild()
                    }
                }

                return UninstallOutcome(freedBytes: freed, succeeded: succeeded, failures: failures)
            },
```

- [ ] **Step 2: Build the app target**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Run full test suite**

Run: `swift test`
Expected: all tests PASS (the ~99 existing + ~9 new).

- [ ] **Step 4: Smoke test in a real run (manual)**

Build the menu bar app: `swift build -c release`
Launch it, open the Uninstaller tab, pick a single safe disposable test app (e.g. install `Hello.app` from a free dev sample), set mode to Trash, and uninstall.

Verify:
- Process (if running) gets quit.
- Login Items in System Settings no longer contain the app (if it had registered itself).
- Spotlight no longer returns the bundle as an "Applications" hit within ~30s after the rebuild fires.
- AppPurger refuses if you somehow construct a list containing `com.apple.finder` (sanity check the guard).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMac/AppDelegate.swift
git commit -m "feat(AppDelegate): wire shell clients into AppPurger and rebuild LaunchServices after batch"
```

---

## Self-Review Checklist (already applied)

**Spec coverage:** AppProtectionGuard (Task 1-3), force_kill (Task 4-5), Login Items (Task 6), LaunchServices unregister+rebuild (Task 7,9). All four user-requested features covered.

**Placeholder scan:** No TBD/TODO/"add appropriate error handling"/"similar to Task N" in plan body.

**Type consistency:**
- `AppProtectionGuard.isProtected(bundleID:)` — used identically in Tasks 1, 2, 3.
- `AppTerminator.terminate(bundleID:executableName:) async -> Bool` — used identically in Tasks 4, 5, 8.
- `LoginItemsClient.removeLoginItem(appName:bundleID:)` — used identically in Tasks 5, 6, 8.
- `LaunchServicesClient.unregister(app:)` / `.rebuild()` — used identically in Tasks 5, 7, 8, 9.
- `AppPurger.init` signature in Task 5 matches all subsequent test/wire-up references.

**Trade-offs intentionally accepted:**
- Shell impls (`ShellAppTerminator`, `ShellLoginItemsClient`, `ShellLaunchServicesClient`) are not unit-tested live — they touch global system state. Coverage comes from spy-based integration tests and one manual smoke step.
- `AppProtectionGuard.systemCriticalPatterns` is a curated subset of mole's list (~50 entries vs mole's ~150). Extending it later is purely additive.
- `LaunchServicesClient.rebuild()` is fire-and-forget after the batch so the UI does not stall for up to 15s.

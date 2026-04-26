# Thorough App Uninstall + Orphan Preferences Scanner

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) Wzbogacić deinstalację o pełne usuwanie preferencji aplikacji (ByHost, group containers, cookies, LaunchAgents, system-side `/Library/...`, plus `defaults delete` i `launchctl unload`); (2) dodać skaner "osieroconych" preferencji — plików w `~/Library`/`Library` należących do aplikacji, których już nie ma w `/Applications` ani `~/Applications` — z UI do przeglądu i czyszczenia.

**Architecture:** Wyciągnąć pure-funkcyjne reguły generowania ścieżek z `AppScanner` do nowego `LeftoverPathProvider`. Stworzyć `AppPurger` w Core orkiestrujący usuwanie (pliki + cfprefsd + launchctl), z wstrzykiwanymi protokołami `PreferencesDaemonClient` i `LaunchAgentClient` aby był testowalny. Reużyć `LeftoverPathProvider` w nowym `OrphanScanner`, który dla każdego zainstalowanego bundle ID pyta `InstalledAppRegistry`. Wszystko Core → testy XCTest. UI: jedna nowa zakładka `OrphanCleanerTab` w `SettingsView`.

**Tech Stack:** Swift 5.9+, XCTest, Foundation `Process`, `NSAppleScript` (już zaintegrowane przez `ElevatedUninstall`), SwiftUI/AppKit (UI), istniejący `SafeDeleter` do faktycznego usuwania.

---

## File Structure

**Tworzymy:**
- `Sources/AutoCleanMacCore/LeftoverPathProvider.swift` — pure: `(bundleID, displayName?, homeDir) -> LeftoverPaths` (user + system).
- `Sources/AutoCleanMacCore/PreferencesDaemonClient.swift` — protokół + `ShellPreferencesDaemonClient` (uruchamia `defaults delete`).
- `Sources/AutoCleanMacCore/LaunchAgentClient.swift` — protokół + `ShellLaunchAgentClient` (uruchamia `launchctl unload`).
- `Sources/AutoCleanMacCore/AppPurger.swift` — orkiestrator deinstalacji jednej aplikacji; używa `SafeDeleter`, `PreferencesDaemonClient`, `LaunchAgentClient`, plus injected `elevatedRemove: (URL) async throws -> Void`.
- `Sources/AutoCleanMacCore/InstalledAppRegistry.swift` — `installedBundleIDs(homeDirectory:) -> Set<String>` (skanuje `/Applications`, `~/Applications`, `/System/Applications`).
- `Sources/AutoCleanMacCore/OrphanScanner.swift` — `scan(homeDirectory:, installed: Set<String>) -> [OrphanGroup]`.
- `Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift` — UI zakładki.
- `Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift`
- `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`
- `Tests/AutoCleanMacCoreTests/InstalledAppRegistryTests.swift`
- `Tests/AutoCleanMacCoreTests/OrphanScannerTests.swift`

**Modyfikujemy:**
- `Sources/AutoCleanMacCore/AppScanner.swift` — usuwamy inline `generateLeftoverPaths`, używamy `LeftoverPathProvider`.
- `Sources/AutoCleanMac/AppDelegate.swift` — `onUninstall` deleguje całość do `AppPurger`; dodaje obsługę `OrphanCleanerTab` callbacks.
- `Sources/AutoCleanMac/SettingsView.swift` — dodajemy `case orphans` w `SettingsSection`, callback do skanowania/usuwania w `SettingsModel`.

---

## Phase 1 — LeftoverPathProvider

### Task 1.1: Stwórz strukturę `LeftoverPaths` i pierwszy test

**Files:**
- Test: `Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift`

- [ ] **Step 1: Napisz failing test dla podstawowych ścieżek user-side**

```swift
import XCTest
@testable import AutoCleanMacCore

final class LeftoverPathProviderTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let bundleID = "com.example.MyApp"

    func test_userPaths_includes_classic_locations() {
        let paths = LeftoverPathProvider.userPaths(
            bundleID: bundleID,
            displayName: nil,
            homeDirectory: home
        )
        let asStrings = paths.map(\.path)
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Preferences/com.example.MyApp.plist"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Application Support/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Caches/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Containers/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Saved Application State/com.example.MyApp.savedState"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/HTTPStorages/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Logs/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/WebKit/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Cookies/com.example.MyApp.binarycookies"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Application Scripts/com.example.MyApp"))
    }
}
```

- [ ] **Step 2: Uruchom test — oczekiwany FAIL (brak typu)**

Run: `swift test --filter LeftoverPathProviderTests/test_userPaths_includes_classic_locations`
Expected: FAIL z "cannot find 'LeftoverPathProvider' in scope".

- [ ] **Step 3: Zaimplementuj `LeftoverPathProvider.userPaths`**

Plik: `Sources/AutoCleanMacCore/LeftoverPathProvider.swift`

```swift
import Foundation

public enum LeftoverPathProvider {
    /// Ścieżki w obrębie `~/Library` powiązane z bundle ID i opcjonalną nazwą wyświetlaną aplikacji.
    /// Zwraca wszystkie kandydatury, niezależnie od istnienia na dysku — istnienie sprawdza wywołujący.
    public static func userPaths(
        bundleID: String,
        displayName: String?,
        homeDirectory: URL
    ) -> [URL] {
        let lib = homeDirectory.appendingPathComponent("Library")
        var paths: [URL] = [
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Application Support/\(bundleID)"),
            lib.appendingPathComponent("Caches/\(bundleID)"),
            lib.appendingPathComponent("Containers/\(bundleID)"),
            lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
            lib.appendingPathComponent("Logs/\(bundleID)"),
            lib.appendingPathComponent("WebKit/\(bundleID)"),
            lib.appendingPathComponent("Cookies/\(bundleID).binarycookies"),
            lib.appendingPathComponent("Application Scripts/\(bundleID)"),
        ]
        if let name = displayName, !name.isEmpty, name != bundleID {
            paths.append(lib.appendingPathComponent("Application Support/\(name)"))
            paths.append(lib.appendingPathComponent("Caches/\(name)"))
        }
        return paths
    }
}
```

- [ ] **Step 4: Uruchom test — oczekiwany PASS**

Run: `swift test --filter LeftoverPathProviderTests/test_userPaths_includes_classic_locations`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/LeftoverPathProvider.swift Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift
git commit -m "feat(core): add LeftoverPathProvider with classic user-side paths"
```

### Task 1.2: Display-name warianty (`Application Support/<DisplayName>`)

**Files:**
- Test: `Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift`

- [ ] **Step 1: Dopisz test dla display-name**

```swift
func test_userPaths_includes_display_name_variants_when_provided() {
    let paths = LeftoverPathProvider.userPaths(
        bundleID: "com.example.MyApp",
        displayName: "MyApp",
        homeDirectory: home
    )
    let asStrings = paths.map(\.path)
    XCTAssertTrue(asStrings.contains("/Users/test/Library/Application Support/MyApp"))
    XCTAssertTrue(asStrings.contains("/Users/test/Library/Caches/MyApp"))
}

func test_userPaths_skips_display_name_when_equal_to_bundle_id() {
    let paths = LeftoverPathProvider.userPaths(
        bundleID: "com.example.MyApp",
        displayName: "com.example.MyApp",
        homeDirectory: home
    )
    let appSupport = paths.filter { $0.path.hasSuffix("/Application Support/com.example.MyApp") }
    XCTAssertEqual(appSupport.count, 1, "Nie duplikuj display-name jeśli to ten sam string co bundle ID")
}
```

- [ ] **Step 2: Uruchom — pierwszy PASS (już zaimplementowane), drugi może FAIL przy duplikatach**

Run: `swift test --filter LeftoverPathProviderTests`
Expected: oba PASS (logika już dba o `name != bundleID`).

- [ ] **Step 3: Commit**

```bash
git add Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift
git commit -m "test(core): cover display-name handling in LeftoverPathProvider"
```

### Task 1.3: ByHost glob i Group Containers (zwracane jako wzorce)

**Files:**
- Modify: `Sources/AutoCleanMacCore/LeftoverPathProvider.swift`
- Test: `Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift`

- [ ] **Step 1: Test dla rzeczywistych dopasowań ByHost / Group Containers**

```swift
func test_resolveByHostAndGroupContainers_finds_matching_files() throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("LeftoverPathProvider-\(UUID().uuidString)")
    let lib = temp.appendingPathComponent("Library")
    let byHostDir = lib.appendingPathComponent("Preferences/ByHost")
    let groupDir = lib.appendingPathComponent("Group Containers")
    try FileManager.default.createDirectory(at: byHostDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: groupDir, withIntermediateDirectories: true)
    try Data().write(to: byHostDir.appendingPathComponent("com.example.MyApp.ABCDEF.plist"))
    try Data().write(to: byHostDir.appendingPathComponent("com.other.thing.XYZ.plist"))
    try FileManager.default.createDirectory(at: groupDir.appendingPathComponent("group.com.example.MyApp"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: groupDir.appendingPathComponent("ABCD1234.com.example.MyApp"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: groupDir.appendingPathComponent("group.com.unrelated"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let resolved = LeftoverPathProvider.resolveDynamic(
        bundleID: "com.example.MyApp",
        homeDirectory: temp
    )
    let paths = resolved.map(\.path)
    XCTAssertTrue(paths.contains(byHostDir.appendingPathComponent("com.example.MyApp.ABCDEF.plist").path))
    XCTAssertFalse(paths.contains(byHostDir.appendingPathComponent("com.other.thing.XYZ.plist").path))
    XCTAssertTrue(paths.contains(groupDir.appendingPathComponent("group.com.example.MyApp").path))
    XCTAssertTrue(paths.contains(groupDir.appendingPathComponent("ABCD1234.com.example.MyApp").path))
    XCTAssertFalse(paths.contains(groupDir.appendingPathComponent("group.com.unrelated").path))
}
```

- [ ] **Step 2: Uruchom — FAIL (brak `resolveDynamic`)**

Run: `swift test --filter LeftoverPathProviderTests/test_resolveByHostAndGroupContainers_finds_matching_files`
Expected: FAIL.

- [ ] **Step 3: Zaimplementuj `resolveDynamic` w `LeftoverPathProvider`**

Append do `Sources/AutoCleanMacCore/LeftoverPathProvider.swift`:

```swift
extension LeftoverPathProvider {
    /// Ścieżki, których nie da się statycznie wyliczyć — wymagają enumeracji katalogów
    /// (np. ByHost preferences z UUID-em hosta, Group Containers z prefiksem teamID).
    public static func resolveDynamic(
        bundleID: String,
        homeDirectory: URL
    ) -> [URL] {
        let fm = FileManager.default
        let lib = homeDirectory.appendingPathComponent("Library")
        var results: [URL] = []

        let byHost = lib.appendingPathComponent("Preferences/ByHost")
        if let entries = try? fm.contentsOfDirectory(atPath: byHost.path) {
            for name in entries where name.hasPrefix("\(bundleID).") && name.hasSuffix(".plist") {
                results.append(byHost.appendingPathComponent(name))
            }
        }

        let groupContainers = lib.appendingPathComponent("Group Containers")
        if let entries = try? fm.contentsOfDirectory(atPath: groupContainers.path) {
            for name in entries {
                let isGroupPrefixed = name == "group.\(bundleID)" || name.hasPrefix("group.\(bundleID).")
                let isTeamPrefixed = name.hasSuffix(".\(bundleID)") && name.split(separator: ".").count >= 2 && !name.hasPrefix("group.")
                if isGroupPrefixed || isTeamPrefixed {
                    results.append(groupContainers.appendingPathComponent(name))
                }
            }
        }

        return results
    }
}
```

- [ ] **Step 4: Uruchom — PASS**

Run: `swift test --filter LeftoverPathProviderTests/test_resolveByHostAndGroupContainers_finds_matching_files`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/LeftoverPathProvider.swift Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift
git commit -m "feat(core): resolve ByHost prefs and Group Containers by enumeration"
```

### Task 1.4: LaunchAgents user-side (`~/Library/LaunchAgents/<id>*.plist`)

**Files:**
- Modify: `Sources/AutoCleanMacCore/LeftoverPathProvider.swift`
- Test: `Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift`

- [ ] **Step 1: Test**

```swift
func test_resolveDynamic_finds_user_launchagents() throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("LeftoverPathProvider-\(UUID().uuidString)")
    let agents = temp.appendingPathComponent("Library/LaunchAgents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    try Data().write(to: agents.appendingPathComponent("com.example.MyApp.plist"))
    try Data().write(to: agents.appendingPathComponent("com.example.MyApp.helper.plist"))
    try Data().write(to: agents.appendingPathComponent("com.unrelated.helper.plist"))
    defer { try? FileManager.default.removeItem(at: temp) }

    let resolved = LeftoverPathProvider.resolveDynamic(bundleID: "com.example.MyApp", homeDirectory: temp)
    let paths = resolved.map(\.path)
    XCTAssertTrue(paths.contains(agents.appendingPathComponent("com.example.MyApp.plist").path))
    XCTAssertTrue(paths.contains(agents.appendingPathComponent("com.example.MyApp.helper.plist").path))
    XCTAssertFalse(paths.contains(agents.appendingPathComponent("com.unrelated.helper.plist").path))
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `swift test --filter LeftoverPathProviderTests/test_resolveDynamic_finds_user_launchagents`
Expected: FAIL.

- [ ] **Step 3: Rozszerz `resolveDynamic` o LaunchAgents**

Dopisz w bloku `extension LeftoverPathProvider` przed `return results`:

```swift
let userAgents = lib.appendingPathComponent("LaunchAgents")
if let entries = try? fm.contentsOfDirectory(atPath: userAgents.path) {
    for name in entries where name.hasSuffix(".plist") {
        let stem = String(name.dropLast(".plist".count))
        if stem == bundleID || stem.hasPrefix("\(bundleID).") {
            results.append(userAgents.appendingPathComponent(name))
        }
    }
}
```

- [ ] **Step 4: Uruchom — PASS**

Run: `swift test --filter LeftoverPathProviderTests`
Expected: wszystkie PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/LeftoverPathProvider.swift Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift
git commit -m "feat(core): resolve user LaunchAgents matching bundle ID"
```

### Task 1.5: System-side ścieżki (`/Library/...`) — wymagają admin

**Files:**
- Modify: `Sources/AutoCleanMacCore/LeftoverPathProvider.swift`
- Test: `Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift`

- [ ] **Step 1: Test (na fake root)**

```swift
func test_systemPaths_returns_static_candidates() {
    let root = URL(fileURLWithPath: "/")
    let paths = LeftoverPathProvider.systemPaths(
        bundleID: "com.example.MyApp",
        displayName: "MyApp",
        systemRoot: root
    ).map(\.path)
    XCTAssertTrue(paths.contains("/Library/Preferences/com.example.MyApp.plist"))
    XCTAssertTrue(paths.contains("/Library/Application Support/com.example.MyApp"))
    XCTAssertTrue(paths.contains("/Library/Application Support/MyApp"))
    XCTAssertTrue(paths.contains("/Library/LaunchDaemons/com.example.MyApp.plist"))
    XCTAssertTrue(paths.contains("/Library/LaunchAgents/com.example.MyApp.plist"))
    XCTAssertTrue(paths.contains("/Library/PrivilegedHelperTools/com.example.MyApp"))
}

func test_resolveDynamicSystem_finds_helper_variants() throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("SystemFake-\(UUID().uuidString)")
    let daemons = temp.appendingPathComponent("Library/LaunchDaemons")
    try FileManager.default.createDirectory(at: daemons, withIntermediateDirectories: true)
    try Data().write(to: daemons.appendingPathComponent("com.example.MyApp.plist"))
    try Data().write(to: daemons.appendingPathComponent("com.example.MyApp.privilegedhelper.plist"))
    try Data().write(to: daemons.appendingPathComponent("com.unrelated.plist"))
    defer { try? FileManager.default.removeItem(at: temp) }

    let resolved = LeftoverPathProvider.resolveDynamicSystem(
        bundleID: "com.example.MyApp",
        systemRoot: temp
    ).map(\.path)
    XCTAssertTrue(resolved.contains(daemons.appendingPathComponent("com.example.MyApp.plist").path))
    XCTAssertTrue(resolved.contains(daemons.appendingPathComponent("com.example.MyApp.privilegedhelper.plist").path))
    XCTAssertFalse(resolved.contains(daemons.appendingPathComponent("com.unrelated.plist").path))
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `swift test --filter LeftoverPathProviderTests/test_systemPaths_returns_static_candidates`
Expected: FAIL.

- [ ] **Step 3: Zaimplementuj `systemPaths` i `resolveDynamicSystem`**

Append:

```swift
extension LeftoverPathProvider {
    public static func systemPaths(
        bundleID: String,
        displayName: String?,
        systemRoot: URL = URL(fileURLWithPath: "/")
    ) -> [URL] {
        let lib = systemRoot.appendingPathComponent("Library")
        var paths: [URL] = [
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Application Support/\(bundleID)"),
            lib.appendingPathComponent("LaunchDaemons/\(bundleID).plist"),
            lib.appendingPathComponent("LaunchAgents/\(bundleID).plist"),
            lib.appendingPathComponent("PrivilegedHelperTools/\(bundleID)"),
        ]
        if let name = displayName, !name.isEmpty, name != bundleID {
            paths.append(lib.appendingPathComponent("Application Support/\(name)"))
        }
        return paths
    }

    public static func resolveDynamicSystem(
        bundleID: String,
        systemRoot: URL = URL(fileURLWithPath: "/")
    ) -> [URL] {
        let fm = FileManager.default
        let lib = systemRoot.appendingPathComponent("Library")
        var results: [URL] = []

        for sub in ["LaunchDaemons", "LaunchAgents"] {
            let dir = lib.appendingPathComponent(sub)
            if let entries = try? fm.contentsOfDirectory(atPath: dir.path) {
                for name in entries where name.hasSuffix(".plist") {
                    let stem = String(name.dropLast(".plist".count))
                    if stem == bundleID || stem.hasPrefix("\(bundleID).") {
                        results.append(dir.appendingPathComponent(name))
                    }
                }
            }
        }

        let helpers = lib.appendingPathComponent("PrivilegedHelperTools")
        if let entries = try? fm.contentsOfDirectory(atPath: helpers.path) {
            for name in entries where name == bundleID || name.hasPrefix("\(bundleID).") {
                results.append(helpers.appendingPathComponent(name))
            }
        }
        return results
    }
}
```

- [ ] **Step 4: Uruchom — PASS**

Run: `swift test --filter LeftoverPathProviderTests`
Expected: wszystkie PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/LeftoverPathProvider.swift Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift
git commit -m "feat(core): add system-side leftover paths (/Library + helpers)"
```

### Task 1.6: Podmień `AppScanner.generateLeftoverPaths` na `LeftoverPathProvider`

**Files:**
- Modify: `Sources/AutoCleanMacCore/AppScanner.swift:108-120`

- [ ] **Step 1: Sprawdź istniejące testy AppScanner (jeśli są) i uruchom je**

Run: `swift test --filter AutoCleanMacCoreTests`
Expected: 84/84 PASS (baseline).

- [ ] **Step 2: Zastąp `generateLeftoverPaths` wywołaniem providera**

W `AppScanner.swift` usuń funkcję `generateLeftoverPaths(for:homeDirectory:)`. W `processApp(...)` zamień:

```swift
let leftovers = generateLeftoverPaths(for: bundleID, homeDirectory: homeDirectory)
```

na:

```swift
let leftovers = LeftoverPathProvider.userPaths(
    bundleID: bundleID,
    displayName: name,
    homeDirectory: homeDirectory
) + LeftoverPathProvider.resolveDynamic(
    bundleID: bundleID,
    homeDirectory: homeDirectory
)
```

- [ ] **Step 3: Build + test**

Run: `swift build && swift test`
Expected: build clean, wszystkie testy PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoCleanMacCore/AppScanner.swift
git commit -m "refactor(core): AppScanner uses LeftoverPathProvider for leftovers"
```

---

## Phase 2 — Daemon clients (cfprefsd + launchctl)

### Task 2.1: Protokoły + stub dla testów

**Files:**
- Create: `Sources/AutoCleanMacCore/PreferencesDaemonClient.swift`
- Create: `Sources/AutoCleanMacCore/LaunchAgentClient.swift`

- [ ] **Step 1: Zdefiniuj protokoły (kod bez testów — czysta deklaracja)**

`Sources/AutoCleanMacCore/PreferencesDaemonClient.swift`:

```swift
import Foundation

public protocol PreferencesDaemonClient: Sendable {
    /// Wymusza zrzut cache cfprefsd dla danego bundle ID poprzez `defaults delete`.
    /// Zwraca `true` jeśli komenda wykonała się bez błędu (nawet gdy klucz nie istniał).
    func deleteAll(bundleID: String) -> Bool
}
```

`Sources/AutoCleanMacCore/LaunchAgentClient.swift`:

```swift
import Foundation

public protocol LaunchAgentClient: Sendable {
    /// Próbuje wyładować plist agenta. `domain` to `gui/<uid>` dla user-side, `system` dla `/Library/LaunchDaemons`.
    func unload(plist: URL, domain: LaunchAgentDomain) -> Bool
}

public enum LaunchAgentDomain: Sendable {
    case userGUI(uid: uid_t)
    case system
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCleanMacCore/PreferencesDaemonClient.swift Sources/AutoCleanMacCore/LaunchAgentClient.swift
git commit -m "feat(core): add PreferencesDaemonClient and LaunchAgentClient protocols"
```

### Task 2.2: Production implementation (Process-based)

**Files:**
- Modify: `Sources/AutoCleanMacCore/PreferencesDaemonClient.swift`
- Modify: `Sources/AutoCleanMacCore/LaunchAgentClient.swift`
- Test: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift` (zaczynamy plik dla użycia stubów dalej)

- [ ] **Step 1: Stub spy do testów (w pliku testów Phase 3, ale przygotujemy go teraz)**

`Tests/AutoCleanMacCoreTests/AppPurgerTests.swift` (wstępnie tylko spy + pusty test stub):

```swift
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
```

- [ ] **Step 2: Production implementation `ShellPreferencesDaemonClient`**

W `PreferencesDaemonClient.swift` dopisz:

```swift
public struct ShellPreferencesDaemonClient: PreferencesDaemonClient {
    public init() {}
    public func deleteAll(bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", bundleID]
        let nullHandle = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullHandle
        process.standardError = nullHandle
        do {
            try process.run()
            process.waitUntilExit()
            // Status 1 oznacza "domain not found" — to nie jest błąd dla naszego use-case.
            return true
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 3: Production implementation `ShellLaunchAgentClient`**

W `LaunchAgentClient.swift` dopisz:

```swift
public struct ShellLaunchAgentClient: LaunchAgentClient {
    public init() {}
    public func unload(plist: URL, domain: LaunchAgentDomain) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        switch domain {
        case .userGUI(let uid):
            process.arguments = ["bootout", "gui/\(uid)", plist.path]
        case .system:
            process.arguments = ["bootout", "system", plist.path]
        }
        let nullHandle = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullHandle
        process.standardError = nullHandle
        do {
            try process.run()
            process.waitUntilExit()
            return true
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 4: Build + test (powinno przechodzić — tylko nowy stub bez asercji)**

Run: `swift build && swift test`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/PreferencesDaemonClient.swift Sources/AutoCleanMacCore/LaunchAgentClient.swift Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "feat(core): production shell-based PreferencesDaemon and LaunchAgent clients"
```

---

## Phase 3 — AppPurger orkiestrator

### Task 3.1: Definicja `PurgeOutcome` i `AppPurger` z metodą `purge`

**Files:**
- Create: `Sources/AutoCleanMacCore/AppPurger.swift`
- Modify: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`

- [ ] **Step 1: Test podstawowy — usuwa appkę i preferencje user-side bez systemowych**

```swift
func test_purge_removes_app_and_userside_leftovers_in_dryRun() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
    let appsDir = temp.appendingPathComponent("Applications")
    let appURL = appsDir.appendingPathComponent("MyApp.app")
    let lib = temp.appendingPathComponent("Library")
    let prefsURL = lib.appendingPathComponent("Preferences/com.example.MyApp.plist")
    let supportURL = lib.appendingPathComponent("Application Support/com.example.MyApp")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: lib.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 100).write(to: prefsURL)
    defer { try? FileManager.default.removeItem(at: temp) }

    let logger = Logger(directoryURL: temp.appendingPathComponent("logs"))
    let purger = AppPurger(
        deleter: SafeDeleter(mode: .dryRun, logger: logger),
        prefsDaemon: SpyPreferencesDaemon(),
        launchAgents: SpyLaunchAgentClient(),
        elevatedRemove: { _ in XCTFail("Nie powinno być elewacji w dryRun") },
        logger: logger
    )

    let outcome = await purger.purge(
        bundleID: "com.example.MyApp",
        displayName: "MyApp",
        appURL: appURL,
        homeDirectory: temp,
        systemRoot: temp,
        includeSystemPaths: false
    )

    XCTAssertTrue(outcome.appRemoved)
    XCTAssertGreaterThan(outcome.bytesFreed, 0)
    XCTAssertTrue(outcome.failures.isEmpty)
    // dryRun nie usuwa fizycznie:
    XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: prefsURL.path))
}
```

- [ ] **Step 2: Uruchom — FAIL (brak `AppPurger`)**

Run: `swift test --filter AppPurgerTests/test_purge_removes_app_and_userside_leftovers_in_dryRun`
Expected: FAIL.

- [ ] **Step 3: Zaimplementuj `AppPurger`**

`Sources/AutoCleanMacCore/AppPurger.swift`:

```swift
import Foundation

public struct PurgeFailure: Sendable {
    public let path: String
    public let reason: String
    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct PurgeOutcome: Sendable {
    public var appRemoved: Bool
    public var bytesFreed: Int64
    public var itemsDeleted: Int
    public var elevatedFallbackUsed: Bool
    public var failures: [PurgeFailure]
}

public final class AppPurger: Sendable {
    private let deleter: SafeDeleter
    private let prefsDaemon: PreferencesDaemonClient
    private let launchAgents: LaunchAgentClient
    private let elevatedRemove: @Sendable (URL) async throws -> Void
    private let logger: Logger

    public init(
        deleter: SafeDeleter,
        prefsDaemon: PreferencesDaemonClient,
        launchAgents: LaunchAgentClient,
        elevatedRemove: @escaping @Sendable (URL) async throws -> Void,
        logger: Logger
    ) {
        self.deleter = deleter
        self.prefsDaemon = prefsDaemon
        self.launchAgents = launchAgents
        self.elevatedRemove = elevatedRemove
        self.logger = logger
    }

    public func purge(
        bundleID: String,
        displayName: String?,
        appURL: URL,
        homeDirectory: URL,
        systemRoot: URL = URL(fileURLWithPath: "/"),
        includeSystemPaths: Bool
    ) async -> PurgeOutcome {
        let fm = FileManager.default
        var bytes: Int64 = 0
        var items = 0
        var failures: [PurgeFailure] = []
        var elevatedUsed = false

        let appRoot = appURL.deletingLastPathComponent()
        var appRemoved = false
        do {
            let metrics = try deleter.deleteMeasured(appURL, withinRoot: appRoot)
            bytes += metrics.bytesFreed
            items += metrics.itemsDeleted
            appRemoved = true
        } catch {
            if fm.fileExists(atPath: appURL.path), deleter.mode != .dryRun {
                let measured = (try? SafeDeleter.recursiveMetrics(at: appURL).bytesFreed) ?? 0
                do {
                    try await elevatedRemove(appURL)
                    if !fm.fileExists(atPath: appURL.path) {
                        bytes += measured
                        appRemoved = true
                        elevatedUsed = true
                    } else {
                        failures.append(PurgeFailure(path: appURL.path, reason: "Plik nadal istnieje po elewacji."))
                    }
                } catch {
                    failures.append(PurgeFailure(path: appURL.path, reason: "\(error)"))
                }
            } else {
                failures.append(PurgeFailure(path: appURL.path, reason: (error as NSError).localizedDescription))
            }
        }

        // Leftovers user-side — usuwane nawet jeśli .app już nie istniała (czyścimy resztki).
        let userLib = homeDirectory.appendingPathComponent("Library")
        let userLeftovers = LeftoverPathProvider.userPaths(bundleID: bundleID, displayName: displayName, homeDirectory: homeDirectory)
            + LeftoverPathProvider.resolveDynamic(bundleID: bundleID, homeDirectory: homeDirectory)
        for url in userLeftovers where fm.fileExists(atPath: url.path) {
            // Unload LaunchAgents zanim usuniemy plist.
            if url.path.hasPrefix(userLib.appendingPathComponent("LaunchAgents").path) {
                _ = launchAgents.unload(plist: url, domain: .userGUI(uid: getuid()))
            }
            do {
                let metrics = try deleter.deleteMeasured(url, withinRoot: userLib)
                bytes += metrics.bytesFreed
                items += metrics.itemsDeleted
            } catch {
                failures.append(PurgeFailure(path: url.path, reason: (error as NSError).localizedDescription))
            }
        }

        if includeSystemPaths {
            let systemLib = systemRoot.appendingPathComponent("Library")
            let systemLeftovers = LeftoverPathProvider.systemPaths(bundleID: bundleID, displayName: displayName, systemRoot: systemRoot)
                + LeftoverPathProvider.resolveDynamicSystem(bundleID: bundleID, systemRoot: systemRoot)
            for url in systemLeftovers where fm.fileExists(atPath: url.path) {
                if url.path.hasPrefix(systemLib.appendingPathComponent("LaunchDaemons").path)
                    || url.path.hasPrefix(systemLib.appendingPathComponent("LaunchAgents").path) {
                    _ = launchAgents.unload(plist: url, domain: .system)
                }
                let measured = (try? SafeDeleter.recursiveMetrics(at: url).bytesFreed) ?? 0
                if deleter.mode == .dryRun {
                    logger.log(event: "purge_system_dryrun", fields: ["path": url.path, "size": "\(measured)"])
                    continue
                }
                do {
                    try await elevatedRemove(url)
                    if fm.fileExists(atPath: url.path) {
                        failures.append(PurgeFailure(path: url.path, reason: "System path nie usunięty po elewacji."))
                    } else {
                        bytes += measured
                        items += 1
                        elevatedUsed = true
                    }
                } catch {
                    failures.append(PurgeFailure(path: url.path, reason: "\(error)"))
                }
            }
        }

        // Wymuś flush cfprefsd na końcu (po usunięciu plików), niezależnie od trybu.
        if deleter.mode != .dryRun {
            _ = prefsDaemon.deleteAll(bundleID: bundleID)
        }

        logger.log(event: "purge_done", fields: [
            "bundle": bundleID,
            "removed": "\(appRemoved)",
            "bytes": "\(bytes)",
            "items": "\(items)",
            "failures": "\(failures.count)",
            "elevated": "\(elevatedUsed)",
        ])

        return PurgeOutcome(
            appRemoved: appRemoved,
            bytesFreed: bytes,
            itemsDeleted: items,
            elevatedFallbackUsed: elevatedUsed,
            failures: failures
        )
    }
}
```

UWAGA: powyższe wymaga publicznego dostępu do `SafeDeleter.mode`. Sprawdź — jeśli jest `private`, dodaj:

```swift
public extension SafeDeleter {
    var mode: Mode { _mode }
}
```

albo zmień existing `private let mode: Mode` na `public let mode: Mode` w `SafeDeleter.swift` (drugi jest prostszy — zrób to).

- [ ] **Step 4: Otwórz `SafeDeleter.swift` i zmień `private let mode: Mode` na `public let mode: Mode`**

Modify: `Sources/AutoCleanMacCore/SafeDeleter.swift:30`

```swift
public let mode: Mode
```

- [ ] **Step 5: Build + test**

Run: `swift build && swift test --filter AppPurgerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/AppPurger.swift Sources/AutoCleanMacCore/SafeDeleter.swift Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "feat(core): add AppPurger orchestrating app + leftover removal with cfprefsd flush"
```

### Task 3.2: Test elewacji + spy `elevatedRemove`

**Files:**
- Modify: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift`

- [ ] **Step 1: Test — gdy zwykły delete pada, używa elevatedRemove**

```swift
func test_purge_falls_back_to_elevated_on_permission_error() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
    let appURL = temp.appendingPathComponent("Applications/Locked.app")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 50).write(to: appURL.appendingPathComponent("contents"))
    defer { try? FileManager.default.removeItem(at: temp) }

    let logger = Logger(directoryURL: temp.appendingPathComponent("logs"))
    // Symulujemy "live" mode — żeby nie usunąć w fazie measurement, blokujemy zapis na katalogu rodzica.
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appURL.deletingLastPathComponent().path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appURL.deletingLastPathComponent().path) }

    var elevatedCalls: [URL] = []
    let purger = AppPurger(
        deleter: SafeDeleter(mode: .live, logger: logger),
        prefsDaemon: SpyPreferencesDaemon(),
        launchAgents: SpyLaunchAgentClient(),
        elevatedRemove: { url in
            elevatedCalls.append(url)
            // "Udajemy" sukces — usuwamy ręcznie po zdjęciu blokady chwilowo
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
            try FileManager.default.removeItem(at: url)
        },
        logger: logger
    )

    let outcome = await purger.purge(
        bundleID: "com.example.Locked",
        displayName: "Locked",
        appURL: appURL,
        homeDirectory: temp,
        systemRoot: temp,
        includeSystemPaths: false
    )

    XCTAssertEqual(elevatedCalls, [appURL])
    XCTAssertTrue(outcome.appRemoved)
    XCTAssertTrue(outcome.elevatedFallbackUsed)
    XCTAssertGreaterThan(outcome.bytesFreed, 0)
}
```

- [ ] **Step 2: Uruchom — PASS**

Run: `swift test --filter AppPurgerTests/test_purge_falls_back_to_elevated_on_permission_error`
Expected: PASS (logika już zaimplementowana w 3.1).

- [ ] **Step 3: Test — wywołuje `prefsDaemon.deleteAll` w trybie live**

```swift
func test_purge_calls_prefs_daemon_in_live_mode() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
    let appURL = temp.appendingPathComponent("Applications/Tiny.app")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let logger = Logger(directoryURL: temp.appendingPathComponent("logs"))
    let prefs = SpyPreferencesDaemon()
    _ = await AppPurger(
        deleter: SafeDeleter(mode: .live, logger: logger),
        prefsDaemon: prefs,
        launchAgents: SpyLaunchAgentClient(),
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
    XCTAssertEqual(prefs.calls, ["com.example.Tiny"])
}

func test_purge_skips_prefs_daemon_in_dryRun() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
    let appURL = temp.appendingPathComponent("Applications/Tiny.app")
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let logger = Logger(directoryURL: temp.appendingPathComponent("logs"))
    let prefs = SpyPreferencesDaemon()
    _ = await AppPurger(
        deleter: SafeDeleter(mode: .dryRun, logger: logger),
        prefsDaemon: prefs,
        launchAgents: SpyLaunchAgentClient(),
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
    XCTAssertTrue(prefs.calls.isEmpty)
}
```

- [ ] **Step 4: Uruchom — PASS**

Run: `swift test --filter AppPurgerTests`
Expected: wszystkie PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/AutoCleanMacCoreTests/AppPurgerTests.swift
git commit -m "test(core): cover AppPurger elevation fallback and prefs daemon flush"
```

---

## Phase 4 — Wpięcie `AppPurger` do AppDelegate

### Task 4.1: Refaktor closure `onUninstall` na delegację do AppPurger

**Files:**
- Modify: `Sources/AutoCleanMac/AppDelegate.swift:453-543` (cały blok `onUninstall` + `attemptElevatedRemoval`)

- [ ] **Step 1: Sprawdź obecny baseline testów**

Run: `swift test`
Expected: 84+ testów PASS (po dodanych w Phase 1-3 powinno być więcej).

- [ ] **Step 2: Zastąp closure wewnątrz `openSettings()`**

W `AppDelegate.swift`, znajdź `onUninstall: { [weak self] apps, mode in ... }` i zamień na:

```swift
onUninstall: { [weak self] apps, mode in
    guard let self else {
        return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: [])
    }
    let purger = AppPurger(
        deleter: SafeDeleter(mode: mode, logger: self.logger),
        prefsDaemon: ShellPreferencesDaemonClient(),
        launchAgents: ShellLaunchAgentClient(),
        elevatedRemove: { url in
            try await MainActor.run {
                if mode == .trash {
                    do { try ElevatedUninstall.trashViaFinder(url); return } catch { /* fallback */ }
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
    return UninstallOutcome(freedBytes: freed, succeeded: succeeded, failures: failures)
}
```

- [ ] **Step 3: Usuń pomocniczą metodę `attemptElevatedRemoval` i typ `ElevatedRemovalResult` z AppDelegate (są już niepotrzebne)**

W `AppDelegate.swift` usuń cały blok zaczynający się od `fileprivate enum ElevatedRemovalResult { ... }` oraz metodę `fileprivate func attemptElevatedRemoval(...)`.

- [ ] **Step 4: Build + test**

Run: `swift build && swift test`
Expected: build clean, wszystkie testy PASS.

- [ ] **Step 5: Smoke test ręczny**

```
./scripts/install.sh
```

Otwórz AutoCleanMac → Deinstalator → wybierz aplikację user-side (np. coś z `~/Applications`) → odinstaluj. Sprawdź:
- alert pokazuje realne MB,
- `~/Library/Preferences/<bundleID>.plist` zniknął,
- `~/Library/Caches/<bundleID>` zniknął.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMac/AppDelegate.swift
git commit -m "refactor(app): delegate uninstall flow to AppPurger with full leftover purge"
```

---

## Phase 5 — InstalledAppRegistry

### Task 5.1: Implementacja + test

**Files:**
- Create: `Sources/AutoCleanMacCore/InstalledAppRegistry.swift`
- Create: `Tests/AutoCleanMacCoreTests/InstalledAppRegistryTests.swift`

- [ ] **Step 1: Test — zbiera bundle IDs z fake katalogów Applications**

```swift
import XCTest
@testable import AutoCleanMacCore

final class InstalledAppRegistryTests: XCTestCase {
    func test_collects_bundle_ids_from_app_directories() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Registry-\(UUID().uuidString)")
        let dirA = temp.appendingPathComponent("Applications")
        let dirB = temp.appendingPathComponent("UserApps")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try makeAppBundle(at: dirA.appendingPathComponent("Foo.app"), bundleID: "com.example.foo")
        try makeAppBundle(at: dirB.appendingPathComponent("Bar.app"), bundleID: "com.example.bar")
        defer { try? FileManager.default.removeItem(at: temp) }

        let registry = InstalledAppRegistry()
        let ids = registry.installedBundleIDs(searchRoots: [dirA, dirB])
        XCTAssertEqual(ids, ["com.example.foo", "com.example.bar"])
    }

    private func makeAppBundle(at url: URL, bundleID: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": url.deletingPathExtension().lastPathComponent]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `swift test --filter InstalledAppRegistryTests`
Expected: FAIL.

- [ ] **Step 3: Implementacja**

`Sources/AutoCleanMacCore/InstalledAppRegistry.swift`:

```swift
import Foundation

public struct InstalledAppRegistry: Sendable {
    public init() {}

    /// Domyślne lokalizacje skanowania (production).
    public static func defaultSearchRoots(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            homeDirectory.appendingPathComponent("Applications"),
        ]
    }

    /// Zbiera bundle ID wszystkich `.app` w podanych katalogach (rekurencyjnie, ale `skipsPackageDescendants`).
    public func installedBundleIDs(searchRoots: [URL]) -> Set<String> {
        let fm = FileManager.default
        var ids: Set<String> = []
        for root in searchRoots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                    ids.insert(id)
                }
            }
        }
        return ids
    }
}
```

- [ ] **Step 4: Uruchom — PASS**

Run: `swift test --filter InstalledAppRegistryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/InstalledAppRegistry.swift Tests/AutoCleanMacCoreTests/InstalledAppRegistryTests.swift
git commit -m "feat(core): add InstalledAppRegistry collecting bundle IDs from Applications dirs"
```

---

## Phase 6 — OrphanScanner

### Task 6.1: Definicje typów i podstawowy test

**Files:**
- Create: `Sources/AutoCleanMacCore/OrphanScanner.swift`
- Create: `Tests/AutoCleanMacCoreTests/OrphanScannerTests.swift`

- [ ] **Step 1: Test — znajduje plist preferencji bez aplikacji**

```swift
import XCTest
@testable import AutoCleanMacCore

final class OrphanScannerTests: XCTestCase {
    func test_scan_returns_orphan_for_pref_without_installed_app() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: prefs.appendingPathComponent("com.dead.app.plist"))
        try Data(repeating: 1, count: 200).write(to: prefs.appendingPathComponent("com.alive.app.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let scanner = OrphanScanner()
        let orphans = scanner.scan(homeDirectory: temp, installedBundleIDs: ["com.alive.app"])
        let bundleIDs = orphans.map(\.bundleID).sorted()
        XCTAssertEqual(bundleIDs, ["com.dead.app"])
        XCTAssertEqual(orphans.first?.paths.count, 1)
        XCTAssertEqual(orphans.first?.totalBytes, 200)
    }

    func test_scan_groups_multiple_paths_for_same_bundle_id() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        let support = temp.appendingPathComponent("Library/Application Support/com.dead.app")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: prefs.appendingPathComponent("com.dead.app.plist"))
        try Data(repeating: 1, count: 50).write(to: support.appendingPathComponent("data.bin"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(orphans.first?.paths.count, 2)
        XCTAssertEqual(orphans.first?.totalBytes, 150)
    }

    func test_scan_skips_apple_system_bundle_ids() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data().write(to: prefs.appendingPathComponent("com.apple.dock.plist"))
        try Data().write(to: prefs.appendingPathComponent(".GlobalPreferences.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])
        XCTAssertTrue(orphans.isEmpty)
    }
}
```

- [ ] **Step 2: Uruchom — FAIL**

Run: `swift test --filter OrphanScannerTests`
Expected: FAIL.

- [ ] **Step 3: Implementacja**

`Sources/AutoCleanMacCore/OrphanScanner.swift`:

```swift
import Foundation

public struct OrphanGroup: Sendable, Identifiable {
    public let id: String  // == bundleID
    public let bundleID: String
    public let paths: [OrphanPath]
    public let totalBytes: Int64

    public init(bundleID: String, paths: [OrphanPath]) {
        self.id = bundleID
        self.bundleID = bundleID
        self.paths = paths
        self.totalBytes = paths.reduce(0) { $0 + $1.bytes }
    }
}

public struct OrphanPath: Sendable, Hashable {
    public let url: URL
    public let bytes: Int64
}

public struct OrphanScanner: Sendable {
    /// Bundle ID prefiksy, których nie raportujemy jako sieroty (system, Apple).
    public static let skippedPrefixes: [String] = [
        "com.apple.",
        ".GlobalPreferences",
    ]

    public init() {}

    public func scan(homeDirectory: URL, installedBundleIDs: Set<String>) -> [OrphanGroup] {
        let lib = homeDirectory.appendingPathComponent("Library")
        var byID: [String: [OrphanPath]] = [:]

        // Skanowane lokalizacje (basename → bundle ID).
        let plistDirs: [(URL, suffix: String)] = [
            (lib.appendingPathComponent("Preferences"), ".plist"),
            (lib.appendingPathComponent("LaunchAgents"), ".plist"),
            (lib.appendingPathComponent("Cookies"), ".binarycookies"),
        ]
        for (dir, suffix) in plistDirs {
            collectFiles(in: dir, suffix: suffix, into: &byID, installed: installedBundleIDs)
        }

        // Katalogi nazwane bundle ID.
        let dirRoots: [URL] = [
            lib.appendingPathComponent("Application Support"),
            lib.appendingPathComponent("Caches"),
            lib.appendingPathComponent("Containers"),
            lib.appendingPathComponent("HTTPStorages"),
            lib.appendingPathComponent("Logs"),
            lib.appendingPathComponent("WebKit"),
            lib.appendingPathComponent("Application Scripts"),
        ]
        for root in dirRoots {
            collectDirectories(in: root, into: &byID, installed: installedBundleIDs)
        }

        // Saved Application State – `<id>.savedState`.
        collectFiles(in: lib.appendingPathComponent("Saved Application State"), suffix: ".savedState", into: &byID, installed: installedBundleIDs)

        return byID
            .map { OrphanGroup(bundleID: $0.key, paths: $0.value) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    private func collectFiles(
        in dir: URL,
        suffix: String,
        into byID: inout [String: [OrphanPath]],
        installed: Set<String>
    ) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in entries where name.hasSuffix(suffix) {
            let stem = String(name.dropLast(suffix.count))
            let bundleID = bundleIDFromPlistStem(stem)
            guard isCandidateOrphan(bundleID: bundleID, installed: installed) else { continue }
            let url = dir.appendingPathComponent(name)
            let bytes = (try? SafeDeleter.recursiveMetrics(at: url).bytesFreed) ?? 0
            byID[bundleID, default: []].append(OrphanPath(url: url, bytes: bytes))
        }
    }

    private func collectDirectories(
        in root: URL,
        into byID: inout [String: [OrphanPath]],
        installed: Set<String>
    ) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in entries {
            guard isCandidateOrphan(bundleID: name, installed: installed) else { continue }
            let url = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let bytes = (try? SafeDeleter.recursiveMetrics(at: url).bytesFreed) ?? 0
            byID[name, default: []].append(OrphanPath(url: url, bytes: bytes))
        }
    }

    private func bundleIDFromPlistStem(_ stem: String) -> String {
        // Dla ByHost trzymamy się `<bundleID>.<UUID>` — odetnij ostatnią kropkę-UUID jeśli wygląda jak GUID/MAC.
        // Tu uproszczenie: zwracamy całość, sieroty ByHost trafiają do osobnych grup, co jest OK.
        return stem
    }

    private func isCandidateOrphan(bundleID: String, installed: Set<String>) -> Bool {
        guard !bundleID.isEmpty, !bundleID.hasPrefix(".") else { return false }
        for prefix in Self.skippedPrefixes where bundleID.hasPrefix(prefix) { return false }
        return !installed.contains(bundleID)
    }
}
```

- [ ] **Step 4: Uruchom — PASS**

Run: `swift test --filter OrphanScannerTests`
Expected: wszystkie PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/OrphanScanner.swift Tests/AutoCleanMacCoreTests/OrphanScannerTests.swift
git commit -m "feat(core): add OrphanScanner finding leftover prefs without installed apps"
```

---

## Phase 7 — UI: zakładka OrphanCleanerTab

### Task 7.1: Stwórz pustą zakładkę i podpiąć do nawigacji

**Files:**
- Create: `Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift`
- Modify: `Sources/AutoCleanMac/SettingsView.swift:145-187` (enum + switch)

- [ ] **Step 1: Stwórz szkielet zakładki**

`Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift`:

```swift
import SwiftUI
import AutoCleanMacCore

struct OrphanCleanerTab: View {
    @ObservedObject var settingsModel: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Osierocone preferencje")
                    .font(.headline)
                Spacer()
                if settingsModel.orphansScanning {
                    ProgressView().controlSize(.small)
                }
                Button("Skanuj") {
                    Task { await settingsModel.scanOrphans() }
                }
                .disabled(settingsModel.orphansScanning)
            }
            .padding()

            if settingsModel.orphans.isEmpty {
                Spacer()
                Text(settingsModel.orphansScanning ? "Skanowanie..." : "Brak osieroconych preferencji.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $settingsModel.selectedOrphans) {
                    ForEach(settingsModel.orphans) { group in
                        Section(group.bundleID) {
                            ForEach(group.paths, id: \.url) { path in
                                HStack {
                                    Text(path.url.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(ByteCountFormatter().string(fromByteCount: path.bytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(group.id)
                    }
                }
                .listStyle(.inset)

                HStack {
                    Text("Wybrano: \(settingsModel.selectedOrphans.count) grup")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        Task { await settingsModel.removeSelectedOrphans() }
                    } label: {
                        Text("Usuń zaznaczone")
                    }
                    .disabled(settingsModel.selectedOrphans.isEmpty || settingsModel.orphansScanning)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}
```

- [ ] **Step 2: Dodaj `case orphans` do `SettingsSection`**

W `SettingsView.swift:145-187`:

```swift
private enum SettingsSection: String, CaseIterable, Identifiable {
    case scanner
    case general
    case cleanup
    case browsers
    case uninstaller
    case orphans
    case reminders
    case advanced
    case statistics
    case logs
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanner: return "Skaner"
        case .general: return "Ogólne"
        case .statistics: return "Statystyki"
        case .about: return "O programie"
        case .cleanup: return "Czyszczenie"
        case .browsers: return "Przeglądarki"
        case .uninstaller: return "Deinstalator"
        case .orphans: return "Osierocone preferencje"
        case .reminders: return "Przypominacz"
        case .advanced: return "Zaawansowane"
        case .logs: return "Logi"
        }
    }

    var symbol: String {
        switch self {
        case .scanner: return "magnifyingglass"
        case .general: return "gearshape"
        case .statistics: return "chart.bar"
        case .about: return "info.circle"
        case .cleanup: return "trash"
        case .browsers: return "globe"
        case .uninstaller: return "app.dashed"
        case .orphans: return "questionmark.folder"
        case .reminders: return "bell"
        case .advanced: return "slider.horizontal.3"
        case .logs: return "doc.text"
        }
    }
}
```

- [ ] **Step 3: Dodaj case w `detailContent` switch**

W `SettingsView.swift:240` rozszerz `@ViewBuilder var detailContent`:

```swift
case .orphans:
    OrphanCleanerTab(settingsModel: model)
```

(Dokładną pozycję w switch wybierz po `case .uninstaller:` — sprawdź sąsiedztwo plikiem `smart_outline`.)

- [ ] **Step 4: Build — oczekiwane błędy bo brak `orphans*` w SettingsModel**

Run: `swift build`
Expected: błędy "value of type 'SettingsModel' has no member 'orphans'" — naprawimy w Task 7.2.

- [ ] **Step 5: NIE commituj jeszcze — kontynuuj do 7.2**

### Task 7.2: Stan i akcje w SettingsModel

**Files:**
- Modify: `Sources/AutoCleanMac/SettingsView.swift` (klasa `SettingsModel`)

- [ ] **Step 1: Dodaj pola @Published i callbacks**

W `SettingsView.swift` w klasie `SettingsModel`, dodaj po istniejących polach:

```swift
@Published var orphans: [OrphanGroup] = []
@Published var selectedOrphans: Set<String> = []
@Published var orphansScanning: Bool = false

let onScanOrphans: () async -> [OrphanGroup]
let onRemoveOrphans: ([OrphanGroup], SafeDeleter.Mode) async -> UninstallOutcome
```

Rozszerz `init` o parametry:

```swift
onScanOrphans: @escaping () async -> [OrphanGroup],
onRemoveOrphans: @escaping ([OrphanGroup], SafeDeleter.Mode) async -> UninstallOutcome,
```

oraz przypisanie:

```swift
self.onScanOrphans = onScanOrphans
self.onRemoveOrphans = onRemoveOrphans
```

I metody pomocnicze:

```swift
@MainActor
func scanOrphans() async {
    orphansScanning = true
    defer { orphansScanning = false }
    selectedOrphans = []
    orphans = await onScanOrphans()
}

@MainActor
func removeSelectedOrphans() async {
    let chosen = orphans.filter { selectedOrphans.contains($0.id) }
    guard !chosen.isEmpty else { return }
    _ = await onRemoveOrphans(chosen, deleteMode == .live ? .live : .trash)
    await scanOrphans()
}
```

- [ ] **Step 2: Build — błędy w `AppDelegate.openSettings()` (brak nowych argumentów w `SettingsModel(init:...)`)**

Run: `swift build`
Expected: błąd "missing arguments for parameters 'onScanOrphans' 'onRemoveOrphans'".

- [ ] **Step 3: NIE commituj — przejdź do 7.3**

### Task 7.3: Wpięcie w AppDelegate

**Files:**
- Modify: `Sources/AutoCleanMac/AppDelegate.swift` (`openSettings()`)

- [ ] **Step 1: Dodaj closures w wywołaniu `SettingsModel(...)`**

W `AppDelegate.swift` w `openSettings()`, w wywołaniu `SettingsModel(initial: ..., ...)` dodaj na końcu listy argumentów:

```swift
onScanOrphans: { [weak self] in
    guard let self else { return [] }
    let installed = InstalledAppRegistry().installedBundleIDs(
        searchRoots: InstalledAppRegistry.defaultSearchRoots(homeDirectory: home)
    )
    return OrphanScanner().scan(homeDirectory: home, installedBundleIDs: installed)
},
onRemoveOrphans: { [weak self] groups, mode in
    guard let self else { return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: []) }
    let deleter = SafeDeleter(mode: mode, logger: self.logger)
    let userLib = home.appendingPathComponent("Library")
    var freed: Int64 = 0
    var succeeded = 0
    var failures: [UninstallFailure] = []
    for group in groups {
        var groupOk = true
        for path in group.paths where FileManager.default.fileExists(atPath: path.url.path) {
            do {
                let metrics = try deleter.deleteMeasured(path.url, withinRoot: userLib)
                freed += metrics.bytesFreed
            } catch {
                groupOk = false
                failures.append(UninstallFailure(appName: group.bundleID, reason: (error as NSError).localizedDescription))
            }
        }
        if groupOk { succeeded += 1 }
    }
    return UninstallOutcome(freedBytes: freed, succeeded: succeeded, failures: failures)
}
```

- [ ] **Step 2: Build + test**

Run: `swift build && swift test`
Expected: build clean, wszystkie testy PASS.

- [ ] **Step 3: Smoke test ręczny**

```
./scripts/install.sh
```

Otwórz AutoCleanMac → "Osierocone preferencje" → kliknij "Skanuj". Sprawdź:
- lista wyświetla grupy plików dla bundle ID, których nie ma na dysku,
- zaznaczenie kilku + "Usuń zaznaczone" → faktyczny delete (Kosz w trybie domyślnym),
- ponowny skan pokazuje listę pomniejszoną o usunięte.

- [ ] **Step 4: Commit całości UI**

```bash
git add Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift Sources/AutoCleanMac/SettingsView.swift Sources/AutoCleanMac/AppDelegate.swift
git commit -m "feat(ui): add Orphan Preferences scanner tab with selectable cleanup"
```

---

## Phase 8 — Walidacja końcowa

### Task 8.1: Pełny build, testy, smoke test

**Files:**
- (brak modyfikacji — sanity check)

- [ ] **Step 1: Pełny build release**

Run: `swift build -c release`
Expected: clean.

- [ ] **Step 2: Pełna suite testów**

Run: `swift test 2>&1 | tail -10`
Expected: 84+ poprzednich + 14+ nowych = ~98+ testów PASS, 0 failures.

- [ ] **Step 3: Reinstall i E2E**

```
./scripts/install.sh
```

Test scenariuszy:
- Deinstalacja aplikacji user-side z resztkami w Application Support i Preferences → wszystko zniknęło.
- Deinstalacja root-owned w `/Applications` (np. zostawiony Perplexity w przykładzie wcześniej, jeśli reinstalujemy go) → prompt admin → cała aplikacja + system path resztki zniknęły.
- Skaner sierot → znajduje stare preferencje po dawno usuniętych aplikacjach.

- [ ] **Step 4: Sprawdź w `~/Library/Logs/AutoCleanMac` że `purge_done` ma `failures: 0`**

```bash
tail -n 30 ~/Library/Logs/AutoCleanMac/*.log
```

- [ ] **Step 5: Final commit (jeśli były drobne fixy)**

```bash
git status
git add -p
git commit -m "chore: final tidy from E2E validation"
```

---

## Self-Review

**Spec coverage:**
- (1) Pełne usuwanie preferencji przy deinstalacji → Phase 1 (paths) + Phase 2 (daemon) + Phase 3 (purger) + Phase 4 (wpięcie). ✓
- (2) Skaner osieroconych preferencji jako dodatkowa opcja → Phase 5 (registry) + Phase 6 (scanner) + Phase 7 (UI). ✓

**Niezamierzone luki:** żadne; wszystkie kategorie z dyskusji ("co już usuwamy / czego brakuje") trafiły do `LeftoverPathProvider`. System paths objęte przez `includeSystemPaths` flagę aktywną tylko dla `/Applications/...`.

**Type consistency:**
- `OrphanGroup.id == bundleID: String` — `selectedOrphans: Set<String>` zgadza się.
- `UninstallOutcome` reużywany dla obu flow (deinstalator + skaner sierot) — istniejący typ.
- `LeftoverPathProvider.userPaths` / `resolveDynamic` / `systemPaths` / `resolveDynamicSystem` — nazwy spójne, używane zgodnie w `AppPurger`, `AppScanner`, `OrphanScanner`.
- `SafeDeleter.mode` zmieniany na public — wszystkie miejsca w testach i `AppPurger` używają tej samej publicznej property.

**Placeholder scan:** brak TBD, TODO, "implement later", "fill in details", "similar to Task N". Każdy step zawiera konkretny kod lub komendę.

# Czyszczenie przeglądarek w Preferencjach — Plan Implementacji

> **Dla wykonawcy:** WYMAGANY SUB-SKILL: superpowers:subagent-driven-development (rekomendowany) albo superpowers:executing-plans. Kroki używają `- [ ]` do oznaczania postępu.

**Cel:** Dodać per-przeglądarka + per-typ-danych (cache/cookies/history) wybór czyszczenia, konfigurowalny z nowego okna Preferencji w SwiftUI.

**Architektura:** W `AutoCleanMacCore`: nowe typy `BrowserIdentity` (Chrome, Firefox, Edge, Brave, Vivaldi, Arc) i `BrowserDataType` (cache, cookies, history), nowy sparametryzowany `BrowserDataTask` zastępujący istniejący `BrowserCachesTask`, nowy `Config.browsers` dict, nowy `ConfigWriter` do atomowego zapisu konfiguracji. W `AutoCleanMac`: nowy `SettingsView.swift`, scene `Settings { … }` w `@main`, pozycja menu "Preferencje…" (⌘,). Legacy klucz `browser_caches: true` dalej działa jako alias (włącza cache dla wszystkich przeglądarek).

**Tech Stack:** Swift 5.9, SwiftUI Settings scene, XCTest, Foundation, AppKit (`NSRunningApplication` dla detekcji działającej przeglądarki). Pliki SQLite traktujemy jak zwykłe pliki (usuwamy razem z `-journal`, `-wal`, `-shm`) — bez zapytań SQL.

---

## Struktura plików

- Create: `Sources/AutoCleanMacCore/BrowserIdentity.swift` — enum `BrowserIdentity`, enum `BrowserDataType`, tabela ścieżek, `displayName`.
- Create: `Sources/AutoCleanMacCore/BrowserRunning.swift` — `BrowserRunning.isRunning(_:)` via `NSRunningApplication`.
- Create: `Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift` — `BrowserDataTask(browser:dataType:isEnabled:)` implementujący `CleanupTask`.
- Create: `Sources/AutoCleanMacCore/ConfigWriter.swift` — atomowy zapis `Config` do JSON.
- Modify: `Sources/AutoCleanMacCore/Config.swift` — dodanie `Browsers` dict + migracja `browser_caches` → cache all.
- Modify: `Sources/AutoCleanMacCore/CleanupEngine.swift` — `makeDefault` generuje po tasku na każdą (browser, type) parę.
- Delete: `Sources/AutoCleanMacCore/Tasks/BrowserCachesTask.swift` — zastąpiony.
- Create: `Sources/AutoCleanMac/SettingsView.swift` — SwiftUI okno Preferencji, sekcja Przeglądarki.
- Modify: `Sources/AutoCleanMac/AppDelegate.swift` — zarządzanie `NSWindow` Preferencji, callback od MenuBarController.
- Modify: `Sources/AutoCleanMac/MenuBarController.swift` — nowy item "Preferencje…" z `keyEquivalent: ","`.
- Test: `Tests/AutoCleanMacCoreTests/BrowserIdentityTests.swift`
- Test: `Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift`
- Test: `Tests/AutoCleanMacCoreTests/ConfigWriterTests.swift`
- Modify: `Tests/AutoCleanMacCoreTests/ConfigTests.swift` — testy migracji + nowy format `browsers`.

---

## Task 1: Enumy `BrowserIdentity` i `BrowserDataType` + tabela ścieżek

**Dlaczego:** Reszta kodu się od tego odbija — najpierw niezależny, testowalny opis "co to jest Chrome" / "co to jest cookies dla Firefoxa".

**Files:**
- Create: `Sources/AutoCleanMacCore/BrowserIdentity.swift`
- Create: `Tests/AutoCleanMacCoreTests/BrowserIdentityTests.swift`

---

- [ ] **Step 1: Napisz failing testy**

Zapisz `Tests/AutoCleanMacCoreTests/BrowserIdentityTests.swift`:

```swift
import XCTest
@testable import AutoCleanMacCore

final class BrowserIdentityTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/test")

    func test_all_browsers_have_stable_raw_values() {
        XCTAssertEqual(BrowserIdentity.chrome.rawValue,  "chrome")
        XCTAssertEqual(BrowserIdentity.firefox.rawValue, "firefox")
        XCTAssertEqual(BrowserIdentity.edge.rawValue,    "edge")
        XCTAssertEqual(BrowserIdentity.brave.rawValue,   "brave")
        XCTAssertEqual(BrowserIdentity.vivaldi.rawValue, "vivaldi")
        XCTAssertEqual(BrowserIdentity.arc.rawValue,     "arc")
    }

    func test_data_type_raw_values() {
        XCTAssertEqual(BrowserDataType.cache.rawValue,   "cache")
        XCTAssertEqual(BrowserDataType.cookies.rawValue, "cookies")
        XCTAssertEqual(BrowserDataType.history.rawValue, "history")
    }

    func test_chrome_profile_roots_include_default() {
        let roots = BrowserIdentity.chrome.profileRoots(homeDirectory: home)
        XCTAssertTrue(roots.contains(home.appendingPathComponent("Library/Application Support/Google/Chrome")))
    }

    func test_firefox_profile_roots_include_app_support_and_caches() {
        let roots = BrowserIdentity.firefox.profileRoots(homeDirectory: home)
        XCTAssertTrue(roots.contains(home.appendingPathComponent("Library/Application Support/Firefox/Profiles")))
        XCTAssertTrue(roots.contains(home.appendingPathComponent("Library/Caches/Firefox/Profiles")))
    }

    func test_edge_brave_vivaldi_arc_roots() {
        XCTAssertTrue(BrowserIdentity.edge.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/Microsoft Edge")))
        XCTAssertTrue(BrowserIdentity.brave.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")))
        XCTAssertTrue(BrowserIdentity.vivaldi.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/Vivaldi")))
        XCTAssertTrue(BrowserIdentity.arc.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/Arc/User Data")))
    }

    func test_bundle_identifiers_are_stable() {
        XCTAssertEqual(BrowserIdentity.chrome.bundleIdentifiers,  ["com.google.Chrome"])
        XCTAssertEqual(BrowserIdentity.firefox.bundleIdentifiers, ["org.mozilla.firefox"])
        XCTAssertEqual(BrowserIdentity.edge.bundleIdentifiers,    ["com.microsoft.edgemac"])
        XCTAssertEqual(BrowserIdentity.brave.bundleIdentifiers,   ["com.brave.Browser"])
        XCTAssertEqual(BrowserIdentity.vivaldi.bundleIdentifiers, ["com.vivaldi.Vivaldi"])
        XCTAssertEqual(BrowserIdentity.arc.bundleIdentifiers,     ["company.thebrowser.Browser"])
    }
}
```

- [ ] **Step 2: Uruchom testy, potwierdź że failują**

Run: `swift test --filter BrowserIdentityTests`
Expected: błąd kompilacji "cannot find 'BrowserIdentity' in scope".

- [ ] **Step 3: Zaimplementuj `BrowserIdentity` i `BrowserDataType`**

Zapisz `Sources/AutoCleanMacCore/BrowserIdentity.swift`:

```swift
import Foundation

/// Identyfikator obsługiwanej przeglądarki. Safari celowo pominięte w v1 (wymaga TCC Full Disk Access).
public enum BrowserIdentity: String, CaseIterable, Equatable, Hashable {
    case chrome, firefox, edge, brave, vivaldi, arc

    public var displayName: String {
        switch self {
        case .chrome:  return "Google Chrome"
        case .firefox: return "Firefox"
        case .edge:    return "Microsoft Edge"
        case .brave:   return "Brave"
        case .vivaldi: return "Vivaldi"
        case .arc:     return "Arc"
        }
    }

    /// Katalogi w których leżą profile przeglądarki (każdy profil to podkatalog, np. "Default", "Profile 1").
    public func profileRoots(homeDirectory: URL) -> [URL] {
        let appSupport = homeDirectory.appendingPathComponent("Library/Application Support")
        let caches     = homeDirectory.appendingPathComponent("Library/Caches")
        switch self {
        case .chrome:  return [appSupport.appendingPathComponent("Google/Chrome")]
        case .firefox:
            return [
                appSupport.appendingPathComponent("Firefox/Profiles"),
                caches.appendingPathComponent("Firefox/Profiles"),
            ]
        case .edge:    return [appSupport.appendingPathComponent("Microsoft Edge")]
        case .brave:   return [appSupport.appendingPathComponent("BraveSoftware/Brave-Browser")]
        case .vivaldi: return [appSupport.appendingPathComponent("Vivaldi")]
        case .arc:     return [appSupport.appendingPathComponent("Arc/User Data")]
        }
    }

    /// Bundle identifiery do wykrywania czy przeglądarka jest uruchomiona (NSRunningApplication).
    public var bundleIdentifiers: [String] {
        switch self {
        case .chrome:  return ["com.google.Chrome"]
        case .firefox: return ["org.mozilla.firefox"]
        case .edge:    return ["com.microsoft.edgemac"]
        case .brave:   return ["com.brave.Browser"]
        case .vivaldi: return ["com.vivaldi.Vivaldi"]
        case .arc:     return ["company.thebrowser.Browser"]
        }
    }

    /// Czy to silnik Chromium (wspólny layout profili).
    public var isChromium: Bool { self != .firefox }
}

public enum BrowserDataType: String, CaseIterable, Equatable, Hashable {
    case cache, cookies, history

    public var displayName: String {
        switch self {
        case .cache:   return "Cache"
        case .cookies: return "Ciasteczka"
        case .history: return "Historia"
        }
    }
}
```

- [ ] **Step 4: Potwierdź że testy przechodzą**

Run: `swift test --filter BrowserIdentityTests`
Expected: 5 testów PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/BrowserIdentity.swift Tests/AutoCleanMacCoreTests/BrowserIdentityTests.swift
git commit -m "feat(core): add BrowserIdentity and BrowserDataType enums

Describes supported browsers (Chrome, Firefox, Edge, Brave, Vivaldi, Arc)
and the three cleanable data types (cache, cookies, history). Exposes
profile root directories and bundle identifiers for running-process
detection. Safari intentionally omitted in v1 (TCC Full Disk Access)."
```

---

## Task 2: Wykrywanie uruchomionej przeglądarki (`BrowserRunning`)

**Dlaczego:** Pliki SQLite cookies/history są zablokowane gdy przeglądarka działa. Zamiast psuć bazę, task ma pominąć browser z warningiem.

**Files:**
- Create: `Sources/AutoCleanMacCore/BrowserRunning.swift`

**Testy:** pomijamy — `NSRunningApplication` jest AppKit-specific i trudno go zamockować w czystym XCTest bez infrastruktury. Weryfikacja manualna w Tasku 9 (integration smoke).

---

- [ ] **Step 1: Zaimplementuj pomocniczą strukturę**

Zapisz `Sources/AutoCleanMacCore/BrowserRunning.swift`:

```swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Wykrywa czy dana przeglądarka jest aktualnie uruchomiona. Jeśli AppKit niedostępny
/// (np. testy na Linuksie) zawsze zwraca false — wtedy taski po prostu będą usuwać pliki
/// jakby browser był zamknięty.
public enum BrowserRunning {
    public static func isRunning(_ browser: BrowserIdentity) -> Bool {
        #if canImport(AppKit)
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        return browser.bundleIdentifiers.contains { running.contains($0) }
        #else
        return false
        #endif
    }
}
```

- [ ] **Step 2: Zbuduj**

Run: `swift build`
Expected: `Build complete!` bez nowych warningów.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCleanMacCore/BrowserRunning.swift
git commit -m "feat(core): add BrowserRunning helper via NSRunningApplication

Returns true if any of a browser's bundle identifiers matches a running
app. Used by BrowserDataTask to skip locked SQLite files safely.
Compiled-out on non-AppKit platforms (tests stay platform-portable)."
```

---

## Task 3: `BrowserDataTask` — cache

**Dlaczego:** Start od najbezpieczniejszego typu danych. Cache = pliki binarne, nie SQLite, bez logowań do utracenia. Generyczna struktura `BrowserDataTask` powstaje tu, cookies i history doklejamy w Task 4/5.

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift`
- Test: `Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift`

---

- [ ] **Step 1: Napisz failing test dla cache na fake Chromium-profile**

Zapisz `Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift`:

```swift
import XCTest
@testable import AutoCleanMacCore

final class BrowserDataTaskTests: XCTestCase {
    var tempDir: URL!
    var logger: Logger!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logger = try Logger(directory: tempDir.appendingPathComponent("logs"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func context() -> CleanupContext {
        CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .live, logger: logger),
            logger: logger,
            homeDirectory: tempDir
        )
    }

    func test_disabled_task_skips() async throws {
        let task = BrowserDataTask(browser: .chrome, dataType: .cache, isEnabled: false)
        let result = await task.run(context: context())
        XCTAssertTrue(result.skipped)
    }

    func test_chrome_cache_deletes_Cache_and_CodeCache_under_each_profile() async throws {
        let base = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome")
        let defaultCache = base.appendingPathComponent("Default/Cache/f1.bin")
        let defaultCode  = base.appendingPathComponent("Default/Code Cache/js/f2.bin")
        let p1Cache      = base.appendingPathComponent("Profile 1/Cache/f3.bin")
        let outside      = base.appendingPathComponent("Default/Bookmarks") // MUSI zostać
        try Fixtures.makeFile(at: defaultCache, size: 100)
        try Fixtures.makeFile(at: defaultCode,  size: 200)
        try Fixtures.makeFile(at: p1Cache,      size: 300)
        try Fixtures.makeFile(at: outside,      size: 999)

        let task = BrowserDataTask(browser: .chrome, dataType: .cache, isEnabled: true)
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 600)
        XCTAssertFalse(result.skipped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultCode.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: p1Cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_skips_when_no_profile_root_exists() async throws {
        // brak żadnego katalogu Chrome w tempDir
        let task = BrowserDataTask(browser: .chrome, dataType: .cache, isEnabled: true)
        let result = await task.run(context: context())
        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.skipReason, "no browser profile directories")
    }
}
```

- [ ] **Step 2: Uruchom testy, potwierdź że failują**

Run: `swift test --filter BrowserDataTaskTests`
Expected: kompilacja nie przejdzie — "cannot find 'BrowserDataTask' in scope".

- [ ] **Step 3: Zaimplementuj `BrowserDataTask` ze wsparciem TYLKO dla `.cache`**

Zapisz `Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift`:

```swift
import Foundation

public struct BrowserDataTask: CleanupTask {
    public let browser: BrowserIdentity
    public let dataType: BrowserDataType
    public let isEnabled: Bool

    private let isBrowserRunning: (BrowserIdentity) -> Bool

    public var displayName: String {
        "\(browser.displayName) — \(dataType.displayName)"
    }

    /// Główny init używany produkcyjnie.
    public init(browser: BrowserIdentity, dataType: BrowserDataType, isEnabled: Bool) {
        self.init(browser: browser, dataType: dataType, isEnabled: isEnabled, isBrowserRunning: BrowserRunning.isRunning)
    }

    /// Testowalny init — pozwala wstrzyknąć stub detekcji uruchomionej przeglądarki.
    public init(
        browser: BrowserIdentity,
        dataType: BrowserDataType,
        isEnabled: Bool,
        isBrowserRunning: @escaping (BrowserIdentity) -> Bool
    ) {
        self.browser = browser
        self.dataType = dataType
        self.isEnabled = isEnabled
        self.isBrowserRunning = isBrowserRunning
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else { return TaskResult(skipped: true, skipReason: "disabled") }

        let roots = browser.profileRoots(homeDirectory: context.homeDirectory)
            .filter { context.fileManager.fileExists(atPath: $0.path) }
        guard !roots.isEmpty else {
            return TaskResult(skipped: true, skipReason: "no browser profile directories")
        }

        if isBrowserRunning(browser) {
            return TaskResult(
                bytesFreed: 0,
                warnings: ["\(browser.displayName) jest uruchomiony — pomijam (zamknij przeglądarkę żeby wyczyścić)"],
                skipped: true,
                skipReason: "browser running"
            )
        }

        var freed: Int64 = 0
        var warnings: [String] = []
        for profilesRoot in roots {
            for profile in listProfileDirs(in: profilesRoot, fileManager: context.fileManager) {
                let paths = itemsToDelete(in: profile)
                for url in paths where context.fileManager.fileExists(atPath: url.path) {
                    do {
                        freed += try context.deleter.delete(url, withinRoot: profile)
                    } catch {
                        warnings.append("\(url.lastPathComponent): \(error)")
                    }
                }
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }

    private func listProfileDirs(in root: URL, fileManager: FileManager) -> [URL] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Lista konkretnych plików/katalogów do usunięcia w obrębie jednego profilu.
    private func itemsToDelete(in profile: URL) -> [URL] {
        switch (browser.isChromium, dataType) {
        case (true, .cache):
            return [
                profile.appendingPathComponent("Cache"),
                profile.appendingPathComponent("Code Cache"),
                profile.appendingPathComponent("GPUCache"),
            ]
        case (false, .cache):
            // Firefox cache — zarówno pod Application Support/Firefox/Profiles jak i Caches/Firefox/Profiles
            return [profile.appendingPathComponent("cache2")]
        case (true, .cookies), (true, .history), (false, .cookies), (false, .history):
            // wypełnione w kolejnych taskach (4, 5)
            return []
        }
    }
}
```

- [ ] **Step 4: Uruchom testy**

Run: `swift test --filter BrowserDataTaskTests`
Expected: 3 testy PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift
git commit -m "feat(core): add BrowserDataTask with cache support

Parameterized task (browser × dataType × isEnabled). Walks each profile
in the browser's Application Support (and Caches for Firefox) tree and
deletes Cache / Code Cache / GPUCache for Chromium, cache2 for Firefox.
Skips with warning when the browser is running (locked SQLite safety).
Cookies and history handled in follow-up tasks."
```

---

## Task 4: `BrowserDataTask` — cookies

**Dlaczego:** SQLite pliki cookies są szczególnym przypadkiem — usuwamy zarówno główny plik (`Cookies` dla Chromium, `cookies.sqlite` dla Firefox) jak i towarzyszące journalowe (`-journal`, `-wal`, `-shm`). Detekcja "czy browser działa" jest krytyczna — operacja na otwartej bazie SQLite = uszkodzenie.

**Files:**
- Modify: `Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift`
- Test: `Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift`

---

- [ ] **Step 1: Napisz failing testy**

Dodaj do `Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift` (przed zamykającą klamrą klasy):

```swift
func test_chrome_cookies_deletes_Cookies_and_journal() async throws {
    let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
    try Fixtures.makeFile(at: profile.appendingPathComponent("Cookies"),         size: 500)
    try Fixtures.makeFile(at: profile.appendingPathComponent("Cookies-journal"), size: 50)
    try Fixtures.makeFile(at: profile.appendingPathComponent("Bookmarks"),       size: 999) // zostaje

    let task = BrowserDataTask(browser: .chrome, dataType: .cookies, isEnabled: true, isBrowserRunning: { _ in false })
    let result = await task.run(context: context())

    XCTAssertEqual(result.bytesFreed, 550)
    XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Cookies").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Cookies-journal").path))
    XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path))
}

func test_firefox_cookies_deletes_sqlite_and_wal_shm() async throws {
    let profile = tempDir.appendingPathComponent("Library/Application Support/Firefox/Profiles/abc.default")
    try Fixtures.makeFile(at: profile.appendingPathComponent("cookies.sqlite"),     size: 400)
    try Fixtures.makeFile(at: profile.appendingPathComponent("cookies.sqlite-wal"), size: 30)
    try Fixtures.makeFile(at: profile.appendingPathComponent("cookies.sqlite-shm"), size: 20)
    try Fixtures.makeFile(at: profile.appendingPathComponent("places.sqlite"),      size: 9999) // MUSI zostać

    let task = BrowserDataTask(browser: .firefox, dataType: .cookies, isEnabled: true, isBrowserRunning: { _ in false })
    let result = await task.run(context: context())

    XCTAssertEqual(result.bytesFreed, 450)
    XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("cookies.sqlite").path))
    XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("places.sqlite").path))
}

func test_running_browser_skips_with_warning() async throws {
    let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
    try Fixtures.makeFile(at: profile.appendingPathComponent("Cookies"), size: 500)

    let task = BrowserDataTask(browser: .chrome, dataType: .cookies, isEnabled: true, isBrowserRunning: { _ in true })
    let result = await task.run(context: context())

    XCTAssertTrue(result.skipped)
    XCTAssertEqual(result.skipReason, "browser running")
    XCTAssertFalse(result.warnings.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Cookies").path))
}
```

- [ ] **Step 2: Uruchom testy — oczekiwane FAIL**

Run: `swift test --filter BrowserDataTaskTests/test_chrome_cookies_deletes_Cookies_and_journal`
Expected: FAIL — `itemsToDelete` dla (Chromium, cookies) zwraca `[]`, `bytesFreed` = 0.

- [ ] **Step 3: Rozszerz `itemsToDelete` o cookies**

W `Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift`, w metodzie `itemsToDelete(in:)`, zastąp case dla cookies (aktualnie zwraca `[]`):

```swift
        case (true, .cookies):
            return [
                profile.appendingPathComponent("Cookies"),
                profile.appendingPathComponent("Cookies-journal"),
                profile.appendingPathComponent("Network/Cookies"),          // nowe wersje Chromium
                profile.appendingPathComponent("Network/Cookies-journal"),
            ]
        case (false, .cookies):
            return [
                profile.appendingPathComponent("cookies.sqlite"),
                profile.appendingPathComponent("cookies.sqlite-wal"),
                profile.appendingPathComponent("cookies.sqlite-shm"),
            ]
```

- [ ] **Step 4: Uruchom testy**

Run: `swift test --filter BrowserDataTaskTests`
Expected: 6 testów (3 istniejące + 3 nowe) PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift
git commit -m "feat(core): BrowserDataTask handles cookies

Chromium: deletes Cookies + Cookies-journal (including the newer
Network/Cookies path). Firefox: deletes cookies.sqlite + -wal + -shm,
explicitly preserves places.sqlite (bookmarks+history). Running-browser
detection short-circuits the whole operation with a user-facing warning
to avoid corrupting locked SQLite files."
```

---

## Task 5: `BrowserDataTask` — history (z zabezpieczeniem dla Firefoxa)

**Dlaczego:** Chromium: `History` SQLite — zwykły plik, usuwamy. **Firefox: `places.sqlite` zawiera historię i zakładki w jednej bazie — NIE TYKAMY.** Czyścimy tylko `formhistory.sqlite` (autofill formularzy) i `downloads.sqlite` (historia pobrań). Użytkownik w UI zobaczy jawny komunikat o tym.

**Files:**
- Modify: `Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift`
- Test: `Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift`

---

- [ ] **Step 1: Napisz failing testy**

Dodaj do `Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift`:

```swift
func test_chrome_history_deletes_History_and_journal() async throws {
    let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
    try Fixtures.makeFile(at: profile.appendingPathComponent("History"),         size: 800)
    try Fixtures.makeFile(at: profile.appendingPathComponent("History-journal"), size: 40)
    try Fixtures.makeFile(at: profile.appendingPathComponent("Bookmarks"),       size: 999) // zostaje

    let task = BrowserDataTask(browser: .chrome, dataType: .history, isEnabled: true, isBrowserRunning: { _ in false })
    let result = await task.run(context: context())

    XCTAssertEqual(result.bytesFreed, 840)
    XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("History").path))
    XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path))
}

func test_firefox_history_preserves_places_sqlite_and_deletes_formhistory_downloads() async throws {
    let profile = tempDir.appendingPathComponent("Library/Application Support/Firefox/Profiles/abc.default")
    try Fixtures.makeFile(at: profile.appendingPathComponent("places.sqlite"),       size: 9999) // MUSI zostać (bookmarks!)
    try Fixtures.makeFile(at: profile.appendingPathComponent("formhistory.sqlite"),  size: 700)
    try Fixtures.makeFile(at: profile.appendingPathComponent("downloads.sqlite"),    size: 200)

    let task = BrowserDataTask(browser: .firefox, dataType: .history, isEnabled: true, isBrowserRunning: { _ in false })
    let result = await task.run(context: context())

    XCTAssertEqual(result.bytesFreed, 900)
    XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("places.sqlite").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("formhistory.sqlite").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("downloads.sqlite").path))
}
```

- [ ] **Step 2: Uruchom — oczekiwane FAIL**

Run: `swift test --filter BrowserDataTaskTests/test_chrome_history_deletes_History_and_journal`
Expected: FAIL — zero zwolnione.

- [ ] **Step 3: Rozszerz `itemsToDelete` o history**

W `BrowserDataTask.swift`, w `itemsToDelete(in:)`, zastąp case history:

```swift
        case (true, .history):
            return [
                profile.appendingPathComponent("History"),
                profile.appendingPathComponent("History-journal"),
                profile.appendingPathComponent("Visited Links"),
                profile.appendingPathComponent("Top Sites"),
                profile.appendingPathComponent("Top Sites-journal"),
            ]
        case (false, .history):
            // CELOWO nie tykamy places.sqlite — zawiera zakładki. Czyścimy tylko poboczne bazy historii.
            return [
                profile.appendingPathComponent("formhistory.sqlite"),
                profile.appendingPathComponent("formhistory.sqlite-wal"),
                profile.appendingPathComponent("formhistory.sqlite-shm"),
                profile.appendingPathComponent("downloads.sqlite"),
                profile.appendingPathComponent("downloads.sqlite-wal"),
                profile.appendingPathComponent("downloads.sqlite-shm"),
            ]
```

- [ ] **Step 4: Uruchom wszystkie testy**

Run: `swift test --filter BrowserDataTaskTests`
Expected: 8 PASS (3 + 3 + 2).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/BrowserDataTask.swift Tests/AutoCleanMacCoreTests/BrowserDataTaskTests.swift
git commit -m "feat(core): BrowserDataTask handles history

Chromium: deletes History + History-journal + Visited Links + Top Sites.
Firefox: DELIBERATELY preserves places.sqlite (contains bookmarks AND
history in one DB) and only clears formhistory.sqlite and
downloads.sqlite — otherwise users would silently lose bookmarks. UI
will surface this caveat next to the Firefox/history toggle."
```

---

## Task 6: `Config.browsers` + migracja z `browser_caches`

**Dlaczego:** Silnik musi wiedzieć które kombinacje (browser × dataType) są włączone. Istniejący klucz `browser_caches: true` dalej powinien działać — oznacza "cache dla wszystkich" — żeby nie łamać istniejących configów.

**Files:**
- Modify: `Sources/AutoCleanMacCore/Config.swift`
- Test: `Tests/AutoCleanMacCoreTests/ConfigTests.swift`

---

- [ ] **Step 1: Napisz failing testy**

Dodaj do `Tests/AutoCleanMacCoreTests/ConfigTests.swift`:

```swift
func test_default_browsers_all_types_off() {
    let missing = tempDir.appendingPathComponent("nope.json")
    let config = Config.loadOrDefault(from: missing, warn: { _ in })
    // Domyślnie nic nie jest aktywne per-browser — użytkownik świadomie włącza.
    for browser in BrowserIdentity.allCases {
        XCTAssertFalse(config.browsers[browser, default: .none].contains(.cache))
        XCTAssertFalse(config.browsers[browser, default: .none].contains(.cookies))
        XCTAssertFalse(config.browsers[browser, default: .none].contains(.history))
    }
}

func test_legacy_browser_caches_true_enables_cache_for_all_browsers() throws {
    let file = tempDir.appendingPathComponent("c.json")
    try #"{ "tasks": { "browser_caches": true } }"#.write(to: file, atomically: true, encoding: .utf8)
    let config = Config.loadOrDefault(from: file, warn: { _ in })
    for browser in BrowserIdentity.allCases {
        XCTAssertTrue(config.browsers[browser, default: .none].contains(.cache),
                      "cache powinno być włączone dla \(browser) przez legacy browser_caches")
        XCTAssertFalse(config.browsers[browser, default: .none].contains(.cookies))
    }
}

func test_explicit_browsers_section_takes_precedence() throws {
    let file = tempDir.appendingPathComponent("c.json")
    let json = """
    {
      "browsers": {
        "chrome":  { "cache": true,  "cookies": true,  "history": false },
        "firefox": { "cache": false, "cookies": true,  "history": true  }
      }
    }
    """
    try json.write(to: file, atomically: true, encoding: .utf8)
    let config = Config.loadOrDefault(from: file, warn: { _ in })
    XCTAssertTrue (config.browsers[.chrome]!.contains(.cache))
    XCTAssertTrue (config.browsers[.chrome]!.contains(.cookies))
    XCTAssertFalse(config.browsers[.chrome]!.contains(.history))
    XCTAssertFalse(config.browsers[.firefox]!.contains(.cache))
    XCTAssertTrue (config.browsers[.firefox]!.contains(.cookies))
    XCTAssertTrue (config.browsers[.firefox]!.contains(.history))
    // Przeglądarki nienadmienione pozostają puste
    XCTAssertEqual(config.browsers[.edge, default: .none], [])
}

func test_explicit_browsers_override_legacy() throws {
    // Gdy obecne jest obie: legacy browser_caches: true ORAZ browsers.chrome.cache: false,
    // jawna sekcja browsers wygrywa dla Chrome. Legacy nadal działa dla pozostałych.
    let file = tempDir.appendingPathComponent("c.json")
    let json = """
    {
      "tasks":   { "browser_caches": true },
      "browsers": { "chrome": { "cache": false, "cookies": false, "history": false } }
    }
    """
    try json.write(to: file, atomically: true, encoding: .utf8)
    let config = Config.loadOrDefault(from: file, warn: { _ in })
    XCTAssertFalse(config.browsers[.chrome, default: .none].contains(.cache))
    XCTAssertTrue (config.browsers[.firefox, default: .none].contains(.cache))
}
```

- [ ] **Step 2: Uruchom — oczekiwane FAIL (kompilacja)**

Run: `swift test --filter ConfigTests`
Expected: błąd "value of type 'Config' has no member 'browsers'".

- [ ] **Step 3: Rozszerz `Config`**

W `Sources/AutoCleanMacCore/Config.swift`:

(a) Dodaj **nad** `public struct Config`:

```swift
/// Zestaw typów danych do wyczyszczenia dla jednej przeglądarki.
public struct BrowserPreferences: Equatable {
    public var types: Set<BrowserDataType>

    public init(types: Set<BrowserDataType> = []) { self.types = types }

    public static let none = BrowserPreferences(types: [])

    public func contains(_ type: BrowserDataType) -> Bool { types.contains(type) }

    public mutating func set(_ type: BrowserDataType, _ enabled: Bool) {
        if enabled { types.insert(type) } else { types.remove(type) }
    }
}
```

(b) W `struct Config` dodaj pole **po** `tasks` (przed `deleteMode`):

```swift
    public var browsers: [BrowserIdentity: BrowserPreferences]
```

(c) Zaktualizuj `Config.default`:

```swift
    public static let `default` = Config(
        retentionDays: 7, window: .default, tasks: .default,
        browsers: [:],
        deleteMode: .trash
    )
```

(d) W `loadOrDefault(from:warn:)` dodaj **po** parsowaniu `tasks`, a **przed** `delete_mode`:

```swift
        // Legacy: browser_caches: true włącza cache dla wszystkich przeglądarek
        var browsers: [BrowserIdentity: BrowserPreferences] = [:]
        if let tasksJson = json["tasks"] as? [String: Any],
           let legacy = tasksJson["browser_caches"] as? Bool, legacy {
            for b in BrowserIdentity.allCases {
                browsers[b] = BrowserPreferences(types: [.cache])
            }
        }
        // Jawna sekcja browsers — nadpisuje legacy per-browser
        if let browsersJson = json["browsers"] as? [String: Any] {
            for (key, value) in browsersJson {
                guard let browser = BrowserIdentity(rawValue: key),
                      let obj = value as? [String: Any] else { continue }
                var prefs = BrowserPreferences()
                for type in BrowserDataType.allCases {
                    if let enabled = obj[type.rawValue] as? Bool, enabled {
                        prefs.types.insert(type)
                    }
                }
                browsers[browser] = prefs
            }
        }
        config.browsers = browsers
```

- [ ] **Step 4: Uruchom wszystkie testy**

Run: `swift test`
Expected: wszystkie PASS (4 nowe + wszystkie dotychczasowe). Uwaga: może trzeba wyzerować `config.browsers` w dotychczasowym teście `test_default_when_file_missing` — jeśli on sprawdza równość całego `Config.default`, nic nie trzeba zmieniać bo `Config.default.browsers == [:]`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Config.swift Tests/AutoCleanMacCoreTests/ConfigTests.swift
git commit -m "feat(core): add Config.browsers with legacy migration

New field: browsers: [BrowserIdentity: BrowserPreferences], parsed from
the JSON 'browsers' object with snake_case keys. Legacy tasks.browser_caches=true
still works — it enables cache for every supported browser. Explicit
per-browser entries take precedence over the legacy shortcut."
```

---

## Task 7: `CleanupEngine.makeDefault` generuje taski przeglądarek

**Dlaczego:** Stara lista tasków w `makeDefault` zawiera jeden `BrowserCachesTask` — trzeba go usunąć i zastąpić N tasków `BrowserDataTask` na podstawie `config.browsers`.

**Files:**
- Modify: `Sources/AutoCleanMacCore/CleanupEngine.swift`
- Delete: `Sources/AutoCleanMacCore/Tasks/BrowserCachesTask.swift`
- Test: `Tests/AutoCleanMacCoreTests/CleanupEngineTests.swift` (lekki smoke, jeśli istnieją)

---

- [ ] **Step 1: Sprawdź co kompiluje/testy**

Run: `swift build 2>&1 | tail -10` przed zmianami — żebyś wiedział co referuje `BrowserCachesTask`. Jedyne miejsce użycia to `CleanupEngine.makeDefault`.

- [ ] **Step 2: Zaktualizuj `makeDefault`**

W `Sources/AutoCleanMacCore/CleanupEngine.swift`, zastąp linię:

```swift
            BrowserCachesTask(isEnabled: config.tasks.browserCaches),
```

bloczkiem:

```swift
            // BrowserCachesTask zastąpiony per-browser × per-type zestawem zadań poniżej.
```

A w tym samym `makeDefault`, po ostatniej linii tasków (po `DownloadsTask(...)`), dodaj:

```swift
        var all: [CleanupTask] = [
            UserCachesTask(isEnabled: config.tasks.userCaches),
            SystemTempTask(isEnabled: config.tasks.systemTemp),
            TrashTask(isEnabled: config.tasks.trash),
            DSStoreTask(isEnabled: config.tasks.dsStore),
            UserLogsTask(isEnabled: config.tasks.userLogs),
            DevCachesTask(isEnabled: config.tasks.devCaches),
            DownloadsTask(isEnabled: config.tasks.downloads),
        ]
        for browser in BrowserIdentity.allCases {
            let prefs = config.browsers[browser, default: .none]
            for type in BrowserDataType.allCases where prefs.contains(type) {
                all.append(BrowserDataTask(browser: browser, dataType: type, isEnabled: true))
            }
        }
        return CleanupEngine(tasks: all)
```

…i usuń stare `return CleanupEngine(tasks: [...])`.

Uwaga: musisz usunąć `BrowserCachesTask(…)` z listy i zamiast tego umieścić tylko powyższe `all`. Jeśli poprzedni `return` ma dokładnie 8 pozycji (z browser_caches), po zmianie ma 7 statycznych + dynamicznie doklejane per-browser.

- [ ] **Step 3: Usuń stary plik `BrowserCachesTask.swift`**

```bash
rm Sources/AutoCleanMacCore/Tasks/BrowserCachesTask.swift
```

- [ ] **Step 4: Uruchom wszystkie testy**

Run: `swift test`
Expected: wszystkie PASS. Jeśli istnieją testy jednostkowe dla `BrowserCachesTask`, usuń je — plik został usunięty.

Run: `swift build`
Expected: `Build complete!`, brak odwołań do `BrowserCachesTask`.

- [ ] **Step 5: Usuń `config.tasks.browserCaches` jeśli nieużywane nigdzie indziej**

Run: `grep -rn "browserCaches" Sources/ Tests/`
Jeśli wynik wskazuje tylko na `Config.swift` (pole + parser + default), usuń je:

(a) W `Config.swift`, z `struct Tasks` usuń pole `public var browserCaches: Bool` (zachowaj resztę).
(b) Usuń z `Tasks.default` parametr `browserCaches: true`.
(c) Z `loadOrDefault` usuń blok `if let v = t["browser_caches"] as? Bool { config.tasks.browserCaches = v }` — legacy parsowanie przenieś logicznie do Task 6 (tam już jest).
(d) Istniejący klucz JSON `browser_caches: true` **nadal działa** — jest obsłużony w Task 6.

Sprawdź testy — jeśli któryś referował `config.tasks.browserCaches`, usuń referencję.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(core): replace BrowserCachesTask with BrowserDataTask matrix

CleanupEngine.makeDefault now enumerates all enabled (browser × dataType)
pairs from config.browsers. The old fixed BrowserCachesTask is removed;
its legacy key tasks.browser_caches: true continues to work via the
Config migration path added in the previous commit."
```

---

## Task 8: `ConfigWriter` — atomowy zapis `Config` do JSON

**Dlaczego:** Settings UI musi móc zapisać zmiany użytkownika z powrotem do `~/.config/autoclean-mac/config.json`. Zapis atomowy (`Data.write(to:options:.atomic)`) żeby nie zostawiać pustego/uszkodzonego pliku przy przerwaniu.

**Files:**
- Create: `Sources/AutoCleanMacCore/ConfigWriter.swift`
- Test: `Tests/AutoCleanMacCoreTests/ConfigWriterTests.swift`

---

- [ ] **Step 1: Napisz failing test**

Zapisz `Tests/AutoCleanMacCoreTests/ConfigWriterTests.swift`:

```swift
import XCTest
@testable import AutoCleanMacCore

final class ConfigWriterTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_round_trip_preserves_delete_mode_retention_and_browsers() throws {
        var cfg = Config.default
        cfg.retentionDays = 14
        cfg.deleteMode = .live
        cfg.browsers = [
            .chrome:  BrowserPreferences(types: [.cache, .cookies]),
            .firefox: BrowserPreferences(types: [.history]),
        ]
        cfg.tasks.downloads = true

        let file = tempDir.appendingPathComponent("out.json")
        try ConfigWriter.write(cfg, to: file)

        let reloaded = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(reloaded.retentionDays, 14)
        XCTAssertEqual(reloaded.deleteMode, .live)
        XCTAssertTrue(reloaded.tasks.downloads)
        XCTAssertEqual(reloaded.browsers[.chrome]?.types,  [.cache, .cookies])
        XCTAssertEqual(reloaded.browsers[.firefox]?.types, [.history])
        XCTAssertNil(reloaded.browsers[.edge])
    }

    func test_write_is_atomic_creates_parent_dirs() throws {
        let nested = tempDir.appendingPathComponent("a/b/c/config.json")
        try ConfigWriter.write(Config.default, to: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }
}
```

- [ ] **Step 2: Uruchom — oczekiwane FAIL**

Run: `swift test --filter ConfigWriterTests`
Expected: "cannot find 'ConfigWriter' in scope".

- [ ] **Step 3: Zaimplementuj `ConfigWriter`**

Zapisz `Sources/AutoCleanMacCore/ConfigWriter.swift`:

```swift
import Foundation

public enum ConfigWriter {
    /// Serializuje `Config` do pretty-printed JSON i zapisuje atomowo do `url`.
    /// Tworzy brakujące katalogi nadrzędne.
    public static func write(_ config: Config, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        var tasks: [String: Any] = [
            "user_caches":    config.tasks.userCaches,
            "system_temp":    config.tasks.systemTemp,
            "trash":          config.tasks.trash,
            "ds_store":       config.tasks.dsStore,
            "user_logs":      config.tasks.userLogs,
            "dev_caches":     config.tasks.devCaches,
            "downloads":      config.tasks.downloads,
        ]
        // Legacy: zapisujemy też browser_caches=false aby stare narzędzia się nie myliły.
        tasks["browser_caches"] = false

        var browsers: [String: Any] = [:]
        for (browser, prefs) in config.browsers {
            var entry: [String: Any] = [:]
            for type in BrowserDataType.allCases {
                entry[type.rawValue] = prefs.contains(type)
            }
            browsers[browser.rawValue] = entry
        }

        let root: [String: Any] = [
            "retention_days": config.retentionDays,
            "delete_mode":    config.deleteMode.rawValue == "dryRun" ? "dry_run" : config.deleteMode.rawValue,
            "window": [
                "fade_in_ms":    config.window.fadeInMs,
                "hold_after_ms": config.window.holdAfterMs,
                "fade_out_ms":   config.window.fadeOutMs,
            ],
            "tasks":    tasks,
            "browsers": browsers,
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
```

Uwaga: `delete_mode` dla `.dryRun` musi zapisać się jako `"dry_run"` (snake_case), a nie rawValue `"dryRun"`. Jeden warunek inline wystarczy.

- [ ] **Step 4: Uruchom testy**

Run: `swift test --filter ConfigWriterTests`
Expected: 2 PASS.

Run: `swift test` (pełny)
Expected: brak regresji.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/ConfigWriter.swift Tests/AutoCleanMacCoreTests/ConfigWriterTests.swift
git commit -m "feat(core): add ConfigWriter for atomic JSON persistence

Round-trips retention_days, delete_mode (with correct snake_case for
dry_run), window timings, per-task toggles, and the new browsers dict.
Uses .atomic write option and creates intermediate directories.
Consumed by SettingsView Apply button in the next commit."
```

---

## Task 9: `SettingsView` + scene `Settings` + menu "Preferencje…"

**Dlaczego:** Wreszcie widoczne dla użytkownika. SwiftUI `Settings { }` scene to idiomatyczny sposób na okno preferencji na macOS — dostaje skrót `⌘,` za darmo i jest zarządzane przez system.

**Files:**
- Create: `Sources/AutoCleanMac/SettingsView.swift`
- Modify: `Sources/AutoCleanMac/AppDelegate.swift`
- Modify: `Sources/AutoCleanMac/MenuBarController.swift`

**Brak testów automatycznych** — UI testowane manualnie w Tasku 10. Kompilacja + build to gate tutaj.

---

- [ ] **Step 1: Stwórz `SettingsView.swift`**

Zapisz `Sources/AutoCleanMac/SettingsView.swift`:

```swift
import SwiftUI
import AutoCleanMacCore

/// Observable model trzymający edytowalne preferencje. Zapisywany przez Apply.
final class SettingsModel: ObservableObject {
    @Published var browsers: [BrowserIdentity: BrowserPreferences]

    let onApply: (Config) -> Void
    private let baseConfig: Config

    init(initial: Config, onApply: @escaping (Config) -> Void) {
        self.baseConfig = initial
        self.browsers = initial.browsers
        self.onApply = onApply
    }

    func toggle(_ browser: BrowserIdentity, _ type: BrowserDataType, _ enabled: Bool) {
        var prefs = browsers[browser, default: .none]
        prefs.set(type, enabled)
        browsers[browser] = prefs
    }

    func isOn(_ browser: BrowserIdentity, _ type: BrowserDataType) -> Bool {
        browsers[browser, default: .none].contains(type)
    }

    func apply() {
        var updated = baseConfig
        updated.browsers = browsers
        onApply(updated)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            BrowsersTab(model: model)
                .tabItem { Label("Przeglądarki", systemImage: "globe") }
        }
        .frame(width: 520, height: 420)
        .padding()
    }
}

private struct BrowsersTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wybierz co wyczyścić w każdej przeglądarce:")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("").frame(minWidth: 140, alignment: .leading)
                    ForEach(BrowserDataType.allCases, id: \.self) { type in
                        Text(type.displayName).bold().frame(minWidth: 90, alignment: .center)
                    }
                }
                Divider()
                ForEach(BrowserIdentity.allCases, id: \.self) { browser in
                    GridRow {
                        Text(browser.displayName)
                            .frame(minWidth: 140, alignment: .leading)
                        ForEach(BrowserDataType.allCases, id: \.self) { type in
                            Toggle("", isOn: Binding(
                                get: { model.isOn(browser, type) },
                                set: { model.toggle(browser, type, $0) }
                            ))
                            .labelsHidden()
                            .frame(minWidth: 90, alignment: .center)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("Ciasteczka = wylogowanie z serwisów.", systemImage: "info.circle")
                Label("Historia dla Firefoxa czyści tylko autofill i historię pobrań — zakładki bezpieczne (są w tej samej bazie co historia przeglądania, której nie tykamy).", systemImage: "exclamationmark.triangle")
                Label("Pomijamy przeglądarki które są uruchomione — zamknij je przed sprzątaniem.", systemImage: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Zapisz") { model.apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
```

- [ ] **Step 2: Zaktualizuj `MenuBarController`**

W `Sources/AutoCleanMac/MenuBarController.swift` dodaj obsługę nowego callbacku. Najpierw `var onOpenSettings: (() -> Void)?` obok innych, potem w `install()`:

Dodaj w `install()` **przed** separatorem końcowym (zaraz po "Otwórz folder logów"):

```swift
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferencje…",                action: #selector(openSettings), keyEquivalent: ",").target = self
```

I dodaj na końcu klasy:

```swift
    @objc private func openSettings() { onOpenSettings?() }
```

- [ ] **Step 3: Wire up w `AppDelegate`**

W `Sources/AutoCleanMac/AppDelegate.swift`:

(a) Dodaj na górze imporcie SwiftUI jeśli brak:

```swift
import SwiftUI
```

(b) Dodaj nowe pole klasy (obok innych `private var …`):

```swift
    private var settingsWindow: NSWindow?
```

(c) W `applicationDidFinishLaunching`, gdzie podpinane są callbacki menu, dodaj:

```swift
        menu.onOpenSettings   = { [weak self] in self?.openSettings() }
```

(d) Dodaj nową metodę (gdziekolwiek w klasie):

```swift
    private func openSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = SettingsModel(initial: config) { [weak self] updated in
            guard let self else { return }
            do {
                try ConfigWriter.write(updated, to: self.configPath)
                self.config = updated
                self.logger.log(event: "config_saved", fields: ["source": "settings"])
                self.settingsWindow?.close()
            } catch {
                self.logger.log(event: "config_save_failed", fields: ["error": "\(error)"])
            }
        }
        let host = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: host)
        win.title = "AutoCleanMac — Preferencje"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 4: Zbuduj**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!`. Warnings dot. `Sendable` na istniejącym `AppDelegate.swift` są OK (pre-existing).

- [ ] **Step 5: Pełne testy**

Run: `swift test 2>&1 | tail -3`
Expected: wszystkie dotychczasowe testy core pass. UI nieporuszone.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(app): add Preferences window with browsers section

New SwiftUI Settings window hosted via NSHostingController, opened from
menu bar 'Preferencje…' (⌘,). Grid of BrowserIdentity × BrowserDataType
toggles; Apply persists via ConfigWriter.write and refreshes the
in-memory config so the next cleanup run picks up the changes without
restarting. Footer surfaces the Firefox-places.sqlite and
running-browser caveats in plain language."
```

---

## Task 10: Integration smoke — build bundle + install + weryfikacja Preferencji

**Dlaczego:** Końcowy sanity check — aplikacja faktycznie otwiera okno Preferencji i zapisuje zmiany.

**Files:** brak zmian w kodzie.

---

- [ ] **Step 1: Rebuild + install**

```bash
cd /Users/micz/__DEV__/__auto_clean_mac
./scripts/install.sh 2>&1 | tail -15
```
Expected: "✓ AutoCleanMac zainstalowany." Wylistowane ścieżki.

- [ ] **Step 2: Uruchom aplikację ręcznie**

```bash
open ~/Applications/AutoCleanMac.app
```

Weryfikuj manualnie:
1. Ikona 🧹 w pasku menu się pojawia.
2. Kliknij ikonę → menu: "Uruchom teraz / Pokaż ostatnie sprzątanie / Otwórz konfigurację / Otwórz folder logów / Preferencje… / Zakończ".
3. Kliknij "Preferencje…" — otwiera się okno "AutoCleanMac — Preferencje".
4. Widać zakładkę "Przeglądarki" z gridem 6 przeglądarek × 3 typy + 3 stopki.
5. Zaznacz np. "Google Chrome — Cache", kliknij "Zapisz".
6. Sprawdź: `cat ~/.config/autoclean-mac/config.json | python3 -m json.tool` — widać sekcję `"browsers": { "chrome": { "cache": true, ... } }`.
7. ⌘Q żeby zamknąć okno; ikona w menu barze zostaje.

- [ ] **Step 3: Uruchom cleanup ręcznie**

W menu barze → "Uruchom teraz". W oknie konsoli powinno pojawić się zadanie "Google Chrome — Cache …" obok innych tasków. Jeśli Chrome działa — zadanie powinno mieć oznaczenie "pominięte (browser running)".

- [ ] **Step 4: Commit (docs)**

```bash
git add -A
git commit --allow-empty -m "chore: verify Settings window integration smoke manually

Manually exercised: menu item opens window, toggle Chrome Cache, save,
confirm JSON on disk, trigger cleanup, observe new per-browser task."
```

(`--allow-empty` bo to tylko zapis w historii commitów że smoke przeszedł — nie zmieniamy plików).

---

## Self-review

- [x] **Spec coverage:** User chciał "czyszczenie cache, ciastek, historii wybranych przeglądarek" — pokryte w Task 3-5. "Dodać do preferencji" — Task 9. Per-browser selection — Task 6 (`browsers` dict). Migracja — Task 6. Bezpieczeństwo places.sqlite — Task 5 jawnie.
- [x] **Placeholder scan:** żadnych "TBD"/"implement later"/"handle edge cases". Każdy krok ma konkretny kod.
- [x] **Type consistency:** `BrowserIdentity` (core) ↔ rawValue w JSON (`"chrome"`, `"firefox"`). `BrowserDataType` (core) ↔ klucze JSON (`"cache"`, `"cookies"`, `"history"`). `BrowserPreferences.types: Set<BrowserDataType>` używane wszędzie tak samo. `BrowserDataTask(browser:dataType:isEnabled:)` — init public, drugi z inject `isBrowserRunning` dla testów.

---

## Poza zakresem (osobne plany w przyszłości)

- Safari cleanup — wymaga TCC Full Disk Access + specjalna obsługa `~/Library/Safari/`.
- Firefox history pełne — parsowanie `places.sqlite`, SQL DELETE z `moz_places` poza zakładkami (wymaga lib SQLite).
- Dodatkowe sekcje Preferencji: retention slider, task toggles (`user_caches` itd.), delete_mode radio, window timings. Obecny config w JSON nadal działa — dopchnę w następnej fali.
- Podgląd "co zostanie usunięte" (dry-run z poziomu UI) — osobna funkcjonalność.
- Powiadomienie systemowe po zakończeniu — osobny task.
- Ikona SF Symbols zamiast emoji — osobny task.

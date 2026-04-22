# AutoCleanMac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI utility that runs at login, displays a small "cute console" window with live progress, safely removes unneeded cache/log/temp files under an explicit allow-list, and stays resident in the menu bar for manual triggering.

**Architecture:** Swift Package Manager executable with two targets (library + app). Entry point is `AppDelegate` (AppKit), SwiftUI hosts the console view inside a floating `NSPanel`. Cleanup is modeled as a `CleanupTask` protocol; each task declares an allowed root and is executed through a `SafeDeleter` that enforces realpath-containment. Config is JSON, logs are per-day plain text. Installation compiles the SwiftPM binary, assembles a `.app` bundle, codesigns ad-hoc, and registers a user LaunchAgent.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (`NSStatusItem`, `NSPanel`), Swift Package Manager, XCTest, `launchctl`, `codesign --sign -`.

**Spec:** [docs/superpowers/specs/2026-04-22-autocleanmac-design.md](../specs/2026-04-22-autocleanmac-design.md)

**Repo root:** `/Users/micz/__DEV__/__auto_clean_mac`

---

## File Structure

```
__auto_clean_mac/
├── Package.swift
├── Sources/
│   ├── AutoCleanMacCore/                 ← library target (testable)
│   │   ├── Logger.swift
│   │   ├── Config.swift
│   │   ├── SafeDeleter.swift
│   │   ├── CleanupTask.swift             ← protocol + TaskResult + CleanupContext
│   │   ├── CleanupEngine.swift
│   │   └── Tasks/
│   │       ├── TrashTask.swift
│   │       ├── DSStoreTask.swift
│   │       ├── UserLogsTask.swift
│   │       ├── SystemTempTask.swift
│   │       ├── UserCachesTask.swift
│   │       ├── BrowserCachesTask.swift
│   │       ├── DevCachesTask.swift
│   │       └── DownloadsTask.swift
│   └── AutoCleanMac/                     ← executable target (UI)
│       ├── main.swift
│       ├── AppDelegate.swift
│       ├── MenuBarController.swift
│       ├── ConsoleWindow.swift
│       └── ConsoleView.swift
├── Tests/
│   └── AutoCleanMacCoreTests/
│       ├── Fixtures.swift
│       ├── LoggerTests.swift
│       ├── ConfigTests.swift
│       ├── SafeDeleterTests.swift
│       ├── CleanupEngineTests.swift
│       └── TasksTests.swift
├── scripts/
│   ├── build-app-bundle.sh
│   ├── install.sh
│   └── uninstall.sh
├── resources/
│   └── com.micz.autocleanmac.plist.template
└── docs/
    └── superpowers/…
```

**Responsibilities:**
- `AutoCleanMacCore`: pure, testable logic — no AppKit/SwiftUI imports. All file operations go through `SafeDeleter`.
- `AutoCleanMac`: GUI only — AppKit + SwiftUI. Subscribes to engine events, renders console, owns menu bar.
- Separation means tests never need a display and never touch UI types.

---

## Task 1: Scaffold Swift package

**Files:**
- Create: `Package.swift`
- Create: `Sources/AutoCleanMacCore/Placeholder.swift`
- Create: `Sources/AutoCleanMac/main.swift`
- Create: `Tests/AutoCleanMacCoreTests/SmokeTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoCleanMac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "AutoCleanMacCore",
            path: "Sources/AutoCleanMacCore"
        ),
        .executableTarget(
            name: "AutoCleanMac",
            dependencies: ["AutoCleanMacCore"],
            path: "Sources/AutoCleanMac"
        ),
        .testTarget(
            name: "AutoCleanMacCoreTests",
            dependencies: ["AutoCleanMacCore"],
            path: "Tests/AutoCleanMacCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create placeholder source files**

`Sources/AutoCleanMacCore/Placeholder.swift`:
```swift
// Placeholder — will be removed once real sources are added.
public enum AutoCleanMacCore {
    public static let version = "0.1.0"
}
```

`Sources/AutoCleanMac/main.swift`:
```swift
import AutoCleanMacCore

print("AutoCleanMac \(AutoCleanMacCore.version) — scaffold build")
```

- [ ] **Step 3: Create smoke test**

`Tests/AutoCleanMacCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import AutoCleanMacCore

final class SmokeTests: XCTestCase {
    func test_version_is_defined() {
        XCTAssertFalse(AutoCleanMacCore.version.isEmpty)
    }
}
```

- [ ] **Step 4: Create `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj
DerivedData/
*.dSYM/
.DS_Store
```

- [ ] **Step 5: Initialize git, verify build + test**

```bash
cd /Users/micz/__DEV__/__auto_clean_mac
git init -b main
swift build
swift test
```

Expected: build succeeds, 1 test passes, `scaffold build` output from binary is **not** shown (only `swift run` would print it).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests .gitignore docs
git commit -m "chore: scaffold Swift package with core library and executable"
```

---

## Task 2: Logger

**Files:**
- Create: `Sources/AutoCleanMacCore/Logger.swift`
- Create: `Tests/AutoCleanMacCoreTests/LoggerTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/AutoCleanMacCoreTests/LoggerTests.swift`:
```swift
import XCTest
@testable import AutoCleanMacCore

final class LoggerTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AutoCleanMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_creates_log_directory_if_missing() throws {
        let logDir = tempDir.appendingPathComponent("logs")
        let logger = try Logger(directory: logDir, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        logger.log(event: "start", fields: ["source": "test"])
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: logDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func test_writes_line_with_iso_timestamp_and_event() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let logger = try Logger(directory: tempDir, clock: { fixedDate })
        logger.log(event: "start", fields: ["source": "login"])
        let file = tempDir.appendingPathComponent("2023-11-14.log")
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains("2023-11-14T22:13:20Z"))
        XCTAssertTrue(contents.contains("start"))
        XCTAssertTrue(contents.contains("source=login"))
    }

    func test_appends_multiple_lines() throws {
        let logger = try Logger(directory: tempDir, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        logger.log(event: "a", fields: [:])
        logger.log(event: "b", fields: [:])
        let file = tempDir.appendingPathComponent("2023-11-14.log")
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter LoggerTests
```
Expected: FAIL — `Logger` type not defined.

- [ ] **Step 3: Implement `Logger`**

`Sources/AutoCleanMacCore/Logger.swift`:
```swift
import Foundation

public final class Logger {
    private let directory: URL
    private let clock: () -> Date
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter
    private let queue = DispatchQueue(label: "autocleanmac.logger")

    public init(directory: URL, clock: @escaping () -> Date = Date.init) throws {
        self.directory = directory
        self.clock = clock
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.timeZone = TimeZone(identifier: "UTC")
        self.dayFormatter = DateFormatter()
        self.dayFormatter.timeZone = TimeZone(identifier: "UTC")
        self.dayFormatter.dateFormat = "yyyy-MM-dd"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func log(event: String, fields: [String: String] = [:]) {
        let now = clock()
        let timestamp = isoFormatter.string(from: now)
        let day = dayFormatter.string(from: now)
        let fieldsString = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "\(timestamp)\t\(event)\t\(fieldsString)\n"
        let file = directory.appendingPathComponent("\(day).log")
        queue.sync {
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter LoggerTests
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Logger.swift Tests/AutoCleanMacCoreTests/LoggerTests.swift
git commit -m "feat(core): add Logger with per-day append-only files"
```

---

## Task 3: Config

**Files:**
- Create: `Sources/AutoCleanMacCore/Config.swift`
- Create: `Tests/AutoCleanMacCoreTests/ConfigTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/AutoCleanMacCoreTests/ConfigTests.swift`:
```swift
import XCTest
@testable import AutoCleanMacCore

final class ConfigTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AutoCleanMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_default_when_file_missing() {
        let missing = tempDir.appendingPathComponent("nope.json")
        let config = Config.loadOrDefault(from: missing, warn: { _ in })
        XCTAssertEqual(config.retentionDays, 7)
        XCTAssertTrue(config.tasks.userCaches)
        XCTAssertFalse(config.tasks.downloads)
        XCTAssertEqual(config.window.fadeInMs, 800)
    }

    func test_loads_custom_values() throws {
        let file = tempDir.appendingPathComponent("c.json")
        let json = """
        {
          "retention_days": 14,
          "window": { "fade_in_ms": 500, "hold_after_ms": 2000, "fade_out_ms": 500 },
          "tasks": { "downloads": true, "user_caches": false }
        }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(config.retentionDays, 14)
        XCTAssertEqual(config.window.fadeInMs, 500)
        XCTAssertTrue(config.tasks.downloads)
        XCTAssertFalse(config.tasks.userCaches)
        // Unspecified keys keep defaults:
        XCTAssertTrue(config.tasks.trash)
    }

    func test_malformed_json_falls_back_to_defaults_and_warns() throws {
        let file = tempDir.appendingPathComponent("bad.json")
        try "{ not valid json".write(to: file, atomically: true, encoding: .utf8)
        var warnings: [String] = []
        let config = Config.loadOrDefault(from: file, warn: { warnings.append($0) })
        XCTAssertEqual(config.retentionDays, 7)
        XCTAssertFalse(warnings.isEmpty)
    }

    func test_unknown_keys_are_ignored() throws {
        let file = tempDir.appendingPathComponent("unknown.json")
        let json = """
        { "retention_days": 3, "future_feature": "abc" }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(config.retentionDays, 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ConfigTests
```
Expected: FAIL — `Config` not defined.

- [ ] **Step 3: Implement `Config`**

`Sources/AutoCleanMacCore/Config.swift`:
```swift
import Foundation

public struct Config: Equatable {
    public struct Window: Equatable {
        public var fadeInMs: Int
        public var holdAfterMs: Int
        public var fadeOutMs: Int

        public static let `default` = Window(fadeInMs: 800, holdAfterMs: 3000, fadeOutMs: 800)
    }

    public struct Tasks: Equatable {
        public var userCaches: Bool
        public var systemTemp: Bool
        public var trash: Bool
        public var dsStore: Bool
        public var userLogs: Bool
        public var browserCaches: Bool
        public var devCaches: Bool
        public var downloads: Bool

        public static let `default` = Tasks(
            userCaches: true, systemTemp: true, trash: true, dsStore: true,
            userLogs: true, browserCaches: true, devCaches: true, downloads: false
        )
    }

    public var retentionDays: Int
    public var window: Window
    public var tasks: Tasks

    public static let `default` = Config(
        retentionDays: 7, window: .default, tasks: .default
    )

    public static func loadOrDefault(from url: URL, warn: (String) -> Void) -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }
        guard let data = try? Data(contentsOf: url) else {
            warn("Nie udało się odczytać configu: \(url.path)")
            return .default
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            warn("Malformed config JSON, używam wartości domyślnych")
            return .default
        }
        var config = Config.default
        if let n = json["retention_days"] as? Int { config.retentionDays = n }
        if let w = json["window"] as? [String: Any] {
            if let v = w["fade_in_ms"]    as? Int { config.window.fadeInMs    = v }
            if let v = w["hold_after_ms"] as? Int { config.window.holdAfterMs = v }
            if let v = w["fade_out_ms"]   as? Int { config.window.fadeOutMs   = v }
        }
        if let t = json["tasks"] as? [String: Any] {
            if let v = t["user_caches"]    as? Bool { config.tasks.userCaches    = v }
            if let v = t["system_temp"]    as? Bool { config.tasks.systemTemp    = v }
            if let v = t["trash"]          as? Bool { config.tasks.trash         = v }
            if let v = t["ds_store"]       as? Bool { config.tasks.dsStore       = v }
            if let v = t["user_logs"]      as? Bool { config.tasks.userLogs      = v }
            if let v = t["browser_caches"] as? Bool { config.tasks.browserCaches = v }
            if let v = t["dev_caches"]     as? Bool { config.tasks.devCaches     = v }
            if let v = t["downloads"]      as? Bool { config.tasks.downloads     = v }
        }
        return config
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter ConfigTests
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Config.swift Tests/AutoCleanMacCoreTests/ConfigTests.swift
git commit -m "feat(core): add Config with JSON load and default fallback"
```

---

## Task 4: SafeDeleter

This is the critical safety primitive. Every deletion in the app goes through it.

**Files:**
- Create: `Sources/AutoCleanMacCore/SafeDeleter.swift`
- Create: `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`
- Modify: `Tests/AutoCleanMacCoreTests/Fixtures.swift` (new helper)

- [ ] **Step 1: Create test fixtures helper**

`Tests/AutoCleanMacCoreTests/Fixtures.swift`:
```swift
import Foundation
import XCTest

enum Fixtures {
    static func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AutoCleanMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Creates a regular file at `url` with `size` bytes of 'x'. Sets mtime to `ageInDays` ago.
    static func makeFile(at url: URL, size: Int = 16, ageInDays: Int = 0) throws {
        let bytes = Data(repeating: 0x78, count: size)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        let mtime = Date().addingTimeInterval(TimeInterval(-ageInDays * 86_400))
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    /// Creates a symlink at `linkAt` pointing to `target`.
    static func makeSymlink(at linkAt: URL, pointingTo target: URL) throws {
        try FileManager.default.createDirectory(at: linkAt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkAt, withDestinationURL: target)
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`:
```swift
import XCTest
@testable import AutoCleanMacCore

final class SafeDeleterTests: XCTestCase {
    var tempDir: URL!
    var logDir: URL!
    var logger: Logger!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logDir = tempDir.appendingPathComponent("logs")
        logger = try Logger(directory: logDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_delete_file_within_root_removes_and_returns_size() throws {
        let root = tempDir.appendingPathComponent("root")
        let file = root.appendingPathComponent("a.txt")
        try Fixtures.makeFile(at: file, size: 100)
        let deleter = SafeDeleter(mode: .live, logger: logger)
        let freed = try deleter.delete(file, withinRoot: root)
        XCTAssertEqual(freed, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_delete_rejects_path_outside_root() throws {
        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = tempDir.appendingPathComponent("other/file.txt")
        try Fixtures.makeFile(at: outside)
        let deleter = SafeDeleter(mode: .live, logger: logger)
        XCTAssertThrowsError(try deleter.delete(outside, withinRoot: root)) { error in
            guard case SafeDeleter.DeletionError.outsideAllowedRoot = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_delete_rejects_symlink_escaping_root() throws {
        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = tempDir.appendingPathComponent("secret.txt")
        try Fixtures.makeFile(at: outside)
        let link = root.appendingPathComponent("trap")
        try Fixtures.makeSymlink(at: link, pointingTo: outside)
        let deleter = SafeDeleter(mode: .live, logger: logger)
        XCTAssertThrowsError(try deleter.delete(link, withinRoot: root)) { error in
            guard case SafeDeleter.DeletionError.outsideAllowedRoot = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_dry_run_does_not_delete_but_returns_size() throws {
        let root = tempDir.appendingPathComponent("root")
        let file = root.appendingPathComponent("a.txt")
        try Fixtures.makeFile(at: file, size: 42)
        let deleter = SafeDeleter(mode: .dryRun, logger: logger)
        let freed = try deleter.delete(file, withinRoot: root)
        XCTAssertEqual(freed, 42)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_delete_nonexistent_file_throws() throws {
        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("gone.txt")
        let deleter = SafeDeleter(mode: .live, logger: logger)
        XCTAssertThrowsError(try deleter.delete(file, withinRoot: root))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
swift test --filter SafeDeleterTests
```
Expected: FAIL — `SafeDeleter` not defined.

- [ ] **Step 4: Implement `SafeDeleter`**

`Sources/AutoCleanMacCore/SafeDeleter.swift`:
```swift
import Foundation

public final class SafeDeleter {
    public enum Mode { case live, dryRun }

    public enum DeletionError: Error, CustomStringConvertible {
        case outsideAllowedRoot(path: String, root: String)
        case notFound(path: String)

        public var description: String {
            switch self {
            case .outsideAllowedRoot(let p, let r): return "Path \(p) escapes root \(r)"
            case .notFound(let p):                  return "Not found: \(p)"
            }
        }
    }

    private let mode: Mode
    private let logger: Logger

    public init(mode: Mode, logger: Logger) {
        self.mode = mode
        self.logger = logger
    }

    @discardableResult
    public func delete(_ path: URL, withinRoot: URL) throws -> Int64 {
        let resolvedPath = path.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = withinRoot.resolvingSymlinksInPath().standardizedFileURL

        let rootStr = resolvedRoot.path
        let pathStr = resolvedPath.path
        let rootWithSep = rootStr.hasSuffix("/") ? rootStr : rootStr + "/"

        guard pathStr == rootStr || pathStr.hasPrefix(rootWithSep) else {
            throw DeletionError.outsideAllowedRoot(path: pathStr, root: rootStr)
        }

        // Use lstat-style attributes so symlinks themselves can be sized/removed.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path) else {
            throw DeletionError.notFound(path: path.path)
        }
        let size = (attrs[.size] as? Int64) ?? 0

        let event = mode == .dryRun ? "dryrun" : "delete"
        logger.log(event: event, fields: ["path": path.path, "size": "\(size)"])

        if mode == .live {
            try FileManager.default.removeItem(at: path)
        }
        return size
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter SafeDeleterTests
```
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/SafeDeleter.swift Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift Tests/AutoCleanMacCoreTests/Fixtures.swift
git commit -m "feat(core): add SafeDeleter with realpath containment and dry-run mode"
```

---

## Task 5: CleanupTask protocol and supporting types

**Files:**
- Create: `Sources/AutoCleanMacCore/CleanupTask.swift`
- Delete: `Sources/AutoCleanMacCore/Placeholder.swift`

- [ ] **Step 1: Create the protocol and types**

`Sources/AutoCleanMacCore/CleanupTask.swift`:
```swift
import Foundation

public struct TaskResult: Equatable {
    public var bytesFreed: Int64
    public var warnings: [String]
    public var skipped: Bool
    public var skipReason: String?

    public init(bytesFreed: Int64 = 0, warnings: [String] = [], skipped: Bool = false, skipReason: String? = nil) {
        self.bytesFreed = bytesFreed
        self.warnings = warnings
        self.skipped = skipped
        self.skipReason = skipReason
    }
}

public struct CleanupContext {
    public let retentionDays: Int
    public let deleter: SafeDeleter
    public let logger: Logger
    public let fileManager: FileManager
    public let homeDirectory: URL

    public init(
        retentionDays: Int,
        deleter: SafeDeleter,
        logger: Logger,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.retentionDays = retentionDays
        self.deleter = deleter
        self.logger = logger
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }
}

public protocol CleanupTask {
    var displayName: String { get }
    var isEnabled: Bool { get }
    func run(context: CleanupContext) async -> TaskResult
}

/// Shared helper: enumerate regular files + symlinks under `root`, applying an optional mtime filter.
public struct FileEnumerator {
    public static func files(
        inRoot root: URL,
        olderThanDays days: Int? = nil,
        namedExactly exactName: String? = nil,
        fileManager: FileManager = .default,
        clock: () -> Date = Date.init
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else { return [] }
        let now = clock()
        let cutoff = days.map { now.addingTimeInterval(TimeInterval(-$0 * 86_400)) }
        var out: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            let isFile = (values?.isRegularFile ?? false) || (values?.isSymbolicLink ?? false)
            guard isFile else { continue }
            if let name = exactName, url.lastPathComponent != name { continue }
            if let cutoff, let mtime = values?.contentModificationDate, mtime > cutoff { continue }
            out.append(url)
        }
        return out
    }
}
```

- [ ] **Step 2: Remove the placeholder file and update references**

```bash
rm /Users/micz/__DEV__/__auto_clean_mac/Sources/AutoCleanMacCore/Placeholder.swift
```

Modify `Tests/AutoCleanMacCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import AutoCleanMacCore

final class SmokeTests: XCTestCase {
    func test_taskresult_defaults() {
        let r = TaskResult()
        XCTAssertEqual(r.bytesFreed, 0)
        XCTAssertTrue(r.warnings.isEmpty)
        XCTAssertFalse(r.skipped)
    }
}
```

- [ ] **Step 3: Build + run tests**

```bash
swift test
```
Expected: PASS (all existing tests + updated smoke test).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(core): add CleanupTask protocol, CleanupContext, TaskResult, FileEnumerator"
```

---

## Task 6: TrashTask

Each task follows the same pattern — TDD against fixtures, declared allowed root, mtime filter.

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/TrashTask.swift`
- Create: `Tests/AutoCleanMacCoreTests/TasksTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoCleanMacCoreTests/TasksTests.swift`:
```swift
import XCTest
@testable import AutoCleanMacCore

final class TasksTests: XCTestCase {
    var tempDir: URL!
    var logger: Logger!
    var deleter: SafeDeleter!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logger = try Logger(directory: tempDir.appendingPathComponent("logs"))
        deleter = SafeDeleter(mode: .live, logger: logger)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeContext(home: URL? = nil) -> CleanupContext {
        CleanupContext(
            retentionDays: 7,
            deleter: deleter,
            logger: logger,
            homeDirectory: home ?? tempDir
        )
    }

    // MARK: - TrashTask

    func test_trash_deletes_files_older_than_retention() async throws {
        let trash = tempDir.appendingPathComponent(".Trash")
        try Fixtures.makeFile(at: trash.appendingPathComponent("old.txt"), size: 100, ageInDays: 30)
        try Fixtures.makeFile(at: trash.appendingPathComponent("fresh.txt"), size: 100, ageInDays: 1)
        let task = TrashTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.appendingPathComponent("old.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent("fresh.txt").path))
    }

    func test_trash_skipped_when_disabled() async throws {
        let task = TrashTask(isEnabled: false)
        let result = await task.run(context: makeContext())
        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.bytesFreed, 0)
    }

    func test_trash_skipped_when_root_missing() async throws {
        let task = TrashTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertTrue(result.skipped)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_trash
```
Expected: FAIL — `TrashTask` not defined.

- [ ] **Step 3: Implement `TrashTask`**

`Sources/AutoCleanMacCore/Tasks/TrashTask.swift`:
```swift
import Foundation

public struct TrashTask: CleanupTask {
    public let displayName = "Trash (>retention)"
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent(".Trash")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        let candidates = FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays)
        var freed: Int64 = 0
        var warnings: [String] = []
        for url in candidates {
            do {
                freed += try context.deleter.delete(url, withinRoot: root)
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
swift test --filter TasksTests/test_trash
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/TrashTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add TrashTask"
```

---

## Task 7: DSStoreTask

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/DSStoreTask.swift`
- Modify: `Tests/AutoCleanMacCoreTests/TasksTests.swift` (add test)

- [ ] **Step 1: Append failing test to `TasksTests.swift`**

Add before the final `}` of `TasksTests`:
```swift
    // MARK: - DSStoreTask

    func test_dsstore_deletes_only_dsstore_files() async throws {
        let desktop = tempDir.appendingPathComponent("Desktop")
        try Fixtures.makeFile(at: desktop.appendingPathComponent(".DS_Store"), size: 50)
        try Fixtures.makeFile(at: desktop.appendingPathComponent("important.txt"), size: 500)
        try Fixtures.makeFile(at: desktop.appendingPathComponent("sub/.DS_Store"), size: 70)
        let task = DSStoreTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 120)
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("important.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: desktop.appendingPathComponent(".DS_Store").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("sub/.DS_Store").path))
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_dsstore
```
Expected: FAIL — `DSStoreTask` not defined.

- [ ] **Step 3: Implement `DSStoreTask`**

`Sources/AutoCleanMacCore/Tasks/DSStoreTask.swift`:
```swift
import Foundation

public struct DSStoreTask: CleanupTask {
    public let displayName = ".DS_Store files"
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let roots = ["Desktop", "Documents", "Downloads"]
            .map { context.homeDirectory.appendingPathComponent($0) }
            .filter { context.fileManager.fileExists(atPath: $0.path) }
        guard !roots.isEmpty else {
            return TaskResult(skipped: true, skipReason: "no roots present")
        }
        var freed: Int64 = 0
        var warnings: [String] = []
        for root in roots {
            let files = FileEnumerator.files(inRoot: root, namedExactly: ".DS_Store")
            for url in files {
                do {
                    freed += try context.deleter.delete(url, withinRoot: root)
                } catch {
                    warnings.append("\(url.path): \(error)")
                }
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TasksTests/test_dsstore
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/DSStoreTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add DSStoreTask"
```

---

## Task 8: UserLogsTask

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/UserLogsTask.swift`
- Modify: `Tests/AutoCleanMacCoreTests/TasksTests.swift` (add test)

- [ ] **Step 1: Append failing test**

Add to `TasksTests`:
```swift
    // MARK: - UserLogsTask

    func test_user_logs_deletes_old_files_only() async throws {
        let logsRoot = tempDir.appendingPathComponent("Library/Logs")
        try Fixtures.makeFile(at: logsRoot.appendingPathComponent("old.log"),   size: 300, ageInDays: 30)
        try Fixtures.makeFile(at: logsRoot.appendingPathComponent("fresh.log"), size: 300, ageInDays: 1)
        let task = UserLogsTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 300)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logsRoot.appendingPathComponent("old.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsRoot.appendingPathComponent("fresh.log").path))
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_user_logs
```
Expected: FAIL.

- [ ] **Step 3: Implement `UserLogsTask`**

`Sources/AutoCleanMacCore/Tasks/UserLogsTask.swift`:
```swift
import Foundation

public struct UserLogsTask: CleanupTask {
    public let displayName = "User logs (>retention)"
    public let isEnabled: Bool

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent("Library/Logs")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        var freed: Int64 = 0
        var warnings: [String] = []
        for url in FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays) {
            do {
                freed += try context.deleter.delete(url, withinRoot: root)
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TasksTests/test_user_logs
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/UserLogsTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add UserLogsTask"
```

---

## Task 9: SystemTempTask

Operates on `$TMPDIR` (user-scoped on macOS). In tests we override via an injectable root.

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/SystemTempTask.swift`
- Modify: `Tests/AutoCleanMacCoreTests/TasksTests.swift`

- [ ] **Step 1: Append failing test**

```swift
    // MARK: - SystemTempTask

    func test_system_temp_deletes_old_files_only() async throws {
        let temp = tempDir.appendingPathComponent("temp-root")
        try Fixtures.makeFile(at: temp.appendingPathComponent("old.tmp"),   size: 80, ageInDays: 30)
        try Fixtures.makeFile(at: temp.appendingPathComponent("fresh.tmp"), size: 80, ageInDays: 1)
        let task = SystemTempTask(isEnabled: true, rootOverride: temp)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 80)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_system_temp
```
Expected: FAIL.

- [ ] **Step 3: Implement `SystemTempTask`**

`Sources/AutoCleanMacCore/Tasks/SystemTempTask.swift`:
```swift
import Foundation

public struct SystemTempTask: CleanupTask {
    public let displayName = "System temp (>retention)"
    public let isEnabled: Bool
    private let rootOverride: URL?

    public init(isEnabled: Bool, rootOverride: URL? = nil) {
        self.isEnabled = isEnabled
        self.rootOverride = rootOverride
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = rootOverride ?? URL(fileURLWithPath: NSTemporaryDirectory())
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        var freed: Int64 = 0
        var warnings: [String] = []
        for url in FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays) {
            do {
                freed += try context.deleter.delete(url, withinRoot: root)
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TasksTests/test_system_temp
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/SystemTempTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add SystemTempTask"
```

---

## Task 10: UserCachesTask

Deletes all regular files under `~/Library/Caches`. No mtime filter — caches regenerate.

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/UserCachesTask.swift`
- Modify: `Tests/AutoCleanMacCoreTests/TasksTests.swift`

- [ ] **Step 1: Append failing test**

```swift
    // MARK: - UserCachesTask

    func test_user_caches_deletes_all_files_regardless_of_mtime() async throws {
        let caches = tempDir.appendingPathComponent("Library/Caches")
        try Fixtures.makeFile(at: caches.appendingPathComponent("a/x.bin"),  size: 100, ageInDays: 0)
        try Fixtures.makeFile(at: caches.appendingPathComponent("b/y.bin"),  size: 200, ageInDays: 30)
        let task = UserCachesTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 300)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_user_caches
```
Expected: FAIL.

- [ ] **Step 3: Implement `UserCachesTask`**

`Sources/AutoCleanMacCore/Tasks/UserCachesTask.swift`:
```swift
import Foundation

public struct UserCachesTask: CleanupTask {
    public let displayName = "User caches"
    public let isEnabled: Bool

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent("Library/Caches")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        var freed: Int64 = 0
        var warnings: [String] = []
        for url in FileEnumerator.files(inRoot: root) {
            do {
                freed += try context.deleter.delete(url, withinRoot: root)
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TasksTests/test_user_caches
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/UserCachesTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add UserCachesTask"
```

---

## Task 11: BrowserCachesTask

Scans `~/Library/Application Support/Google/Chrome/*/Cache`, `.../Code Cache`, `~/Library/Application Support/Firefox/Profiles/*/cache2`. Deletes contents **only** of directories whose name matches the allow-list `["Cache", "Code Cache", "cache2"]` — never `Cookies`, `History`, etc.

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/BrowserCachesTask.swift`
- Modify: `Tests/AutoCleanMacCoreTests/TasksTests.swift`

- [ ] **Step 1: Append failing test**

```swift
    // MARK: - BrowserCachesTask

    func test_browser_caches_deletes_allowed_dirs_only() async throws {
        let chromeProfile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try Fixtures.makeFile(at: chromeProfile.appendingPathComponent("Cache/blob1"),     size: 100)
        try Fixtures.makeFile(at: chromeProfile.appendingPathComponent("Code Cache/js/x"), size: 50)
        try Fixtures.makeFile(at: chromeProfile.appendingPathComponent("Cookies"),         size: 999)
        try Fixtures.makeFile(at: chromeProfile.appendingPathComponent("History"),         size: 888)

        let ffProfile = tempDir.appendingPathComponent("Library/Application Support/Firefox/Profiles/abcd.default/cache2")
        try Fixtures.makeFile(at: ffProfile.appendingPathComponent("entry1"), size: 40)

        let task = BrowserCachesTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 190)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chromeProfile.appendingPathComponent("Cookies").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: chromeProfile.appendingPathComponent("History").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: chromeProfile.appendingPathComponent("Cache/blob1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ffProfile.appendingPathComponent("entry1").path))
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_browser_caches
```
Expected: FAIL.

- [ ] **Step 3: Implement `BrowserCachesTask`**

`Sources/AutoCleanMacCore/Tasks/BrowserCachesTask.swift`:
```swift
import Foundation

public struct BrowserCachesTask: CleanupTask {
    public let displayName = "Browser caches"
    public let isEnabled: Bool

    private static let allowedDirNames: Set<String> = ["Cache", "Code Cache", "cache2"]

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let appSupport = context.homeDirectory.appendingPathComponent("Library/Application Support")
        let roots: [URL] = [
            appSupport.appendingPathComponent("Google/Chrome"),
            appSupport.appendingPathComponent("Firefox/Profiles"),
        ].filter { context.fileManager.fileExists(atPath: $0.path) }
        guard !roots.isEmpty else {
            return TaskResult(skipped: true, skipReason: "no browser profile directories")
        }

        var freed: Int64 = 0
        var warnings: [String] = []

        for root in roots {
            // Find every directory whose name is in the allow-list, under `root`.
            let allowedDirs = findAllowedCacheDirs(under: root, fileManager: context.fileManager)
            for dir in allowedDirs {
                for url in FileEnumerator.files(inRoot: dir) {
                    do {
                        freed += try context.deleter.delete(url, withinRoot: dir)
                    } catch {
                        warnings.append("\(url.lastPathComponent): \(error)")
                    }
                }
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }

    private func findAllowedCacheDirs(under root: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        var dirs: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true, Self.allowedDirNames.contains(url.lastPathComponent) {
                dirs.append(url)
                enumerator.skipDescendants() // don't recurse into the cache itself here
            }
        }
        return dirs
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TasksTests/test_browser_caches
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/BrowserCachesTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add BrowserCachesTask with explicit allow-list"
```

---

## Task 12: DevCachesTask

Deletes Xcode DerivedData contents + npm/pip cache contents older than retention. Additionally runs `brew cleanup --prune=<days>` if `brew` is available. The shell-out is wrapped so tests can disable it.

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/DevCachesTask.swift`
- Modify: `Tests/AutoCleanMacCoreTests/TasksTests.swift`

- [ ] **Step 1: Append failing test**

```swift
    // MARK: - DevCachesTask

    func test_dev_caches_deletes_derived_data_and_npm_and_pip() async throws {
        let derived = tempDir.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        try Fixtures.makeFile(at: derived.appendingPathComponent("proj-abc/x"), size: 200, ageInDays: 30)
        try Fixtures.makeFile(at: derived.appendingPathComponent("proj-abc/y"), size: 50,  ageInDays: 1)

        let npm = tempDir.appendingPathComponent(".npm/_cacache")
        try Fixtures.makeFile(at: npm.appendingPathComponent("content-v2/abc"), size: 300, ageInDays: 30)

        let pip = tempDir.appendingPathComponent("Library/Caches/pip")
        try Fixtures.makeFile(at: pip.appendingPathComponent("wheels/a"), size: 150, ageInDays: 30)

        let task = DevCachesTask(isEnabled: true, runBrew: false)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 200 + 300 + 150)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_dev_caches
```
Expected: FAIL.

- [ ] **Step 3: Implement `DevCachesTask`**

`Sources/AutoCleanMacCore/Tasks/DevCachesTask.swift`:
```swift
import Foundation

public struct DevCachesTask: CleanupTask {
    public let displayName = "Dev caches"
    public let isEnabled: Bool
    private let runBrew: Bool

    public init(isEnabled: Bool, runBrew: Bool = true) {
        self.isEnabled = isEnabled
        self.runBrew = runBrew
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }

        let roots: [URL] = [
            context.homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            context.homeDirectory.appendingPathComponent(".npm/_cacache"),
            context.homeDirectory.appendingPathComponent("Library/Caches/pip"),
        ].filter { context.fileManager.fileExists(atPath: $0.path) }

        var freed: Int64 = 0
        var warnings: [String] = []

        for root in roots {
            for url in FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays) {
                do {
                    freed += try context.deleter.delete(url, withinRoot: root)
                } catch {
                    warnings.append("\(url.lastPathComponent): \(error)")
                }
            }
        }

        if runBrew, let brew = Self.findExecutable("brew") {
            let status = Self.shell(brew, args: ["cleanup", "--prune=\(context.retentionDays)"])
            if status != 0 {
                warnings.append("brew cleanup exited \(status)")
            }
        }

        return TaskResult(bytesFreed: freed, warnings: warnings)
    }

    private static func findExecutable(_ name: String) -> String? {
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let full = "\(path)/\(name)"
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    private static func shell(_ path: String, args: [String]) -> Int32 {
        let process = Process()
        process.launchPath = path
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TasksTests/test_dev_caches
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/DevCachesTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add DevCachesTask (DerivedData, npm, pip, optional brew cleanup)"
```

---

## Task 13: DownloadsTask

Default-off task that deletes files older than retention in `~/Downloads`, **skipping hidden files and directories**.

**Files:**
- Create: `Sources/AutoCleanMacCore/Tasks/DownloadsTask.swift`
- Modify: `Tests/AutoCleanMacCoreTests/TasksTests.swift`

- [ ] **Step 1: Append failing test**

```swift
    // MARK: - DownloadsTask

    func test_downloads_deletes_old_files_but_not_hidden_or_dirs() async throws {
        let dl = tempDir.appendingPathComponent("Downloads")
        try Fixtures.makeFile(at: dl.appendingPathComponent("old-installer.dmg"),  size: 500, ageInDays: 30)
        try Fixtures.makeFile(at: dl.appendingPathComponent("recent-notes.txt"),   size: 500, ageInDays: 1)
        try Fixtures.makeFile(at: dl.appendingPathComponent(".localized"),         size: 50,  ageInDays: 30)
        try Fixtures.makeFile(at: dl.appendingPathComponent("project/file.txt"),   size: 100, ageInDays: 30)
        let task = DownloadsTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 500)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dl.appendingPathComponent("recent-notes.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dl.appendingPathComponent(".localized").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dl.appendingPathComponent("project/file.txt").path))
    }

    func test_downloads_default_off() async throws {
        let task = DownloadsTask(isEnabled: false)
        let result = await task.run(context: makeContext())
        XCTAssertTrue(result.skipped)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TasksTests/test_downloads
```
Expected: FAIL.

- [ ] **Step 3: Implement `DownloadsTask`**

`Sources/AutoCleanMacCore/Tasks/DownloadsTask.swift`:
```swift
import Foundation

public struct DownloadsTask: CleanupTask {
    public let displayName = "Downloads (>retention, opt-in)"
    public let isEnabled: Bool

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent("Downloads")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }

        guard let entries = try? context.fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return TaskResult(skipped: true, skipReason: "unreadable")
        }

        let now = Date()
        let cutoff = now.addingTimeInterval(TimeInterval(-context.retentionDays * 86_400))
        var freed: Int64 = 0
        var warnings: [String] = []

        for url in entries {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard let mtime = values?.contentModificationDate, mtime <= cutoff else { continue }
            do {
                freed += try context.deleter.delete(url, withinRoot: root)
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TasksTests/test_downloads
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Tasks/DownloadsTask.swift Tests/AutoCleanMacCoreTests/TasksTests.swift
git commit -m "feat(core): add DownloadsTask (opt-in, top-level non-hidden files only)"
```

---

## Task 14: CleanupEngine

Orchestrates tasks, emits progress events to a delegate/callback.

**Files:**
- Create: `Sources/AutoCleanMacCore/CleanupEngine.swift`
- Create: `Tests/AutoCleanMacCoreTests/CleanupEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/AutoCleanMacCoreTests/CleanupEngineTests.swift`:
```swift
import XCTest
@testable import AutoCleanMacCore

final class CleanupEngineTests: XCTestCase {
    var tempDir: URL!
    var logger: Logger!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logger = try Logger(directory: tempDir.appendingPathComponent("logs"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    struct StubTask: CleanupTask {
        let displayName: String
        let isEnabled: Bool
        let result: TaskResult
        func run(context: CleanupContext) async -> TaskResult { result }
    }

    func test_engine_runs_all_tasks_in_order_and_sums_bytes() async throws {
        let ctx = CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .live, logger: logger),
            logger: logger,
            homeDirectory: tempDir
        )
        let engine = CleanupEngine(tasks: [
            StubTask(displayName: "A", isEnabled: true, result: TaskResult(bytesFreed: 100)),
            StubTask(displayName: "B", isEnabled: true, result: TaskResult(bytesFreed: 200, warnings: ["w"])),
            StubTask(displayName: "C", isEnabled: false, result: TaskResult()),
        ])

        var events: [CleanupEngine.Event] = []
        let summary = await engine.run(context: ctx) { events.append($0) }

        XCTAssertEqual(summary.bytesFreed, 300)
        XCTAssertEqual(summary.warningsCount, 1)
        let names = events.compactMap { event -> String? in
            if case .taskFinished(let name, _) = event { return name }
            return nil
        }
        XCTAssertEqual(names, ["A", "B", "C"])
        if case .summary(let s) = events.last { XCTAssertEqual(s.bytesFreed, 300) } else { XCTFail("no summary event") }
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter CleanupEngineTests
```
Expected: FAIL — `CleanupEngine` not defined.

- [ ] **Step 3: Implement `CleanupEngine`**

`Sources/AutoCleanMacCore/CleanupEngine.swift`:
```swift
import Foundation

public final class CleanupEngine {
    public struct Summary: Equatable {
        public var bytesFreed: Int64
        public var warningsCount: Int
        public var durationMs: Int
    }

    public enum Event {
        case started
        case taskStarted(name: String)
        case taskFinished(name: String, result: TaskResult)
        case summary(Summary)
    }

    private let tasks: [CleanupTask]

    public init(tasks: [CleanupTask]) {
        self.tasks = tasks
    }

    public func run(context: CleanupContext, onEvent: @escaping (Event) -> Void) async -> Summary {
        onEvent(.started)
        let start = Date()
        var totalBytes: Int64 = 0
        var totalWarnings = 0

        for task in tasks {
            onEvent(.taskStarted(name: task.displayName))
            let result = await task.run(context: context)
            onEvent(.taskFinished(name: task.displayName, result: result))
            totalBytes += result.bytesFreed
            totalWarnings += result.warnings.count
        }

        let duration = Int(Date().timeIntervalSince(start) * 1000)
        let summary = Summary(bytesFreed: totalBytes, warningsCount: totalWarnings, durationMs: duration)
        onEvent(.summary(summary))
        context.logger.log(event: "summary", fields: [
            "freed": "\(summary.bytesFreed)",
            "duration_ms": "\(summary.durationMs)",
            "warnings": "\(summary.warningsCount)",
        ])
        return summary
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter CleanupEngineTests
```
Expected: PASS.

- [ ] **Step 5: Add a factory to wire tasks from Config**

Append to `Sources/AutoCleanMacCore/CleanupEngine.swift`:
```swift
public extension CleanupEngine {
    static func makeDefault(config: Config) -> CleanupEngine {
        CleanupEngine(tasks: [
            UserCachesTask(isEnabled: config.tasks.userCaches),
            SystemTempTask(isEnabled: config.tasks.systemTemp),
            TrashTask(isEnabled: config.tasks.trash),
            DSStoreTask(isEnabled: config.tasks.dsStore),
            UserLogsTask(isEnabled: config.tasks.userLogs),
            BrowserCachesTask(isEnabled: config.tasks.browserCaches),
            DevCachesTask(isEnabled: config.tasks.devCaches),
            DownloadsTask(isEnabled: config.tasks.downloads),
        ])
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/CleanupEngine.swift Tests/AutoCleanMacCoreTests/CleanupEngineTests.swift
git commit -m "feat(core): add CleanupEngine with per-task events and summary"
```

---

## Task 15: ConsoleView and ConsoleWindow (SwiftUI)

The "cute console" — an `NSPanel` with a SwiftUI `ConsoleView` inside. Observable state is published by the engine via a view model.

**Files:**
- Create: `Sources/AutoCleanMac/ConsoleView.swift`
- Create: `Sources/AutoCleanMac/ConsoleWindow.swift`

- [ ] **Step 1: Create `ConsoleView.swift`**

`Sources/AutoCleanMac/ConsoleView.swift`:
```swift
import SwiftUI

final class ConsoleViewModel: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let prefix: String // "✓", "⚠", "✗", "•"
        let text: String
    }
    @Published var lines: [Line] = []
    @Published var summary: String? = nil
    @Published var finished: Bool = false
}

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("🧹  AutoCleanMac")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Divider().opacity(0.4)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.prefix)
                                    .frame(width: 14, alignment: .leading)
                                Text(line.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .id(line.id)
                        }
                    }
                }
                .onChange(of: model.lines.count) { _ in
                    if let last = model.lines.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            if let summary = model.summary {
                Divider().opacity(0.4)
                Text(summary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .frame(width: 480, height: 320)
    }
}
```

- [ ] **Step 2: Create `ConsoleWindow.swift`**

`Sources/AutoCleanMac/ConsoleWindow.swift`:
```swift
import AppKit
import SwiftUI

final class ConsoleWindow: NSObject {
    private var panel: NSPanel?
    let model = ConsoleViewModel()

    func showCentered(fadeInMs: Int) {
        let view = ConsoleView(model: model)
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Vibrancy backing view
        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 14
        visual.layer?.masksToBounds = true
        visual.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        visual.autoresizingMask = [.width, .height]

        hosting.frame = visual.bounds
        hosting.autoresizingMask = [.width, .height]
        visual.addSubview(hosting)

        panel.contentView = visual
        panel.center()
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Double(fadeInMs) / 1000.0
            panel.animator().alphaValue = 1.0
        }
        self.panel = panel
    }

    func fadeOutAndClose(holdMs: Int, fadeOutMs: Int, completion: @escaping () -> Void) {
        let deadline = DispatchTime.now() + .milliseconds(holdMs)
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let panel = self?.panel else { completion(); return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Double(fadeOutMs) / 1000.0
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                self?.panel = nil
                completion()
            })
        }
    }
}
```

- [ ] **Step 3: Build verify**

```bash
swift build
```
Expected: builds with warnings about unused Combine; no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoCleanMac/ConsoleView.swift Sources/AutoCleanMac/ConsoleWindow.swift
git commit -m "feat(app): add floating console window with SwiftUI view"
```

---

## Task 16: MenuBarController

**Files:**
- Create: `Sources/AutoCleanMac/MenuBarController.swift`

- [ ] **Step 1: Implement**

`Sources/AutoCleanMac/MenuBarController.swift`:
```swift
import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem?

    var onRunNow: (() -> Void)?
    var onShowLastLog: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onOpenLogsFolder: (() -> Void)?
    var onQuit: (() -> Void)?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🧹"
        item.button?.font = NSFont.systemFont(ofSize: 14)
        let menu = NSMenu()
        menu.addItem(withTitle: "Uruchom teraz",            action: #selector(runNow),        keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pokaż ostatnie sprzątanie", action: #selector(showLastLog),   keyEquivalent: "").target = self
        menu.addItem(withTitle: "Otwórz konfigurację",       action: #selector(openConfig),    keyEquivalent: "").target = self
        menu.addItem(withTitle: "Otwórz folder logów",       action: #selector(openLogsDir),   keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Zakończ",                   action: #selector(quit),          keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func runNow()        { onRunNow?() }
    @objc private func showLastLog()   { onShowLastLog?() }
    @objc private func openConfig()    { onOpenConfig?() }
    @objc private func openLogsDir()   { onOpenLogsFolder?() }
    @objc private func quit()          { onQuit?() }
}
```

- [ ] **Step 2: Build verify**

```bash
swift build
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/AutoCleanMac/MenuBarController.swift
git commit -m "feat(app): add MenuBarController with run-now / logs / config entries"
```

---

## Task 17: AppDelegate and wiring

**Files:**
- Create: `Sources/AutoCleanMac/AppDelegate.swift`
- Modify: `Sources/AutoCleanMac/main.swift`

- [ ] **Step 1: Replace `main.swift`**

`Sources/AutoCleanMac/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()
```

- [ ] **Step 2: Create `AppDelegate.swift`**

`Sources/AutoCleanMac/AppDelegate.swift`:
```swift
import AppKit
import AutoCleanMacCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var consoleWindow: ConsoleWindow?
    private var logger: Logger!
    private var config: Config = .default
    private var isRunning = false

    private let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AutoCleanMac")
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/autoclean-mac/config.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            logger = try Logger(directory: logsDir)
        } catch {
            NSLog("AutoCleanMac: failed to create logger at \(logsDir.path): \(error)")
            NSApp.terminate(nil)
            return
        }
        config = Config.loadOrDefault(from: configPath) { warn in
            self.logger.log(event: "config_warn", fields: ["msg": warn])
        }

        let menu = MenuBarController()
        menu.onRunNow         = { [weak self] in self?.runCleanup(source: "menu") }
        menu.onShowLastLog    = { [weak self] in self?.openMostRecentLog() }
        menu.onOpenConfig     = { [weak self] in self?.openInDefaultEditor(self!.configPath) }
        menu.onOpenLogsFolder = { [weak self] in NSWorkspace.shared.open(self!.logsDir) }
        menu.onQuit           = { NSApp.terminate(nil) }
        menu.install()
        menuBar = menu

        runCleanup(source: "login")
    }

    private func runCleanup(source: String) {
        guard !isRunning else { return }
        isRunning = true
        logger.log(event: "start", fields: ["source": source])

        let window = ConsoleWindow()
        window.showCentered(fadeInMs: config.window.fadeInMs)
        consoleWindow = window

        let mode: SafeDeleter.Mode = ProcessInfo.processInfo.environment["AUTOCLEANMAC_DRY_RUN"] != nil ? .dryRun : .live
        let deleter = SafeDeleter(mode: mode, logger: logger)
        let ctx = CleanupContext(retentionDays: config.retentionDays, deleter: deleter, logger: logger)
        let engine = CleanupEngine.makeDefault(config: config)

        Task {
            let summary = await engine.run(context: ctx) { event in
                Task { @MainActor in self.handle(event, on: window.model) }
            }
            await MainActor.run {
                window.model.summary = Self.formatSummary(summary)
                window.model.finished = true
                window.fadeOutAndClose(holdMs: self.config.window.holdAfterMs, fadeOutMs: self.config.window.fadeOutMs) {
                    self.consoleWindow = nil
                    self.isRunning = false
                }
            }
        }
    }

    @MainActor
    private func handle(_ event: CleanupEngine.Event, on model: ConsoleViewModel) {
        switch event {
        case .started:
            break
        case .taskStarted(let name):
            model.lines.append(.init(prefix: "•", text: "\(name)…"))
        case .taskFinished(let name, let result):
            // replace the last "•" line for this task with the finished one
            if let idx = model.lines.lastIndex(where: { $0.prefix == "•" && $0.text.hasPrefix(name) }) {
                model.lines.remove(at: idx)
            }
            if result.skipped {
                model.lines.append(.init(prefix: "·", text: "\(name) — pominięte (\(result.skipReason ?? "disabled"))"))
            } else {
                let prefix = result.warnings.isEmpty ? "✓" : "⚠"
                let size = Self.formatBytes(result.bytesFreed)
                var line = "\(name)  \(size)"
                if !result.warnings.isEmpty { line += "  (ostrzeżeń: \(result.warnings.count))" }
                model.lines.append(.init(prefix: prefix, text: line))
            }
        case .summary:
            break
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func formatSummary(_ s: CleanupEngine.Summary) -> String {
        let bytes = formatBytes(s.bytesFreed)
        let secs = String(format: "%.1f", Double(s.durationMs) / 1000.0)
        return "Zwolniono: \(bytes) · \(secs)s"
    }

    private func openMostRecentLog() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let newest = files
            .filter { $0.pathExtension == "log" }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .first
        if let newest { NSWorkspace.shared.open(newest) }
    }

    private func openInDefaultEditor(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let defaultJson = """
            {
              "retention_days": 7,
              "window": { "fade_in_ms": 800, "hold_after_ms": 3000, "fade_out_ms": 800 },
              "tasks": {
                "user_caches": true,
                "system_temp": true,
                "trash": true,
                "ds_store": true,
                "user_logs": true,
                "browser_caches": true,
                "dev_caches": true,
                "downloads": false
              }
            }
            """
            try? defaultJson.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: Build + run tests**

```bash
swift build
swift test
```
Expected: build passes; all existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoCleanMac/AppDelegate.swift Sources/AutoCleanMac/main.swift
git commit -m "feat(app): wire AppDelegate (login cleanup, menu bar, logs, config)"
```

---

## Task 18: Build `.app` bundle script

Swift Package Manager produces a plain Mach-O executable. We wrap it into a proper `.app` bundle with `Info.plist` so `LSUIElement`, `LSApplicationCategoryType`, and a stable bundle ID take effect.

**Files:**
- Create: `scripts/build-app-bundle.sh`

- [ ] **Step 1: Create the script**

`scripts/build-app-bundle.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="AutoCleanMac"
BUNDLE_ID="com.micz.autocleanmac"
VERSION="0.1.0"
BUILD_DIR="$REPO_ROOT/.build/release"
OUT_DIR="$REPO_ROOT/.build/bundle"
APP_DIR="$OUT_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "→ swift build -c release"
swift build -c release

echo "→ assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>       <string>en</string>
    <key>CFBundleExecutable</key>              <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>              <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>   <string>6.0</string>
    <key>CFBundleName</key>                    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleShortVersionString</key>      <string>$VERSION</string>
    <key>CFBundleVersion</key>                 <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>          <string>13.0</string>
    <key>LSUIElement</key>                     <true/>
    <key>NSHighResolutionCapable</key>         <true/>
</dict>
</plist>
EOF

echo "→ ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR"

echo "→ done: $APP_DIR"
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x scripts/build-app-bundle.sh
./scripts/build-app-bundle.sh
```
Expected: `.build/bundle/AutoCleanMac.app` exists and has `Contents/MacOS/AutoCleanMac` + `Info.plist`.

- [ ] **Step 3: Smoke-launch the bundle in DRY-RUN mode first**

The first smoke test should never actually delete anything on your real home. Launch directly (not via `open`) so env vars propagate:

```bash
AUTOCLEANMAC_DRY_RUN=1 .build/bundle/AutoCleanMac.app/Contents/MacOS/AutoCleanMac
```
Expected: a 🧹 icon appears in the menu bar; a small console window fades in on screen, runs cleanup against your real home in **dry-run** mode (logs only, no deletions), fades out after ~4s. Inspect `~/Library/Logs/AutoCleanMac/*.log` — every deletion line should start with `dryrun` not `delete`. Quit via menu bar "Zakończ".

Once dry-run looks good, do a live run:

```bash
.build/bundle/AutoCleanMac.app/Contents/MacOS/AutoCleanMac
```

If anything misbehaves (e.g. window is opaque grey, no fade), check logs at `~/Library/Logs/AutoCleanMac/`.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-app-bundle.sh
git commit -m "build: add shell script to assemble .app bundle with Info.plist and ad-hoc signing"
```

---

## Task 19: LaunchAgent plist + install script

**Files:**
- Create: `resources/com.micz.autocleanmac.plist.template`
- Create: `scripts/install.sh`

- [ ] **Step 1: Create plist template**

`resources/com.micz.autocleanmac.plist.template`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.micz.autocleanmac</string>
    <key>ProgramArguments</key>
    <array>
        <string>__APP_BINARY__</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>__LOGS_DIR__/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>__LOGS_DIR__/launchd.err.log</string>
</dict>
</plist>
```

- [ ] **Step 2: Create `install.sh`**

`scripts/install.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="AutoCleanMac"
BUNDLE_ID="com.micz.autocleanmac"
INSTALL_DIR="$HOME/Applications"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
CONFIG_DIR="$HOME/.config/autoclean-mac"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOGS_DIR="$HOME/Library/Logs/AutoCleanMac"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Command Line Tools are not installed."
    echo "Uruchom: xcode-select --install"
    exit 1
fi

echo "→ building .app bundle"
"$REPO_ROOT/scripts/build-app-bundle.sh"

echo "→ installing to $APP_DEST"
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_DEST"
cp -R "$REPO_ROOT/.build/bundle/$APP_NAME.app" "$APP_DEST"

echo "→ ensuring log directory"
mkdir -p "$LOGS_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "→ writing default config to $CONFIG_FILE"
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<'JSON'
{
  "retention_days": 7,
  "window": { "fade_in_ms": 800, "hold_after_ms": 3000, "fade_out_ms": 800 },
  "tasks": {
    "user_caches": true,
    "system_temp": true,
    "trash": true,
    "ds_store": true,
    "user_logs": true,
    "browser_caches": true,
    "dev_caches": true,
    "downloads": false
  }
}
JSON
else
    echo "→ config exists at $CONFIG_FILE (leaving untouched)"
fi

echo "→ installing LaunchAgent"
mkdir -p "$(dirname "$LAUNCH_AGENT")"
sed \
    -e "s|__APP_BINARY__|$APP_DEST/Contents/MacOS/$APP_NAME|g" \
    -e "s|__LOGS_DIR__|$LOGS_DIR|g" \
    "$REPO_ROOT/resources/com.micz.autocleanmac.plist.template" > "$LAUNCH_AGENT"

# If it was loaded previously, unload first to pick up changes.
launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
launchctl load -w "$LAUNCH_AGENT"

echo ""
echo "✓ AutoCleanMac zainstalowany."
echo "  • Aplikacja:     $APP_DEST"
echo "  • Konfiguracja:  $CONFIG_FILE"
echo "  • Logi:          $LOGS_DIR"
echo "  • LaunchAgent:   $LAUNCH_AGENT"
echo ""
echo "Możesz uruchomić ręcznie: open \"$APP_DEST\""
echo "Deinstalacja: ./scripts/uninstall.sh"
```

- [ ] **Step 3: Make executable and test install**

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```
Expected: summary lines are printed; 🧹 icon appears in menu bar; cleanup runs; `launchctl list | grep autocleanmac` shows the agent.

- [ ] **Step 4: Verify at next login**

```bash
launchctl list | grep com.micz.autocleanmac
```
Expected: one row with a numeric PID (or `-` if not currently running).

- [ ] **Step 5: Commit**

```bash
git add resources/com.micz.autocleanmac.plist.template scripts/install.sh
git commit -m "build: add LaunchAgent template and install script"
```

---

## Task 20: uninstall script

**Files:**
- Create: `scripts/uninstall.sh`

- [ ] **Step 1: Write script**

`scripts/uninstall.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.micz.autocleanmac"
APP_DEST="$HOME/Applications/AutoCleanMac.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
CONFIG_DIR="$HOME/.config/autoclean-mac"
LOGS_DIR="$HOME/Library/Logs/AutoCleanMac"

if [[ -f "$LAUNCH_AGENT" ]]; then
    echo "→ unloading LaunchAgent"
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
fi

if [[ -d "$APP_DEST" ]]; then
    echo "→ removing $APP_DEST"
    rm -rf "$APP_DEST"
fi

# Kill any lingering instance (e.g. the user ran the app by hand).
pkill -f "$APP_DEST/Contents/MacOS/AutoCleanMac" 2>/dev/null || true

read -r -p "Usunąć również konfigurację ($CONFIG_DIR)? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf "$CONFIG_DIR"
    echo "  usunięto."
fi

read -r -p "Usunąć również logi ($LOGS_DIR)? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf "$LOGS_DIR"
    echo "  usunięto."
fi

echo "✓ AutoCleanMac odinstalowany."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/uninstall.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/uninstall.sh
git commit -m "build: add uninstall script"
```

---

## Task 21: End-to-end smoke verification

Final walkthrough on the actual machine.

- [ ] **Step 1: Clean install**

```bash
cd /Users/micz/__DEV__/__auto_clean_mac
./scripts/uninstall.sh || true   # in case of leftovers from dev
./scripts/install.sh
```

Expected: install messages print; the app launches immediately and runs cleanup once.

- [ ] **Step 2: Verify menu bar item is functional**

Click the 🧹 in the menu bar. Click each menu entry and verify:
- **Uruchom teraz** → window fades in, tasks scroll, fades out.
- **Pokaż ostatnie sprzątanie** → opens today's `.log` file in Console.app (default handler for `.log`).
- **Otwórz konfigurację** → opens `config.json` in the default editor.
- **Otwórz folder logów** → Finder reveals `~/Library/Logs/AutoCleanMac`.
- **Zakończ** → app exits; menu bar icon disappears.

- [ ] **Step 3: Verify log format**

```bash
ls -la ~/Library/Logs/AutoCleanMac/
```
Open the most recent `.log`; confirm it contains `start`, multiple `delete` lines, and a `summary` line.

- [ ] **Step 4: Verify login trigger**

Log out and back in. Expected: 🧹 icon appears in menu bar, console window fades in shortly after login.

- [ ] **Step 5: Verify safety guard manually**

Create a symlink inside a task's root that points outside, run manual cleanup, then confirm the target was not touched:

```bash
mkdir -p ~/Library/Caches/.test-escape
echo "keep me" > /tmp/never-touch-me
ln -s /tmp/never-touch-me ~/Library/Caches/.test-escape/trap
# click "Uruchom teraz" in menu bar
cat /tmp/never-touch-me   # must still print "keep me"
rm -rf ~/Library/Caches/.test-escape /tmp/never-touch-me
```
Expected: `/tmp/never-touch-me` still exists and contents unchanged. In the log you should see a warning line for the symlink (it resolves outside the cache root, so `SafeDeleter` throws `outsideAllowedRoot` and the task records a warning rather than deleting). This proves the realpath containment guard is active.

- [ ] **Step 6: Tag a release commit**

```bash
git add -A
git commit --allow-empty -m "chore: v0.1.0 — first working end-to-end build"
git tag v0.1.0
```

---

## Coverage check

Every section of the spec maps to at least one task:

| Spec section | Implemented in |
|---|---|
| User flow (login → console → fade-out) | Tasks 15, 17, 19 |
| Menu bar entries | Task 16, 17, 21 |
| Architecture: AutoCleanMacCore vs AutoCleanMac | Task 1 |
| `CleanupTask` protocol, `TaskResult`, `CleanupContext` | Task 5 |
| `SafeDeleter` + realpath containment + dry-run | Task 4 |
| Task: User caches | Task 10 |
| Task: System temp | Task 9 |
| Task: Trash | Task 6 |
| Task: DSStore | Task 7 |
| Task: User logs | Task 8 |
| Task: Browser caches (allow-list) | Task 11 |
| Task: Dev caches (Xcode, npm, pip, brew) | Task 12 |
| Task: Downloads (opt-in) | Task 13 |
| `CleanupEngine` orchestration + events | Task 14 |
| Console window UI (vibrancy, fade, always-on-top, scrolling) | Task 15 |
| Config file format + fallback | Task 3 |
| LaunchAgent plist | Task 19 |
| Logs: daily file, one line per event | Task 2, 17 |
| Install / uninstall flow | Tasks 18, 19, 20 |
| Error handling (permission denied, busy, missing roots) | Tasks 4, 6–13 (warnings path) |
| Testing strategy (SafeDeleter unit, task integration) | Tasks 2–14 |
| Manual smoke | Task 21 |

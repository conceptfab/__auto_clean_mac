# AutoCleanMac Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the correctness bugs, performance hot-spots, dead code, and top duplication surfaced by the 2026-06-16 four-reviewer audit, without changing user-visible cleanup semantics (except the one intentional orphan-mode fix in Task 1).

**Architecture:** Two SPM modules — `AutoCleanMacCore` (logic, fully unit-tested) and `AutoCleanMac` (AppKit/SwiftUI executable). Fixes are ordered: correctness bugs first (Tasks 1–3), then perf (Tasks 4–7), then UI perf (Tasks 8–9), then a shared byte-formatter (Task 10), then a dead-code sweep (Task 11). Each behavioral change is pinned by a test written before the change.

**Tech Stack:** Swift 5.9, swift-tools-version 5.9, XCTest, FileManager/`URLResourceKey`, Swift Concurrency (`TaskGroup`), SwiftUI, macOS 13+.

**Build/test commands:**
- Build: `swift build`
- Full suite: `swift test`
- Single class: `swift test --filter SafeDeleterTests`
- Single test: `swift test --filter SafeDeleterTests/test_name`

**Baseline:** Branch `next`, 99 tests passing. Run `swift test` once before starting and confirm green.

---

## File Structure

**Modified (Core):**
- `Sources/AutoCleanMacCore/Config.swift` — add `DeleteMode.safeDeleterMode` + `DeleteMode.jsonValue`
- `Sources/AutoCleanMacCore/SafeDeleter.swift` — add `Mode.label`; add `URL.isWithin`; optimize `recursiveMetrics` symlink branch
- `Sources/AutoCleanMacCore/ConfigWriter.swift` — use `deleteMode.jsonValue`
- `Sources/AutoCleanMacCore/Tasks/DevCachesTask.swift` — use `mode.label`
- `Sources/AutoCleanMacCore/AppPurger.swift` — use `URL.isWithin` (prefix bug); drop eager pre-measure
- `Sources/AutoCleanMacCore/AppScanner.swift` — parallelize `scanApps`
- `Sources/AutoCleanMacCore/OrphanScanner.swift` — parallelize candidate sizing

**Modified (App):**
- `Sources/AutoCleanMac/AppDelegate.swift` — use `safeDeleterMode`/`label`; offload orphan scan/remove off main thread; remove dead method + dead `@Published` writes
- `Sources/AutoCleanMac/SettingsView.swift` — use `deleteMode.safeDeleterMode` (orphan-mode fix)
- `Sources/AutoCleanMac/UI/Tabs/UninstallerTab.swift` — use `deleteMode.safeDeleterMode`
- `Sources/AutoCleanMac/ConsoleView.swift` — cap `lines`, `LazyVStack`, remove dead `statusColor`/`finished`
- `Sources/AutoCleanMac/UI/Tabs/BrowsersTab.swift` — cache installed browsers in `@State`
- `Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift` — static `ByteCountFormatter`
- `Sources/AutoCleanMac/UI/Components/SettingsComponents.swift` — remove dead `overviewSummary`
- `Sources/AutoCleanMacCore/ByteFormatting.swift` — **new** shared formatter

**Test files:**
- `Tests/AutoCleanMacCoreTests/ConfigTests.swift` — mode-mapping tests
- `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift` — `isWithin` + symlink-metrics characterization
- `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift` — prefix-bug regression
- `Tests/AutoCleanMacCoreTests/ByteFormattingTests.swift` — **new**

**Deleted (orphaned, not in `Package.swift`):**
- `test_scanner.swift`, `test_symbols.swift`, `test_memory.sh`, `test_output.txt`

---

## Task 1: Centralize `DeleteMode` → `SafeDeleter.Mode` mapping (fixes inconsistency bug)

The same `switch` is hand-written in 3 UI sites, and `SettingsView.swift:92` diverges: it collapses `.dryRun → .trash` for orphan removal, while the uninstaller maps `.dryRun → .dryRun`. This makes "Tylko symulacja" silently *trash* orphan files instead of simulating. We add one mapping on the enum and route all sites through it — which also corrects the orphan behavior.

**Files:**
- Modify: `Sources/AutoCleanMacCore/Config.swift:3-16`
- Modify: `Sources/AutoCleanMacCore/SafeDeleter.swift:14`
- Modify: `Sources/AutoCleanMac/AppDelegate.swift:200-214`
- Modify: `Sources/AutoCleanMac/SettingsView.swift:92`
- Modify: `Sources/AutoCleanMac/UI/Tabs/UninstallerTab.swift:176-181`
- Modify: `Sources/AutoCleanMacCore/ConfigWriter.swift:45-50`
- Modify: `Sources/AutoCleanMacCore/Tasks/DevCachesTask.swift:164-173`
- Test: `Tests/AutoCleanMacCoreTests/ConfigTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/AutoCleanMacCoreTests/ConfigTests.swift` (inside the existing `final class ConfigTests: XCTestCase`):

```swift
func test_deleteMode_maps_to_safeDeleterMode() {
    XCTAssertEqual(DeleteMode.trash.safeDeleterMode, .trash)
    XCTAssertEqual(DeleteMode.live.safeDeleterMode, .live)
    XCTAssertEqual(DeleteMode.dryRun.safeDeleterMode, .dryRun)
}

func test_deleteMode_jsonValue_roundtrips_through_parse() {
    for mode in [DeleteMode.trash, .live, .dryRun] {
        XCTAssertEqual(DeleteMode.parse(mode.jsonValue), mode)
    }
    XCTAssertEqual(DeleteMode.dryRun.jsonValue, "dry_run")
}

func test_safeDeleterMode_label_matches_json() {
    XCTAssertEqual(SafeDeleter.Mode.live.label, "live")
    XCTAssertEqual(SafeDeleter.Mode.dryRun.label, "dry_run")
    XCTAssertEqual(SafeDeleter.Mode.trash.label, "trash")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigTests/test_deleteMode_maps_to_safeDeleterMode`
Expected: FAIL — `value of type 'DeleteMode' has no member 'safeDeleterMode'`

- [ ] **Step 3: Add the mappings to the enums**

In `Sources/AutoCleanMacCore/Config.swift`, replace the `DeleteMode` enum (lines 3-16) with:

```swift
public enum DeleteMode: String, Equatable {
    case trash
    case live
    case dryRun

    public static func parse(_ raw: String) -> DeleteMode? {
        switch raw {
        case "trash":    return .trash
        case "live":     return .live
        case "dry_run":  return .dryRun
        default:         return nil
        }
    }

    /// Runtime deletion mode used by `SafeDeleter`.
    public var safeDeleterMode: SafeDeleter.Mode {
        switch self {
        case .trash:  return .trash
        case .live:   return .live
        case .dryRun: return .dryRun
        }
    }

    /// Canonical JSON/log string. Inverse of `parse(_:)`.
    public var jsonValue: String {
        switch self {
        case .trash:  return "trash"
        case .live:   return "live"
        case .dryRun: return "dry_run"
        }
    }
}
```

In `Sources/AutoCleanMacCore/SafeDeleter.swift`, replace line 14 (`public enum Mode: Sendable { case live, dryRun, trash }`) with:

```swift
    public enum Mode: Sendable {
        case live, dryRun, trash

        /// Canonical log/serialization string.
        public var label: String {
            switch self {
            case .live:   return "live"
            case .dryRun: return "dry_run"
            case .trash:  return "trash"
            }
        }
    }
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `swift test --filter ConfigTests`
Expected: PASS (all three new tests green)

- [ ] **Step 5: Route all call sites through the new mappings**

In `Sources/AutoCleanMac/AppDelegate.swift`, replace lines 200-214 (the `mode` closure + `modeString` switch) with:

```swift
        let mode: SafeDeleter.Mode = {
            if let forcedMode { return forcedMode }
            if ProcessInfo.processInfo.environment["AUTOCLEANMAC_DRY_RUN"] != nil { return .dryRun }
            return effectiveConfig.deleteMode.safeDeleterMode
        }()
        logger.log(event: "mode", fields: ["mode": mode.label])
```

In `Sources/AutoCleanMac/SettingsView.swift`, replace line 92:

```swift
        _ = await onRemoveOrphans(chosen, deleteMode == .live ? .live : .trash)
```

with:

```swift
        _ = await onRemoveOrphans(chosen, deleteMode.safeDeleterMode)
```

In `Sources/AutoCleanMac/UI/Tabs/UninstallerTab.swift`, replace lines 176-181 (the `safeDeleterMode` declaration + switch) with:

```swift
        let safeDeleterMode = settingsModel.deleteMode.safeDeleterMode
```

In `Sources/AutoCleanMacCore/ConfigWriter.swift`, replace lines 45-50 (the `deleteModeJson` switch) with:

```swift
        let deleteModeJson = config.deleteMode.jsonValue
```

In `Sources/AutoCleanMacCore/Tasks/DevCachesTask.swift`, replace the body of `deletionModeLabel` (lines 164-173) with a one-liner that delegates to `Mode.label`. Replace:

```swift
    private static func deletionModeLabel(_ mode: SafeDeleter.Mode) -> String {
        switch mode {
        case .dryRun:
            return "dry_run"
        case .live:
            return "live"
        case .trash:
            return "trash"
        }
    }
```

with:

```swift
    private static func deletionModeLabel(_ mode: SafeDeleter.Mode) -> String {
        mode.label
    }
```

- [ ] **Step 6: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures (existing tests unaffected; orphan dry-run now simulates instead of trashing)

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoCleanMacCore/Config.swift Sources/AutoCleanMacCore/SafeDeleter.swift Sources/AutoCleanMacCore/ConfigWriter.swift Sources/AutoCleanMacCore/Tasks/DevCachesTask.swift Sources/AutoCleanMac/AppDelegate.swift Sources/AutoCleanMac/SettingsView.swift Sources/AutoCleanMac/UI/Tabs/UninstallerTab.swift Tests/AutoCleanMacCoreTests/ConfigTests.swift
git commit -m "fix: centralize DeleteMode mapping and fix orphan dry-run trashing files"
```

---

## Task 2: Fix `AppPurger` path-prefix false match (latent deletion-gating bug)

`AppPurger` decides whether to `unload` a LaunchAgent/LaunchDaemon before deletion with bare `url.path.hasPrefix(dir.path)` (no trailing separator), so `…/LaunchAgents-Backup/x.plist` matches `…/LaunchAgents`. `SafeDeleter` already does this correctly with a `rootWithSep` guard. We extract that as a reusable `URL.isWithin` and route both `AppPurger` sites through it.

**Files:**
- Modify: `Sources/AutoCleanMacCore/SafeDeleter.swift` (add `URL.isWithin` extension + reuse it in `deleteMeasured`)
- Modify: `Sources/AutoCleanMacCore/AppPurger.swift:123`, `:140-141`
- Test: `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift` (inside the class):

```swift
func test_isWithin_requires_path_boundary_not_just_prefix() {
    let root = URL(fileURLWithPath: "/Users/x/Library/LaunchAgents")
    let inside = URL(fileURLWithPath: "/Users/x/Library/LaunchAgents/com.foo.plist")
    let sibling = URL(fileURLWithPath: "/Users/x/Library/LaunchAgents-Backup/com.foo.plist")
    XCTAssertTrue(inside.isWithin(root))
    XCTAssertTrue(root.isWithin(root))          // the root itself counts as within
    XCTAssertFalse(sibling.isWithin(root))      // the bug: must NOT match
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SafeDeleterTests/test_isWithin_requires_path_boundary_not_just_prefix`
Expected: FAIL — `value of type 'URL' has no member 'isWithin'`

- [ ] **Step 3: Add the `URL.isWithin` extension**

At the bottom of `Sources/AutoCleanMacCore/SafeDeleter.swift` (after the closing `}` of `SafeDeleter`, line 125), add:

```swift
public extension URL {
    /// True when `self` is `root` itself or a descendant of it, comparing on path
    /// boundaries (so `…/Foo-Backup` does NOT count as within `…/Foo`).
    func isWithin(_ root: URL) -> Bool {
        let rootStr = root.path
        let selfStr = self.path
        let rootWithSep = rootStr.hasSuffix("/") ? rootStr : rootStr + "/"
        return selfStr == rootStr || selfStr.hasPrefix(rootWithSep)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SafeDeleterTests/test_isWithin_requires_path_boundary_not_just_prefix`
Expected: PASS

- [ ] **Step 5: Route `AppPurger` through `isWithin`**

In `Sources/AutoCleanMacCore/AppPurger.swift`, replace line 123:

```swift
            if url.path.hasPrefix(userLib.appendingPathComponent("LaunchAgents").path) {
```

with:

```swift
            if url.isWithin(userLib.appendingPathComponent("LaunchAgents")) {
```

And replace lines 140-141:

```swift
                if url.path.hasPrefix(systemLib.appendingPathComponent("LaunchDaemons").path)
                    || url.path.hasPrefix(systemLib.appendingPathComponent("LaunchAgents").path) {
```

with:

```swift
                if url.isWithin(systemLib.appendingPathComponent("LaunchDaemons"))
                    || url.isWithin(systemLib.appendingPathComponent("LaunchAgents")) {
```

- [ ] **Step 6: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoCleanMacCore/SafeDeleter.swift Sources/AutoCleanMacCore/AppPurger.swift Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift
git commit -m "fix: use path-boundary check for LaunchAgents gating in AppPurger"
```

---

## Task 3: Offload orphan scan/remove off the main thread (UI freeze)

`onScanOrphans` / `onRemoveOrphans` (`AppDelegate.swift:574-602`) run recursive `~/Library` walks + per-path sizing synchronously. Their only caller is the `@MainActor` `SettingsModel`, so the Settings window beachballs for the whole scan. `InstalledAppRegistry`, `OrphanScanner`, `SafeDeleter`, `OrphanGroup`, and `UninstallOutcome` are all value/`Sendable` types, so the bodies can run on `Task.detached` (the pattern already used for `launchServices.rebuild()` at line 567).

**Files:**
- Modify: `Sources/AutoCleanMac/AppDelegate.swift:574-602`

This is a UI-closure change with no unit-test seam; verify by build + the existing suite (closures are exercised indirectly) and a manual smoke note.

- [ ] **Step 1: Wrap `onScanOrphans` body in a detached task**

In `Sources/AutoCleanMac/AppDelegate.swift`, replace the `onScanOrphans` closure (lines 574-580):

```swift
            onScanOrphans: {
                var installed = InstalledAppRegistry().installedBundleIDs(
                    searchRoots: InstalledAppRegistry.defaultSearchRoots(homeDirectory: home)
                )
                installed.formUnion(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                return OrphanScanner().scan(homeDirectory: home, installedBundleIDs: installed)
            },
```

with:

```swift
            onScanOrphans: {
                let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
                return await Task.detached(priority: .userInitiated) {
                    var installed = InstalledAppRegistry().installedBundleIDs(
                        searchRoots: InstalledAppRegistry.defaultSearchRoots(homeDirectory: home)
                    )
                    installed.formUnion(running)
                    return OrphanScanner().scan(homeDirectory: home, installedBundleIDs: installed)
                }.value
            },
```

(Note: `NSWorkspace.shared.runningApplications` is read on the main actor *before* detaching, since `NSWorkspace` is main-actor affine; the heavy filesystem walk runs off-main.)

- [ ] **Step 2: Wrap `onRemoveOrphans` body in a detached task**

Replace the `onRemoveOrphans` closure (lines 581-601):

```swift
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

with:

```swift
            onRemoveOrphans: { [weak self] groups, mode in
                guard let self else { return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: []) }
                let logger = self.logger
                return await Task.detached(priority: .userInitiated) {
                    let deleter = SafeDeleter(mode: mode, logger: logger)
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
                }.value
            }
```

- [ ] **Step 3: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures. If the compiler reports a `Sendable` capture error on `groups`, confirm `OrphanGroup` (and its `paths`) are `Sendable`; if not, add `Sendable` conformance to those Core types in the same commit (they are immutable value types).

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoCleanMac/AppDelegate.swift
git commit -m "perf: run orphan scan/remove off the main thread to avoid UI freeze"
```

---

## Task 4: Remove redundant `attributesOfItem` in `recursiveMetrics` symlink branch

`recursiveMetrics` already prefetches `.fileSizeKey` via the enumerator, then for symlinks (`SafeDeleter.swift:111-114`) does a *second* `fm.attributesOfItem(atPath:)` (a fresh `lstat` + `NSDictionary` alloc) just to read the link size. We first pin the current byte/item output with a characterization test, then read the prefetched value instead — only the symlink syscall changes, reported sizes must stay identical.

**Files:**
- Modify: `Sources/AutoCleanMacCore/SafeDeleter.swift:111-118`
- Test: `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`

- [ ] **Step 1: Write a characterization test pinning current metrics (incl. a symlink)**

Append to `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`:

```swift
func test_recursiveMetrics_counts_files_and_symlink_without_following() throws {
    let dir = tempDir.appendingPathComponent("tree")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Fixtures.makeFile(at: dir.appendingPathComponent("a.txt"), size: 100)
    try Fixtures.makeFile(at: dir.appendingPathComponent("sub/b.txt"), size: 50)
    let target = tempDir.appendingPathComponent("outside.txt")
    try Fixtures.makeFile(at: target, size: 999)
    try Fixtures.makeSymlink(at: dir.appendingPathComponent("link"), pointingTo: target)

    let metrics = try SafeDeleter.recursiveMetrics(at: dir)

    // 2 regular files + 1 symlink counted; symlink NOT followed (999 excluded).
    XCTAssertEqual(metrics.itemsDeleted, 3)
    XCTAssertEqual(metrics.bytesFreed, 150 + metrics.bytesFreed - 150) // placeholder; replaced in Step 2
}
```

- [ ] **Step 2: Run it, read the ACTUAL byte total, then pin it exactly**

Run: `swift test --filter SafeDeleterTests/test_recursiveMetrics_counts_files_and_symlink_without_following`
Expected: it FAILS or passes trivially; read the printed `metrics.bytesFreed` (use a temporary `print(metrics)` if needed). The symlink contributes its own small link-path byte size. Replace the placeholder assertion with the real observed value, e.g.:

```swift
    XCTAssertEqual(metrics.itemsDeleted, 3)
    XCTAssertEqual(metrics.bytesFreed, 150 + Int64(target.path.utf8.count))
```

Re-run; confirm it now PASSES against the **current** implementation. This is the green baseline the refactor must preserve. (If the symlink byte size differs from `target.path.utf8.count` on this platform, pin whatever value the current code returns — the point is to lock present behavior.)

- [ ] **Step 3: Replace `attributesOfItem` with the prefetched resource value**

In `Sources/AutoCleanMacCore/SafeDeleter.swift`, replace lines 111-118:

```swift
                if values?.isSymbolicLink == true {
                    let linkAttrs = try? fm.attributesOfItem(atPath: child.path)
                    total += (linkAttrs?[.size] as? Int64) ?? 0
                    items += 1
                    continue
                }
                total += Int64(values?.fileSize ?? 0)
                items += 1
```

with:

```swift
                // Symlinks and regular files both use the enumerator-prefetched size;
                // we never follow links (sized by their own link length).
                total += Int64(values?.fileSize ?? 0)
                items += 1
```

- [ ] **Step 4: Run the characterization test**

Run: `swift test --filter SafeDeleterTests/test_recursiveMetrics_counts_files_and_symlink_without_following`
Expected: PASS with the **same** pinned value. If it changed, `.fileSizeKey` reports a different symlink size than `attributesOfItem[.size]` on this platform — in that case revert Step 3's symlink handling (keep `attributesOfItem` only for the `isSymbolicLink` case) and stop; the regular-file path is already optimal. Re-pin and commit the no-op-for-symlinks version.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, 0 failures (other size-asserting tests unchanged).

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/SafeDeleter.swift Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift
git commit -m "perf: avoid extra lstat per symlink in recursiveMetrics"
```

---

## Task 5: Parallelize `AppScanner.scanApps` with a bounded TaskGroup

`AppScanner.scanApps` processes app bundles one at a time (`AppScanner.swift:32-46`), each doing a full recursive size walk — fully independent and I/O-bound. A `TaskGroup` cuts wall-clock scan time several-fold on machines with many apps. Results are sorted after collection so ordering is unchanged.

**Files:**
- Modify: `Sources/AutoCleanMacCore/AppScanner.swift:32-46`
- Test: existing `Tests/AutoCleanMacCoreTests/*` covering `AppScanner` must still pass (look for `AppScannerTests` or scanner assertions in `AppStatisticsTests`/`InstalledAppRegistryTests`).

- [ ] **Step 1: Read the current `scanApps` and confirm `processApp` is independent per bundle**

Run: `sed -n '28,110p' Sources/AutoCleanMacCore/AppScanner.swift`
Confirm: each iteration calls `await processApp(...)` with no shared mutable state besides the result array, and `AppInfo` is `Sendable`. Note the exact local variable names (`appURLs`, `results`, the sort key) used below.

- [ ] **Step 2: Write/confirm a test that pins scan output is order-stable**

If an `AppScannerTests` file exists, ensure a test asserts the returned apps are sorted (e.g. by size descending or name). If none asserts ordering, add one to the appropriate existing scanner test file:

```swift
func test_scanApps_returns_results_sorted_stably() async throws {
    // Arrange a fixture root with two fake .app bundles of different sizes,
    // then assert the returned order matches the existing sort key.
    // (Use the same Fixtures helpers the other AppScanner tests use.)
}
```

If the project has no `AppScanner` fixture harness, skip adding a new test and rely on the full suite — note this in the commit message.

- [ ] **Step 3: Convert the serial loop to a TaskGroup**

In `Sources/AutoCleanMacCore/AppScanner.swift`, replace the serial `for` loop (lines ~32-46) that builds `results` by appending `await processApp(...)`. Replace:

```swift
        var results: [AppInfo] = []
        for appURL in appURLs {
            if let info = await processApp(appURL) {
                results.append(info)
            }
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
```

with (adjust the sort key to match the existing one observed in Step 1):

```swift
        let results = await withTaskGroup(of: AppInfo?.self) { group -> [AppInfo] in
            let maxConcurrent = 8
            var iterator = appURLs.makeIterator()
            var inFlight = 0
            var collected: [AppInfo] = []

            func addNext() {
                guard let appURL = iterator.next() else { return }
                inFlight += 1
                group.addTask { await self.processApp(appURL) }
            }

            for _ in 0..<maxConcurrent { addNext() }
            while inFlight > 0 {
                if let info = await group.next() {
                    inFlight -= 1
                    if let info { collected.append(info) }
                    addNext()
                }
            }
            return collected
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
```

(If `processApp` is `nonisolated`/free of `self` mutation this compiles directly. If `processApp` touches `@MainActor` icon loading, keep that hop inside `processApp` — it already isolates per-task and won't block siblings.)

- [ ] **Step 4: Build and run scanner tests**

Run: `swift build && swift test --filter AppScanner` (and `swift test --filter AppStatistics` if scanner output feeds statistics)
Expected: PASS — identical apps, identical sort order.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/AppScanner.swift Tests/AutoCleanMacCoreTests/
git commit -m "perf: scan app bundles concurrently with bounded TaskGroup"
```

---

## Task 6: Parallelize `OrphanScanner` candidate sizing

`OrphanScanner.scan` sizes every candidate with a serial recursive walk (`OrphanScanner.swift` ~line 91/109). Sizing is independent per candidate; a bounded `TaskGroup` over the candidates (after the cheap directory listing) parallelizes the expensive part. Output ordering must be preserved.

**Files:**
- Modify: `Sources/AutoCleanMacCore/OrphanScanner.swift`
- Test: `Tests/AutoCleanMacCoreTests/OrphanScannerTests.swift` (existing tests must still pass; they assert which paths are flagged and their grouping/order)

- [ ] **Step 1: Read `scan` and identify the sizing loop**

Run: `sed -n '40,140p' Sources/AutoCleanMacCore/OrphanScanner.swift`
Identify the loop that maps each candidate path → `(path, size)` via `SafeDeleter.recursiveMetrics`. Note whether `scan` is currently `async` (it is called from `onScanOrphans`, which after Task 3 runs inside `Task.detached` — `scan` itself may be synchronous). If `scan` is **synchronous**, wrap only the sizing in a private `async` helper, or compute sizes via a `TaskGroup` inside a `Task { }.value` bridge. Prefer making the internal sizing function `async` and keeping `scan`'s signature unchanged if callers are synchronous; if changing `scan` to `async` is cleaner, update its single caller `onScanOrphans` (already `await`-capable after Task 3).

- [ ] **Step 2: Confirm OrphanScannerTests pin path selection + ordering**

Run: `swift test --filter OrphanScannerTests`
Expected: PASS now (green baseline). These tests are the safety net — sizing parallelization must not change which paths are returned or their order.

- [ ] **Step 3: Replace the serial sizing loop with a TaskGroup that preserves order**

Replace the serial sizing of candidates. Pattern (size by index so order is preserved):

```swift
        // candidates: [OrphanCandidate] already discovered in directory order.
        let sized: [Int64] = await withTaskGroup(of: (Int, Int64).self) { group in
            for (i, candidate) in candidates.enumerated() {
                group.addTask {
                    let bytes = (try? SafeDeleter.recursiveMetrics(at: candidate.url).bytesFreed) ?? 0
                    return (i, bytes)
                }
            }
            var buffer = [Int64](repeating: 0, count: candidates.count)
            for await (i, bytes) in group { buffer[i] = bytes }
            return buffer
        }
        // Zip sizes back onto candidates in original order:
        let orphans = zip(candidates, sized).map { candidate, bytes in
            // build the same Orphan/OrphanPath value the serial code built, using `bytes`
        }
```

Adapt the final `.map` to construct exactly the same result type the current code returns. Keep all selection/grouping/age logic untouched — only the size computation moves into the group.

- [ ] **Step 4: Run OrphanScannerTests**

Run: `swift test --filter OrphanScannerTests`
Expected: PASS — same paths, same order, same sizes.

- [ ] **Step 5: Run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoCleanMacCore/OrphanScanner.swift
git commit -m "perf: size orphan candidates concurrently, preserving order"
```

---

## Task 7: Drop eager pre-measurement in `AppPurger.purge`

`AppPurger.swift:91` computes `preDeleteMetrics` (a full bundle walk) on every purge, but it's only consumed in the rare elevated-fallback branch. `deleteMeasured` already returns the freed bytes on success. Move the pre-measurement into the fallback path so the happy path walks the bundle twice (size + unlink) instead of three times.

**Files:**
- Modify: `Sources/AutoCleanMacCore/AppPurger.swift` (around lines 85-114)
- Test: `Tests/AutoCleanMacCoreTests/AppPurgerTests.swift` (existing tests pin both the happy path and the elevated-fallback byte reporting — must stay green)

- [ ] **Step 1: Read the purge bundle-deletion block and confirm test coverage**

Run: `sed -n '85,115p' Sources/AutoCleanMacCore/AppPurger.swift`
Run: `swift test --filter AppPurgerTests`
Expected: PASS now. Note specifically the test that asserts `bytesFreed` is non-zero **after the elevated fallback** (per memory: this was a fixed bug — `recursiveMetrics` must be captured *before* the elevated removal in that branch). The refactor must keep pre-measurement for the elevated path.

- [ ] **Step 2: Move pre-measurement into the fallback branch**

Replace the eager pre-measure + delete block. Current shape (around lines 91-114):

```swift
        let preDeleteMetrics = (try? SafeDeleter.recursiveMetrics(at: appURL)) ?? DeletionMetrics(bytesFreed: 0, itemsDeleted: 0)
        do {
            let metrics = try deleter.deleteMeasured(appURL, withinRoot: appsRoot)
            bytes += metrics.bytesFreed
            items += metrics.itemsDeleted
        } catch {
            // elevated fallback ... uses preDeleteMetrics.bytesFreed
        }
```

Replace with (measure lazily, only when entering the fallback, BEFORE the elevated removal):

```swift
        do {
            let metrics = try deleter.deleteMeasured(appURL, withinRoot: appsRoot)
            bytes += metrics.bytesFreed
            items += metrics.itemsDeleted
        } catch {
            // Measure now, before the elevated removal destroys the bundle.
            let preDeleteMetrics = (try? SafeDeleter.recursiveMetrics(at: appURL))
                ?? DeletionMetrics(bytesFreed: 0, itemsDeleted: 0)
            // ... existing elevated-fallback body, using preDeleteMetrics.bytesFreed
        }
```

Preserve the exact elevated-fallback body that follows (the `elevatedRemove` call, `fileExists` re-check, and `PurgeFailure` recording) — only the *placement* of the `preDeleteMetrics` line moves.

- [ ] **Step 3: Run AppPurgerTests**

Run: `swift test --filter AppPurgerTests`
Expected: PASS — happy path bytes from `deleteMeasured`, elevated-fallback bytes from the moved pre-measure.

- [ ] **Step 4: Run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/AppPurger.swift
git commit -m "perf: pre-measure app bundle only on elevated-fallback path"
```

---

## Task 8: Cap `ConsoleViewModel.lines` and use `LazyVStack`

`ConsoleViewModel.lines` (`ConsoleView.swift:10`) grows unbounded and renders in a non-lazy `VStack` (`:109`), keeping every `Text` materialized. Cap the buffer to the last N lines and switch to `LazyVStack`.

**Files:**
- Modify: `Sources/AutoCleanMac/ConsoleView.swift:10`, `:109`

This is a UI/view-model change; verify by build + full suite (`AppDelegateTests` exercises the console handlers).

- [ ] **Step 1: Add a capped append to the view model**

In `Sources/AutoCleanMac/ConsoleView.swift`, add a constant and an append helper to `ConsoleViewModel`. After line 10 (`@Published var lines: [Line] = []`), keep the property and add right after the property block (e.g. after line 26's `finished` — but note Task 11 removes `finished`; place this near `lines`):

```swift
    /// Hard cap so a long run can't grow the console buffer without bound.
    static let maxLines = 500

    func appendLine(_ line: Line) {
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }
```

- [ ] **Step 2: Route existing appends through `appendLine`**

Run: `grep -n "\.lines.append" Sources/AutoCleanMac/AppDelegate.swift`
For each hit (around `AppDelegate.swift:284, 295, 301`), replace `model.lines.append(<x>)` with `model.appendLine(<x>)`. Leave the O(n) `lastIndex(where:)` logic at line ~290 as-is (out of scope; capping bounds it).

- [ ] **Step 3: Switch the console list to `LazyVStack`**

In `Sources/AutoCleanMac/ConsoleView.swift`, line 109, replace:

```swift
                    VStack(alignment: .leading, spacing: 4) {
```

with:

```swift
                    LazyVStack(alignment: .leading, spacing: 4) {
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMac/ConsoleView.swift Sources/AutoCleanMac/AppDelegate.swift
git commit -m "perf: cap console line buffer and lazily render console rows"
```

---

## Task 9: Stop recomputing expensive work in SwiftUI bodies

`BrowsersTab` re-probes LaunchServices for every browser on each `body` evaluation (`BrowsersTab.swift:7-9`), and `OrphanCleanerTab` allocates a `ByteCountFormatter` per row (`OrphanCleanerTab.swift:40`). Cache the browser probe in `@State`; use a `static let` formatter like the sibling tabs.

**Files:**
- Modify: `Sources/AutoCleanMac/UI/Tabs/BrowsersTab.swift:7-9` (+ add `.task`/`@State`)
- Modify: `Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift:40`

Verify by build + full suite.

- [ ] **Step 1: Read both tabs to capture exact surrounding code**

Run: `sed -n '1,45p' Sources/AutoCleanMac/UI/Tabs/BrowsersTab.swift`
Run: `sed -n '1,70p' Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift`
Note the `struct` names, the existing `body`, and where `installed` is referenced (`BrowsersTab.swift:13, 41`).

- [ ] **Step 2: Cache the browser probe in `@State`**

In `Sources/AutoCleanMac/UI/Tabs/BrowsersTab.swift`, replace the computed property (lines 7-9):

```swift
    private var installed: [BrowserIdentity] {
        BrowserIdentity.allCases.filter { $0.isInstalled() }
    }
```

with a `@State` cache populated once on appear:

```swift
    @State private var installed: [BrowserIdentity] = []
```

Then add a `.task` modifier to the tab's root view (attach to the outermost container returned by `body`):

```swift
        .task {
            if installed.isEmpty {
                installed = BrowserIdentity.allCases.filter { $0.isInstalled() }
            }
        }
```

(Keep the `installed.isEmpty` / `ForEach(installed)` read sites unchanged — they now read the cached `@State`.)

- [ ] **Step 3: Use a shared static formatter in OrphanCleanerTab**

In `Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift`, add a static formatter to the struct (match the sibling pattern from `ScannerTab.swift:54-59`):

```swift
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()
```

Then replace the per-row allocation at line 40:

```swift
                        Text(ByteCountFormatter().string(fromByteCount: path.sizeBytes))
```

with (use the exact size property name observed in Step 1):

```swift
                        Text(Self.bytesFormatter.string(fromByteCount: path.sizeBytes))
```

This also fixes a rendering inconsistency: the per-row formatter omitted `.useAll`/`.file`.

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMac/UI/Tabs/BrowsersTab.swift Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift
git commit -m "perf: cache browser probe in @State and reuse byte formatter in orphan rows"
```

---

## Task 10: Extract a shared `ByteFormatting` helper (deduplicate 5+ formatters)

The identical `ByteCountFormatter` (`.useAll` + `.file`) is declared in `StatisticsTab` (2×), `ScannerTab`, `UninstallerTab`, `ConsoleView`, and now `OrphanCleanerTab`. Centralize one helper in Core and route all sites through it.

**Files:**
- Create: `Sources/AutoCleanMacCore/ByteFormatting.swift`
- Modify: `Sources/AutoCleanMac/ConsoleView.swift:37-50`, `Sources/AutoCleanMac/UI/Tabs/StatisticsTab.swift:7-12, 64-69`, `ScannerTab.swift:54-59`, `UninstallerTab.swift:48-53`, `OrphanCleanerTab.swift` (from Task 9)
- Test: `Tests/AutoCleanMacCoreTests/ByteFormattingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AutoCleanMacCoreTests/ByteFormattingTests.swift`:

```swift
import XCTest
@testable import AutoCleanMacCore

final class ByteFormattingTests: XCTestCase {
    func test_formats_bytes_with_file_count_style() {
        // 1 KB in .file style (1000-based) renders as "1 KB".
        XCTAssertEqual(ByteFormatting.string(1_000), "1 KB")
    }

    func test_zero_is_stable() {
        XCTAssertEqual(ByteFormatting.string(0), ByteFormatting.string(0))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ByteFormattingTests`
Expected: FAIL — `cannot find 'ByteFormatting' in scope`

- [ ] **Step 3: Create the helper**

Create `Sources/AutoCleanMacCore/ByteFormatting.swift`:

```swift
import Foundation

/// Single source of truth for human-readable byte sizes across the app.
public enum ByteFormatting {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    public static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ByteFormattingTests`
Expected: PASS. (If the platform renders `1_000` differently, adjust the expected string in Step 1 to match the actual `.file`-style output, then re-run.)

- [ ] **Step 5: Route UI sites through the helper**

For each file, delete its local `static let bytesFormatter` block and replace `Self.bytesFormatter.string(fromByteCount: X)` calls with `ByteFormatting.string(X)`:
- `Sources/AutoCleanMac/ConsoleView.swift` — remove lines 37-42; replace `Self.bytesFormatter.string(...)` at `:45` and `:49` with `ByteFormatting.string(currentRunBytesFreed)` / `ByteFormatting.string(lifetimeBytesFreed)`.
- `Sources/AutoCleanMac/UI/Tabs/StatisticsTab.swift` — remove both formatter blocks (`:7-12`, `:64-69`); replace call sites.
- `Sources/AutoCleanMac/UI/Tabs/ScannerTab.swift` — remove `:54-59`; replace `Self.bytesFormatter.string(...)` at `:78`.
- `Sources/AutoCleanMac/UI/Tabs/UninstallerTab.swift` — remove `:48-53`; replace call sites. Reconcile the `<= 0 ? "0 KB"` special case at `:220-222` to just `ByteFormatting.string(bytes)` for consistency.
- `Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift` — remove the `static let bytesFormatter` added in Task 9; use `ByteFormatting.string(path.sizeBytes)`.

Each of these files already `import AutoCleanMacCore` (or reaches it via models). If a file fails to resolve `ByteFormatting`, add `import AutoCleanMacCore` at the top.

- [ ] **Step 6: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/AutoCleanMacCore/ByteFormatting.swift Tests/AutoCleanMacCoreTests/ByteFormattingTests.swift Sources/AutoCleanMac/ConsoleView.swift Sources/AutoCleanMac/UI/Tabs/StatisticsTab.swift Sources/AutoCleanMac/UI/Tabs/ScannerTab.swift Sources/AutoCleanMac/UI/Tabs/UninstallerTab.swift Sources/AutoCleanMac/UI/Tabs/OrphanCleanerTab.swift
git commit -m "refactor: centralize byte formatting in ByteFormatting helper"
```

---

## Task 11: Dead-code sweep

Remove verified-dead code: orphaned root scratch files, write-only `@Published` properties, an unused method, an unused computed property, and a stale comment.

**Files:**
- Delete: `test_scanner.swift`, `test_symbols.swift`, `test_memory.sh`, `test_output.txt`
- Modify: `Sources/AutoCleanMac/ConsoleView.swift` (remove `statusColor:14`, `finished:26`)
- Modify: `Sources/AutoCleanMac/AppDelegate.swift` (remove assignments to those + method `openInDefaultEditor:406`)
- Modify: `Sources/AutoCleanMac/UI/Components/SettingsComponents.swift` (remove `overviewSummary:169-178`)
- Modify: `Sources/AutoCleanMac/UI/Tabs/ScannerTab.swift:134-137` (stale comment)

- [ ] **Step 1: Delete the orphaned root files (not in Package.swift, never built)**

```bash
git rm test_scanner.swift test_symbols.swift test_memory.sh test_output.txt
```

- [ ] **Step 2: Remove write-only `@Published var finished` and its assignments**

Confirm no reads first:
Run: `grep -rn "\.finished" Sources/AutoCleanMac/ | grep -v "= "` — expect only assignment sites, no reads.
In `Sources/AutoCleanMac/ConsoleView.swift`, delete line 26 (`@Published var finished: Bool = false`).
In `Sources/AutoCleanMac/AppDelegate.swift`, delete the two assignment lines (`model.finished = ...` at ~`:264` and `:354`). Find them with `grep -n "\.finished" Sources/AutoCleanMac/AppDelegate.swift`.

- [ ] **Step 3: Remove write-only `@Published var statusColor` and its assignments**

Confirm no reads: `grep -rn "statusColor" Sources/AutoCleanMac/` — expect only the declaration + 4 assignments in `AppDelegate.swift` (`:366, :369, :372, :378`), none in any view `body`.
In `Sources/AutoCleanMac/ConsoleView.swift`, delete line 14 (`@Published var statusColor: Color = .green`).
In `Sources/AutoCleanMac/AppDelegate.swift`, delete the 4 `model.statusColor = ...` assignment lines.

- [ ] **Step 4: Remove unused `openInDefaultEditor(_:)`**

Confirm zero callers: `grep -rn "openInDefaultEditor" Sources/ Tests/` — expect only the definition.
In `Sources/AutoCleanMac/AppDelegate.swift`, delete the entire `openInDefaultEditor` method (starts ~line 406; delete from its `private func openInDefaultEditor` through its closing `}`).

- [ ] **Step 5: Remove unused `DeleteMode.overviewSummary`**

Confirm zero references: `grep -rn "overviewSummary" Sources/ Tests/` — expect only the definition.
In `Sources/AutoCleanMac/UI/Components/SettingsComponents.swift`, delete the `overviewSummary` computed property (lines 169-178).

- [ ] **Step 6: Remove the stale comment**

In `Sources/AutoCleanMac/UI/Tabs/ScannerTab.swift`, delete the obsolete comment lines 134-137 (the Polish "reflection lub przez wymuszenie" musing) — the working call is on line 138.

- [ ] **Step 7: Build and run the full suite**

Run: `swift build && swift test`
Expected: PASS, 0 failures. (If the compiler flags an unused-result or missing-symbol error, a "dead" item was actually referenced — re-check that specific grep before removing.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: remove dead code, orphaned scratch files, and stale comments"
```

---

## Out of scope (logged for a future pass)

These audit findings are real but deferred — larger refactors or lower ROI, not blocking:
- **Task `run()` boilerplate** — a shared `sweep(roots:filter:)` helper to collapse the ~6 near-identical `CleanupTask` bodies. Big LOC win, but touches every task; do behind the existing task tests as its own plan.
- **`ShellRunner`** — unify the `Process` + `/dev/null` boilerplate across the 5 shell clients (`PreferencesDaemonClient`, `LaunchAgentClient`, `LoginItemsClient`, `LaunchServicesClient`, `AppTerminator`).
- **SwiftUI modifier dedup** — `.sectionFooter()` (footnote/secondary chain, ~10×), `.windowBackground()` (6×), `SteppedValueRow`, and the byte-identical `OverviewNote`/`ReminderModeNote`.
- **`recursiveMetrics` allocated-size switch** (`.fileSizeKey` → `.totalFileAllocatedSizeKey`) — deliberately NOT done: it changes user-reported "freed" byte counts and would diverge from the single-file path's logical size. Treat as a product decision, not a refactor.
- **`CleanupEngine` task parallelism** — deferred: some tasks shell out and live deletion raises ordering/safety questions.
- **`AppProtectionGuard.wildcardMatch`** fast-path for `*`-free patterns; `InstalledAppRegistry` `fileExists(isDirectory:)` → prefetched `.isDirectoryKey`.

---

## Self-Review Notes

- **Spec coverage:** Tasks 1-3 cover the three correctness findings (mode inconsistency, prefix bug, main-thread freeze). Tasks 4-7 cover the verified perf findings (symlink lstat, serial scanners ×2, triple-measure). Tasks 8-9 cover UI perf (unbounded buffer, body recompute). Task 10 covers the top duplication. Task 11 covers all dead-code findings. Remaining low-priority duplication is explicitly logged as out-of-scope.
- **Type consistency:** `safeDeleterMode`/`jsonValue` (on `DeleteMode`) and `label` (on `SafeDeleter.Mode`) are defined in Task 1 and reused verbatim thereafter. `URL.isWithin(_:)` defined in Task 2, reused in `AppPurger`. `ByteFormatting.string(_:)` defined in Task 10, reused across tabs. `appendLine(_:)`/`maxLines` defined in Task 8.
- **TDD safety nets:** Behavioral changes in Core (Tasks 1, 2, 4, 5, 6, 7, 10) are each pinned by a test written before the change. UI-only changes (Tasks 3, 8, 9, 11) rely on build + full suite since they have no unit seam — noted per task.

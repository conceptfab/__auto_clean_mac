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

    // MARK: - SystemTempTask

    func test_system_temp_deletes_old_files_only() async throws {
        let temp = tempDir.appendingPathComponent("temp-root")
        try Fixtures.makeFile(at: temp.appendingPathComponent("old.tmp"),   size: 80, ageInDays: 30)
        try Fixtures.makeFile(at: temp.appendingPathComponent("fresh.tmp"), size: 80, ageInDays: 1)
        let task = SystemTempTask(isEnabled: true, rootOverride: temp)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 80)
    }

    // MARK: - UserCachesTask

    func test_user_caches_deletes_all_files_regardless_of_mtime() async throws {
        let caches = tempDir.appendingPathComponent("Library/Caches")
        try Fixtures.makeFile(at: caches.appendingPathComponent("a/x.bin"),  size: 100, ageInDays: 0)
        try Fixtures.makeFile(at: caches.appendingPathComponent("b/y.bin"),  size: 200, ageInDays: 30)
        let task = UserCachesTask(isEnabled: true, isBundleIDRunning: { _ in false })
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 300)
    }

    func test_user_caches_skips_protected_top_level_directories() async throws {
        let caches = tempDir.appendingPathComponent("Library/Caches")
        try Fixtures.makeFile(at: caches.appendingPathComponent("com.apple.Safari/Cache.db"), size: 120, ageInDays: 30)
        try Fixtures.makeFile(at: caches.appendingPathComponent("safe.vendor.cache/item.bin"), size: 80, ageInDays: 30)

        let task = UserCachesTask(isEnabled: true, isBundleIDRunning: { _ in false })
        let result = await task.run(context: makeContext())

        XCTAssertEqual(result.bytesFreed, 80)
        XCTAssertTrue(FileManager.default.fileExists(atPath: caches.appendingPathComponent("com.apple.Safari/Cache.db").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: caches.appendingPathComponent("safe.vendor.cache/item.bin").path))
    }

    func test_user_caches_skips_bundle_identifier_for_running_app() async throws {
        let caches = tempDir.appendingPathComponent("Library/Caches")
        try Fixtures.makeFile(at: caches.appendingPathComponent("com.example.Editor/cache.bin"), size: 64, ageInDays: 30)
        try Fixtures.makeFile(at: caches.appendingPathComponent("com.example.Helper/cache.bin"), size: 32, ageInDays: 30)

        let task = UserCachesTask(isEnabled: true, isBundleIDRunning: { $0 == "com.example.Editor" })
        let result = await task.run(context: makeContext())

        XCTAssertEqual(result.bytesFreed, 32)
        XCTAssertTrue(FileManager.default.fileExists(atPath: caches.appendingPathComponent("com.example.Editor/cache.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: caches.appendingPathComponent("com.example.Helper/cache.bin").path))
    }

    func test_user_caches_skips_whitelisted_bundle_identifiers() async throws {
        let caches = tempDir.appendingPathComponent("Library/Caches")
        try Fixtures.makeFile(at: caches.appendingPathComponent("com.spotify.client/cache.bin"), size: 100, ageInDays: 30)
        try Fixtures.makeFile(at: caches.appendingPathComponent("com.example.other/cache.bin"), size: 50, ageInDays: 30)

        let task = UserCachesTask(
            isEnabled: true,
            isBundleIDRunning: { _ in false },
            whitelistedBundleIDs: ["com.spotify.client"]
        )
        let result = await task.run(context: makeContext())

        XCTAssertEqual(result.bytesFreed, 50)
        XCTAssertTrue(FileManager.default.fileExists(atPath: caches.appendingPathComponent("com.spotify.client/cache.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: caches.appendingPathComponent("com.example.other/cache.bin").path))
    }

    // MARK: - DevCachesTask

    func test_dev_caches_deletes_derived_data_and_npm_and_pip() async throws {
        let derived = tempDir.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        try Fixtures.makeFile(at: derived.appendingPathComponent("proj-abc/x"), size: 200, ageInDays: 30)
        try Fixtures.makeFile(at: derived.appendingPathComponent("proj-abc/y"), size: 50,  ageInDays: 1)

        let npm = tempDir.appendingPathComponent(".npm/_cacache")
        try Fixtures.makeFile(at: npm.appendingPathComponent("content-v2/abc"), size: 300, ageInDays: 30)

        let pip = tempDir.appendingPathComponent("Library/Caches/pip")
        try Fixtures.makeFile(at: pip.appendingPathComponent("wheels/a"), size: 150, ageInDays: 30)

        let task = DevCachesTask(
            isEnabled: true,
            runBrew: false,
            brewExecutable: { nil },
            runBrewProcess: { _, _, _ in
                XCTFail("No native process should run in this filesystem-only test")
                return DevCachesTask.ProcessOutcome(status: 1, stdout: "", stderr: "", timedOut: false)
            }
        )
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 200 + 300 + 150)
    }

    func test_dev_caches_skips_brew_cleanup_when_deletion_mode_is_dry_run() async throws {
        var didRunBrew = false
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: true,
            brewExecutable: { "/opt/homebrew/bin/brew" },
            runBrewProcess: { _, _, _ in
                didRunBrew = true
                return DevCachesTask.ProcessOutcome(status: 0, stdout: "freed 1GB", stderr: "", timedOut: false)
            }
        )
        let context = CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            deletionMode: .dryRun,
            logger: logger,
            homeDirectory: tempDir
        )

        let result = await task.run(context: context)

        XCTAssertFalse(didRunBrew)
        XCTAssertEqual(result.bytesFreed, 0)
        XCTAssertTrue(result.warnings.contains { $0.contains("brew cleanup pominięty") })
    }

    func test_dev_caches_skips_brew_cleanup_when_deletion_mode_is_trash() async throws {
        var didRunBrew = false
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: true,
            brewExecutable: { "/opt/homebrew/bin/brew" },
            runBrewProcess: { _, _, _ in
                didRunBrew = true
                return DevCachesTask.ProcessOutcome(status: 0, stdout: "freed 1GB", stderr: "", timedOut: false)
            }
        )
        let context = CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .trash, logger: logger),
            deletionMode: .trash,
            logger: logger,
            homeDirectory: tempDir
        )

        let result = await task.run(context: context)

        XCTAssertFalse(didRunBrew)
        XCTAssertEqual(result.bytesFreed, 0)
        XCTAssertTrue(result.warnings.contains { $0.contains("brew cleanup pominięty") })
    }

    func test_dev_caches_runs_brew_cleanup_when_deletion_mode_is_live() async throws {
        var receivedArgs: [String] = []
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: true,
            brewExecutable: { "/opt/homebrew/bin/brew" },
            runBrewProcess: { _, args, _ in
                receivedArgs = args
                return DevCachesTask.ProcessOutcome(status: 0, stdout: "freed 2MB", stderr: "", timedOut: false)
            }
        )
        let context = CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .live, logger: logger),
            deletionMode: .live,
            logger: logger,
            homeDirectory: tempDir
        )

        let result = await task.run(context: context)

        XCTAssertEqual(receivedArgs, ["cleanup", "--prune=7"])
        XCTAssertEqual(result.bytesFreed, 2 * 1_048_576)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func test_dev_caches_skips_native_cleanup_when_deletion_mode_is_dry_run() async throws {
        var didRun = false
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: false,
            brewExecutable: { nil },
            toolExecutable: { _ in "/usr/bin/tool" },
            runBrewProcess: { _, _, _ in
                didRun = true
                return DevCachesTask.ProcessOutcome(status: 0, stdout: "", stderr: "", timedOut: false)
            },
            nativeToolCommands: [
                DevCachesTask.NativeToolCommand(label: "test cache", executableName: "tool", arguments: ["clean"])
            ]
        )
        let context = CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            deletionMode: .dryRun,
            logger: logger,
            homeDirectory: tempDir
        )

        let result = await task.run(context: context)

        XCTAssertFalse(didRun)
        XCTAssertTrue(result.warnings.contains { $0.contains("native devtools cleanup pominięty") })
    }

    func test_dev_caches_skips_native_cleanup_when_deletion_mode_is_trash() async throws {
        var didRun = false
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: false,
            brewExecutable: { nil },
            toolExecutable: { _ in "/usr/bin/tool" },
            runBrewProcess: { _, _, _ in
                didRun = true
                return DevCachesTask.ProcessOutcome(status: 0, stdout: "", stderr: "", timedOut: false)
            },
            nativeToolCommands: [
                DevCachesTask.NativeToolCommand(label: "test cache", executableName: "tool", arguments: ["clean"])
            ]
        )
        let context = CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .trash, logger: logger),
            deletionMode: .trash,
            logger: logger,
            homeDirectory: tempDir
        )

        let result = await task.run(context: context)

        XCTAssertFalse(didRun)
        XCTAssertTrue(result.warnings.contains { $0.contains("native devtools cleanup pominięty") })
    }

    func test_dev_caches_runs_native_cleanup_when_deletion_mode_is_live() async throws {
        var receivedPath = ""
        var receivedArgs: [String] = []
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: false,
            brewExecutable: { nil },
            toolExecutable: { name in name == "tool" ? "/usr/bin/tool" : nil },
            runBrewProcess: { path, args, _ in
                receivedPath = path
                receivedArgs = args
                return DevCachesTask.ProcessOutcome(status: 0, stdout: "", stderr: "", timedOut: false)
            },
            nativeToolCommands: [
                DevCachesTask.NativeToolCommand(label: "test cache", executableName: "tool", arguments: ["clean"])
            ]
        )

        let result = await task.run(context: makeContext())

        XCTAssertEqual(receivedPath, "/usr/bin/tool")
        XCTAssertEqual(receivedArgs, ["clean"])
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func test_dev_caches_warns_when_native_tool_is_missing() async throws {
        var didRun = false
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: false,
            brewExecutable: { nil },
            toolExecutable: { _ in nil },
            runBrewProcess: { _, _, _ in
                didRun = true
                return DevCachesTask.ProcessOutcome(status: 0, stdout: "", stderr: "", timedOut: false)
            },
            nativeToolCommands: [
                DevCachesTask.NativeToolCommand(label: "test cache", executableName: "tool", arguments: ["clean"])
            ]
        )

        let result = await task.run(context: makeContext())

        XCTAssertFalse(didRun)
        XCTAssertTrue(result.warnings.contains { $0.contains("narzędzie niedostępne") })
    }

    func test_dev_caches_warns_when_native_cleanup_fails() async throws {
        let task = DevCachesTask(
            isEnabled: true,
            runBrew: false,
            brewExecutable: { nil },
            toolExecutable: { _ in "/usr/bin/tool" },
            runBrewProcess: { _, _, _ in
                DevCachesTask.ProcessOutcome(status: 42, stdout: "", stderr: "nope", timedOut: false)
            },
            nativeToolCommands: [
                DevCachesTask.NativeToolCommand(label: "test cache", executableName: "tool", arguments: ["clean"])
            ]
        )

        let result = await task.run(context: makeContext())

        XCTAssertTrue(result.warnings.contains { $0.contains("test cache exited 42") })
    }

    // MARK: - ProjectArtifactsTask

    func test_project_artifacts_task_skipped_when_disabled() async throws {
        let task = ProjectArtifactsTask(isEnabled: false, searchRoots: [tempDir])

        let result = await task.run(context: makeContext())

        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.skipReason, "disabled")
    }

    func test_project_artifacts_deletes_supported_artifacts_only() async throws {
        let projects = tempDir.appendingPathComponent("Projects")
        let app = projects.appendingPathComponent("App")
        try Fixtures.makeFile(at: app.appendingPathComponent(".next/cache/chunk.bin"), size: 100)
        try Fixtures.makeFile(at: app.appendingPathComponent("__pycache__/main.pyc"), size: 50)
        try Fixtures.makeFile(at: app.appendingPathComponent(".dart_tool/state.bin"), size: 70)
        try Fixtures.makeFile(at: app.appendingPathComponent(".pytest_cache/v/cache/nodeids"), size: 30)
        try Fixtures.makeFile(at: app.appendingPathComponent(".mypy_cache/3.12/mod.json"), size: 40)
        try Fixtures.makeFile(at: app.appendingPathComponent(".ruff_cache/content"), size: 60)
        try Fixtures.makeFile(at: app.appendingPathComponent("node_modules/.cache/bundler.bin"), size: 80)
        try Fixtures.makeFile(at: app.appendingPathComponent("Sources/main.swift"), size: 1_000)
        try Fixtures.makeFile(at: app.appendingPathComponent("package-lock.json"), size: 1_000)
        try Fixtures.makeFile(at: app.appendingPathComponent("node_modules/pkg/index.js"), size: 1_000)

        let task = ProjectArtifactsTask(isEnabled: true, searchRoots: [projects])
        let result = await task.run(context: makeContext())

        XCTAssertEqual(result.bytesFreed, 100 + 50 + 70 + 30 + 40 + 60 + 80)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent(".next/cache").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("__pycache__").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("node_modules/.cache").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Sources/main.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("package-lock.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("node_modules/pkg/index.js").path))
    }

    func test_project_artifacts_skips_empty_pycache_without_bytecode() async throws {
        let projects = tempDir.appendingPathComponent("Projects")
        let pycache = projects.appendingPathComponent("App/__pycache__")
        try Fixtures.makeFile(at: pycache.appendingPathComponent("notes.txt"), size: 100)

        let task = ProjectArtifactsTask(isEnabled: true, searchRoots: [projects])
        let result = await task.run(context: makeContext())

        XCTAssertEqual(result.bytesFreed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pycache.appendingPathComponent("notes.txt").path))
    }

    func test_project_artifacts_respects_excluded_paths() async throws {
        let projects = tempDir.appendingPathComponent("Projects")
        let cache = projects.appendingPathComponent("App/.next/cache")
        try Fixtures.makeFile(at: cache.appendingPathComponent("chunk.bin"), size: 100)
        let context = CleanupContext(
            retentionDays: 7,
            deleter: deleter,
            logger: logger,
            homeDirectory: tempDir,
            excludedPaths: [projects.appendingPathComponent("App")]
        )

        let task = ProjectArtifactsTask(isEnabled: true, searchRoots: [projects])
        let result = await task.run(context: context)

        XCTAssertEqual(result.bytesFreed, 0)
        XCTAssertTrue(result.warnings.contains { $0.contains("excluded path") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.appendingPathComponent("chunk.bin").path))
    }

    func test_project_artifacts_does_not_follow_symlinked_roots_or_candidates_outside_root() async throws {
        let projects = tempDir.appendingPathComponent("Projects")
        let outside = tempDir.appendingPathComponent("Outside")
        try Fixtures.makeFile(at: outside.appendingPathComponent(".next/cache/outside.bin"), size: 100)
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("App/.next"), withIntermediateDirectories: true)
        try Fixtures.makeSymlink(
            at: projects.appendingPathComponent("App/.next/cache"),
            pointingTo: outside.appendingPathComponent(".next/cache")
        )

        let task = ProjectArtifactsTask(isEnabled: true, searchRoots: [projects])
        let result = await task.run(context: makeContext())

        XCTAssertEqual(result.bytesFreed, 0)
        XCTAssertTrue(result.warnings.contains { $0.contains("escapes root") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent(".next/cache/outside.bin").path))
    }

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

    func test_downloads_respects_excluded_paths() async throws {
        let dl = tempDir.appendingPathComponent("Downloads")
        let excluded = dl.appendingPathComponent("keep.dmg")
        try Fixtures.makeFile(at: dl.appendingPathComponent("old-installer.dmg"), size: 500, ageInDays: 30)
        try Fixtures.makeFile(at: excluded, size: 400, ageInDays: 30)
        let task = DownloadsTask(isEnabled: true)
        let context = CleanupContext(
            retentionDays: 7,
            deleter: deleter,
            logger: logger,
            homeDirectory: tempDir,
            excludedPaths: [excluded]
        )

        let result = await task.run(context: context)

        XCTAssertEqual(result.bytesFreed, 500)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dl.appendingPathComponent("old-installer.dmg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: excluded.path))
        XCTAssertEqual(result.warnings.count, 1)
    }

    func test_downloads_default_off() async throws {
        let task = DownloadsTask(isEnabled: false)
        let result = await task.run(context: makeContext())
        XCTAssertTrue(result.skipped)
    }
}

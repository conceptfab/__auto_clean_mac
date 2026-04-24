import Foundation

public enum ConfigWriter {
    public enum WriteError: Error, CustomStringConvertible {
        case serializationFailed(underlying: Error)

        public var description: String {
            switch self {
            case .serializationFailed(let e): return "Config serialization failed: \(e)"
            }
        }
    }

    /// Serializuje `Config` do pretty-printed JSON i zapisuje atomowo do `url`.
    /// Tworzy brakujące katalogi nadrzędne.
    public static func write(_ config: Config, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let tasks: [String: Any] = [
            "user_caches":    config.tasks.userCaches,
            "system_temp":    config.tasks.systemTemp,
            "trash":          config.tasks.trash,
            "ds_store":       config.tasks.dsStore,
            "user_logs":      config.tasks.userLogs,
            "dev_caches":     config.tasks.devCaches,
            "homebrew_cleanup": config.tasks.homebrewCleanup,
            "downloads":      config.tasks.downloads,
            // Legacy: zapisujemy false — nowe instalacje używają sekcji browsers poniżej.
            "browser_caches": false,
        ]

        var browsers: [String: Any] = [:]
        for (browser, prefs) in config.browsers {
            var entry: [String: Any] = [:]
            for type in BrowserDataType.allCases {
                entry[type.rawValue] = prefs.contains(type)
            }
            browsers[browser.rawValue] = entry
        }

        let deleteModeJson: String
        switch config.deleteMode {
        case .trash:  deleteModeJson = "trash"
        case .live:   deleteModeJson = "live"
        case .dryRun: deleteModeJson = "dry_run"
        }

        let reminderModeJson: String
        switch config.reminder.mode {
        case .off:       reminderModeJson = "off"
        case .remind:    reminderModeJson = "remind"
        case .autoClean: reminderModeJson = "auto_clean"
        }

        let root: [String: Any] = [
            "retention_days": config.retentionDays,
            "delete_mode":    deleteModeJson,
            "reminder": [
                "interval_hours": config.reminder.intervalHours,
                "mode": reminderModeJson,
            ],
            "window": [
                "fade_in_ms":    config.window.fadeInMs,
                "hold_after_ms": config.window.holdAfterMs,
                "fade_out_ms":   config.window.fadeOutMs,
            ],
            "tasks":    tasks,
            "browsers": browsers,
            "excluded_paths": config.excludedPaths,
            "whitelisted_cache_apps": config.whitelistedCacheApps,
            "global_shortcut_enabled": config.globalShortcutEnabled
        ]

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw WriteError.serializationFailed(underlying: error)
        }
        try data.write(to: url, options: .atomic)
    }
}

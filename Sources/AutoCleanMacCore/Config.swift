import Foundation

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
}

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
    public var browsers: [BrowserIdentity: BrowserPreferences]
    public var deleteMode: DeleteMode

    public static let `default` = Config(
        retentionDays: 7, window: .default, tasks: .default,
        browsers: [:],
        deleteMode: .trash
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
        if let raw = json["delete_mode"] as? String {
            if let mode = DeleteMode.parse(raw) {
                config.deleteMode = mode
            } else {
                warn("Nieznana wartość delete_mode: \"\(raw)\" — używam wartości domyślnej (\(config.deleteMode.rawValue))")
            }
        }
        return config
    }
}

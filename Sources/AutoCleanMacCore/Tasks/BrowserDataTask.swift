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
        guard isEnabled else {
            logFinish(context: context, result: TaskResult(skipped: true, skipReason: "disabled"))
            return TaskResult(skipped: true, skipReason: "disabled")
        }

        let roots = browser.profileRoots(homeDirectory: context.homeDirectory)
            .filter { context.fileManager.fileExists(atPath: $0.path) }
        guard !roots.isEmpty else {
            let result = TaskResult(skipped: true, skipReason: "no browser profile directories")
            logFinish(context: context, result: result)
            return result
        }

        if requiresApplicationSupportAccess, isBlockedByFullDiskAccess(context: context) {
            let result = TaskResult(
                bytesFreed: 0,
                warnings: [Self.fullDiskAccessWarning(for: browser)],
                skipped: true,
                skipReason: "full_disk_access_required"
            )
            logFinish(context: context, result: result)
            return result
        }

        if isBrowserRunning(browser) {
            let result = TaskResult(
                bytesFreed: 0,
                warnings: ["\(browser.displayName) ma otwarte okna — pomijam (zamknij przeglądarkę żeby wyczyścić)"],
                skipped: true,
                skipReason: "browser running"
            )
            logFinish(context: context, result: result)
            return result
        }

        var freed: Int64 = 0
        var itemsDeleted = 0
        var warnings: [String] = []

        var profilesToClean: [URL] = []
        if browser.hasProfiles {
            for profilesRoot in roots {
                do {
                    profilesToClean.append(contentsOf: try listProfileDirs(in: profilesRoot, fileManager: context.fileManager))
                } catch {
                    // Na nowym macOS katalogi danych Brave/Chrome są chronione przez TCC.
                    // Bez uprawnień `contentsOfDirectory` rzuca — NIE wolno tego cicho połknąć,
                    // bo użytkownik dostałby „0 B” bez wyjaśnienia dlaczego nic się nie wyczyściło.
                    if Self.isPermissionError(error) {
                        warnings.append("\(browser.displayName): brak dostępu do danych przeglądarki — nadaj aplikacji Pełny dostęp do dysku (Full Disk Access) w Ustawieniach systemowych › Prywatność i bezpieczeństwo")
                    } else {
                        warnings.append("\(profilesRoot.lastPathComponent): \(error)")
                    }
                }
            }
        } else {
            // Safari nie ma profili
            profilesToClean = roots
        }
        
        for profile in profilesToClean {
            if browser.isChromium && dataType == .history {
                for preferencesName in ["Preferences", "Secure Preferences"] {
                    let preferencesURL = profile.appendingPathComponent(preferencesName)
                    guard context.fileManager.fileExists(atPath: preferencesURL.path) else { continue }
                    do {
                        _ = try ChromiumPreferencesScrubber.scrubSessionRestoreData(
                            at: preferencesURL,
                            fileManager: context.fileManager
                        )
                    } catch {
                        if Self.isPermissionError(error) {
                            warnings.append("\(browser.displayName): brak dostępu do \(preferencesName) — nadaj aplikacji Pełny dostęp do dysku (Full Disk Access) w Ustawieniach systemowych › Prywatność i bezpieczeństwo")
                        } else {
                            warnings.append("\(preferencesName): \(error)")
                        }
                    }
                }
            }

            let paths = itemsToDelete(in: profile)
            for url in paths where context.fileManager.fileExists(atPath: url.path) {
                do {
                    let metrics = try context.deleteMeasured(url, withinRoot: profile)
                    freed += metrics.bytesFreed
                    itemsDeleted += metrics.itemsDeleted
                } catch {
                    warnings.append("\(url.lastPathComponent): \(error)")
                }
            }
        }
        let result = TaskResult(bytesFreed: freed, itemsDeleted: itemsDeleted, warnings: warnings)
        logFinish(context: context, result: result)
        return result
    }

    private var requiresApplicationSupportAccess: Bool {
        switch dataType {
        case .cache:
            return false
        case .cookies, .history:
            return true
        }
    }

    private func isBlockedByFullDiskAccess(context: CleanupContext) -> Bool {
        let protectedRoots = browser.applicationSupportProfileRoots(homeDirectory: context.homeDirectory)
            .filter { context.fileManager.fileExists(atPath: $0.path) }
        guard !protectedRoots.isEmpty else { return false }
        return !protectedRoots.contains { Self.isProfileRootReadable($0, fileManager: context.fileManager) }
    }

    private static func isProfileRootReadable(_ root: URL, fileManager: FileManager) -> Bool {
        do {
            _ = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return true
        } catch {
            return !isPermissionError(error)
        }
    }

    private static func fullDiskAccessWarning(for browser: BrowserIdentity) -> String {
        "\(browser.displayName): wymaga Pełnego dostępu do dysku (Full Disk Access) — macOS blokuje ~/Library/Application Support. Dodaj AutoCleanMac w Ustawieniach systemowych › Prywatność i bezpieczeństwo › Pełny dostęp do dysku."
    }

    private func logFinish(context: CleanupContext, result: TaskResult) {
        context.logger.log(event: result.skipped ? "browser_data_skip" : "browser_data_done", fields: [
            "browser": browser.rawValue,
            "type": dataType.rawValue,
            "freed": "\(result.bytesFreed)",
            "items": "\(result.itemsDeleted)",
            "warnings": "\(result.warnings.count)",
            "skip_reason": result.skipReason ?? "",
        ])
    }

    private func listProfileDirs(in root: URL, fileManager: FileManager) throws -> [URL] {
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Czy błąd to odmowa dostępu (POSIX EACCES/EPERM lub Cocoa „no permission”).
    /// macOS opakowuje błąd POSIX w `NSUnderlyingErrorKey`, więc sprawdzamy też zagnieżdżenie.
    private static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError { return true }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EACCES) || ns.code == Int(EPERM)) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EACCES) || underlying.code == Int(EPERM) {
            return true
        }
        return false
    }

    /// Lista konkretnych plików/katalogów do usunięcia w obrębie jednego profilu.
    private func itemsToDelete(in profile: URL) -> [URL] {
        if browser == .safari {
            let container = profile.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library")
            let safari = profile.appendingPathComponent("Library/Safari")
            switch dataType {
            case .cache:
                return [container.appendingPathComponent("Caches/com.apple.Safari")]
            case .cookies:
                return [
                    container.appendingPathComponent("Cookies/Cookies.binarycookies"),
                    safari.appendingPathComponent("Cookies.binarycookies")
                ]
            case .history:
                return [
                    safari.appendingPathComponent("History.db"),
                    safari.appendingPathComponent("History.db-wal"),
                    safari.appendingPathComponent("History.db-shm")
                ]
            }
        }

        switch (browser.isChromium, dataType) {
        case (true, .cache):
            return [
                profile.appendingPathComponent("Cache"),
                profile.appendingPathComponent("Code Cache"),
                profile.appendingPathComponent("GPUCache"),
            ]
        case (false, .cache):
            // Firefox cache — pod `.../Firefox/Profiles/<hash>.<name>/cache2/` zarówno w Application Support jak i Caches
            return [profile.appendingPathComponent("cache2")]
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
        case (true, .history):
            return [
                // Główna baza historii (SQLite)
                profile.appendingPathComponent("History"),
                profile.appendingPathComponent("History-journal"),
                profile.appendingPathComponent("History Provider Cache"),
                profile.appendingPathComponent("Archived History"),
                profile.appendingPathComponent("Archived History-journal"),
                // Faviconsy odwiedzonych stron (SQLite) — jawny ślad "gdzie byłem"
                profile.appendingPathComponent("Favicons"),
                profile.appendingPathComponent("Favicons-journal"),
                // Omnibox autocomplete zbudowany z historii
                profile.appendingPathComponent("Shortcuts"),
                profile.appendingPathComponent("Shortcuts-journal"),
                // Odwiedzone linki (kolor linku w CSS :visited)
                profile.appendingPathComponent("Visited Links"),
                profile.appendingPathComponent("Top Sites"),
                profile.appendingPathComponent("Top Sites-journal"),
                // Predykcje adresów z historii (omnibox)
                profile.appendingPathComponent("Network Action Predictor"),
                profile.appendingPathComponent("Network Action Predictor-journal"),
                // Session restore — bez tego przeglądarka wraca do poprzednich tabów
                profile.appendingPathComponent("Sessions"),
                profile.appendingPathComponent("Session Storage"),
                profile.appendingPathComponent("Current Session"),
                profile.appendingPathComponent("Current Tabs"),
                profile.appendingPathComponent("Last Session"),
                profile.appendingPathComponent("Last Tabs"),
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
        }
    }
}

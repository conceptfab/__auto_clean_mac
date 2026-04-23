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

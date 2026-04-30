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

    public init(url: URL, bytes: Int64) {
        self.url = url
        self.bytes = bytes
    }
}

public struct OrphanScanner: Sendable {
    public let minimumAgeDays: Int

    /// Bundle ID prefiksy, których nie raportujemy jako sieroty (system, Apple).
    public static let skippedPrefixes: [String] = [
        "com.apple.",
        ".GlobalPreferences",
        "GlobalPreferences",
        "org.cups.",
    ]

    public init(minimumAgeDays: Int = 30) {
        self.minimumAgeDays = max(0, minimumAgeDays)
    }

    public func scan(homeDirectory: URL, installedBundleIDs: Set<String>) -> [OrphanGroup] {
        let lib = homeDirectory.appendingPathComponent("Library")
        var byID: [String: [OrphanPath]] = [:]

        // Skanowane lokalizacje (basename → bundle ID).
        let plistDirs: [(URL, suffix: String)] = [
            (lib.appendingPathComponent("Preferences"), ".plist"),
            (lib.appendingPathComponent("Cookies"), ".binarycookies"),
        ]
        for (dir, suffix) in plistDirs {
            collectFiles(in: dir, suffix: suffix, into: &byID, installed: installedBundleIDs)
        }

        // Katalogi nazwane bundle ID.
        // Nie skanujemy tu LaunchAgents, Containers, Group Containers ani Application Scripts:
        // są zbyt ryzykowne jako generic orphan sweep i często dają fałszywe trafienia.
        let dirRoots: [URL] = [
            lib.appendingPathComponent("Application Support"),
            lib.appendingPathComponent("Caches"),
            lib.appendingPathComponent("HTTPStorages"),
            lib.appendingPathComponent("Logs"),
            lib.appendingPathComponent("WebKit"),
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
            guard isOldEnough(url) else { continue }
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
            guard isOldEnough(url) else { continue }
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

    private func isOldEnough(_ url: URL) -> Bool {
        guard minimumAgeDays > 0 else { return true }
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate else {
            return false
        }
        let age = Date().timeIntervalSince(modified)
        return age >= TimeInterval(minimumAgeDays * 24 * 60 * 60)
    }
}

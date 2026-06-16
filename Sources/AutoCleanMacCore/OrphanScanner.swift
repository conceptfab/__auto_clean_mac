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

    public func scan(homeDirectory: URL, installedBundleIDs: Set<String>) async -> [OrphanGroup] {
        let lib = homeDirectory.appendingPathComponent("Library")

        // Phase 1 — discovery (cheap: directory listings, name filtering, age check). No sizing yet.
        // Candidates are collected in scan order so within-group path ordering is preserved.
        var candidates: [(bundleID: String, url: URL)] = []

        let plistDirs: [(URL, suffix: String)] = [
            (lib.appendingPathComponent("Preferences"), ".plist"),
            (lib.appendingPathComponent("Cookies"), ".binarycookies"),
        ]
        for (dir, suffix) in plistDirs {
            discoverFiles(in: dir, suffix: suffix, into: &candidates, installed: installedBundleIDs)
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
            discoverDirectories(in: root, into: &candidates, installed: installedBundleIDs)
        }

        // Saved Application State – `<id>.savedState`.
        discoverFiles(in: lib.appendingPathComponent("Saved Application State"), suffix: ".savedState", into: &candidates, installed: installedBundleIDs)

        // Phase 2 — size each candidate concurrently (bounded), preserving discovery order by index.
        let sizes: [Int64] = await withTaskGroup(of: (Int, Int64).self) { group -> [Int64] in
            let maxConcurrent = 8
            var nextIndex = 0
            func addTaskIfNeeded() {
                guard nextIndex < candidates.count else { return }
                let i = nextIndex
                let url = candidates[i].url
                nextIndex += 1
                group.addTask { (i, (try? SafeDeleter.recursiveMetrics(at: url).bytesFreed) ?? 0) }
            }
            for _ in 0..<min(maxConcurrent, candidates.count) { addTaskIfNeeded() }
            var buffer = [Int64](repeating: 0, count: candidates.count)
            while let (i, bytes) = await group.next() {
                buffer[i] = bytes
                addTaskIfNeeded()
            }
            return buffer
        }

        // Phase 3 — group by bundle ID in discovery order, then sort groups by size.
        var byID: [String: [OrphanPath]] = [:]
        for (i, candidate) in candidates.enumerated() {
            byID[candidate.bundleID, default: []].append(OrphanPath(url: candidate.url, bytes: sizes[i]))
        }

        return byID
            .map { OrphanGroup(bundleID: $0.key, paths: $0.value) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    private func discoverFiles(
        in dir: URL,
        suffix: String,
        into candidates: inout [(bundleID: String, url: URL)],
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
            candidates.append((bundleID, url))
        }
    }

    private func discoverDirectories(
        in root: URL,
        into candidates: inout [(bundleID: String, url: URL)],
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
            candidates.append((name, url))
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

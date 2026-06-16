import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct AppInfo: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let bundleIdentifier: String
    #if canImport(AppKit)
    public let icon: NSImage?
    #endif
    public let leftoverPaths: [URL]
    public let appSize: Int64
    public let leftoversSize: Int64
    
    public var totalSize: Int64 { appSize + leftoversSize }
}

public final class AppScanner: Sendable {
    public init() {}
    
    public func scanApps(homeDirectory: URL) async -> [AppInfo] {
        let fm = FileManager.default
        let dirsToScan = [
            URL(fileURLWithPath: "/Applications"),
            homeDirectory.appendingPathComponent("Applications")
        ]
        
        // Collect all .app bundle URLs first (cheap directory enumeration).
        var appURLs: [URL] = []
        for dir in dirsToScan {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            guard let files = enumerator.allObjects as? [URL] else { continue }
            for fileURL in files where fileURL.pathExtension == "app" {
                appURLs.append(fileURL)
            }
        }

        // Size each bundle concurrently — independent, I/O-bound work. Bounded so we don't
        // launch an unbounded number of recursive filesystem walks at once. Result is sorted
        // afterward, so completion order does not affect output.
        let apps = await withTaskGroup(of: AppInfo?.self) { group -> [AppInfo] in
            let maxConcurrent = 8
            var nextIndex = 0
            func addTaskIfNeeded() {
                guard nextIndex < appURLs.count else { return }
                let url = appURLs[nextIndex]
                nextIndex += 1
                group.addTask { await self.processApp(at: url, homeDirectory: homeDirectory, fileManager: .default) }
            }
            for _ in 0..<min(maxConcurrent, appURLs.count) { addTaskIfNeeded() }
            var collected: [AppInfo] = []
            while let result = await group.next() {
                if let app = result { collected.append(app) }
                addTaskIfNeeded()
            }
            return collected
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private func processApp(at url: URL, homeDirectory: URL, fileManager: FileManager) async -> AppInfo? {
        // Defense-in-depth: never scan /System/. AppProtectionGuard is authoritative for bundle IDs.
        guard !url.path.hasPrefix("/System/") else { return nil }

        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !AppProtectionGuard.isProtected(bundleID: bundleID) else {
            return nil
        }
        
        let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
            
        let leftovers = LeftoverPathProvider.userPaths(
            bundleID: bundleID,
            displayName: name,
            homeDirectory: homeDirectory
        ) + LeftoverPathProvider.resolveDynamic(
            bundleID: bundleID,
            homeDirectory: homeDirectory
        )
        
        var appSize: Int64 = 0
        if let metrics = try? SafeDeleter.recursiveMetrics(at: url) {
            appSize = metrics.bytesFreed
        }
        
        var leftoversSize: Int64 = 0
        for path in leftovers {
            if fileManager.fileExists(atPath: path.path) {
                if let metrics = try? SafeDeleter.recursiveMetrics(at: path) {
                    leftoversSize += metrics.bytesFreed
                }
            }
        }
        
        #if canImport(AppKit)
        struct IconResult: @unchecked Sendable { let icon: NSImage }
        let icon = await MainActor.run { IconResult(icon: NSWorkspace.shared.icon(forFile: url.path)) }.icon
        #endif
        
        #if canImport(AppKit)
        return AppInfo(
            url: url,
            name: name,
            bundleIdentifier: bundleID,
            icon: icon,
            leftoverPaths: leftovers.filter { fileManager.fileExists(atPath: $0.path) },
            appSize: appSize,
            leftoversSize: leftoversSize
        )
        #else
        return AppInfo(
            url: url,
            name: name,
            bundleIdentifier: bundleID,
            leftoverPaths: leftovers.filter { fileManager.fileExists(atPath: $0.path) },
            appSize: appSize,
            leftoversSize: leftoversSize
        )
        #endif
    }
}

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
        
        var apps: [AppInfo] = []
        for dir in dirsToScan {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            guard let files = enumerator.allObjects as? [URL] else { continue }
            for fileURL in files {
                if fileURL.pathExtension == "app" {
                    if let app = await processApp(at: fileURL, homeDirectory: homeDirectory, fileManager: fm) {
                        apps.append(app)
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private func processApp(at url: URL, homeDirectory: URL, fileManager: FileManager) async -> AppInfo? {
        // Zabezpieczenie przed usuwaniem systemowych aplikacji
        guard !url.path.hasPrefix("/System/") else { return nil }
        guard !url.path.hasPrefix("/Applications/Utilities/") else { return nil }
        
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !bundleID.hasPrefix("com.apple.") else {
            return nil
        }
        
        let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
            
        let leftovers = generateLeftoverPaths(for: bundleID, homeDirectory: homeDirectory)
        
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
    
    private func generateLeftoverPaths(for bundleID: String, homeDirectory: URL) -> [URL] {
        let lib = homeDirectory.appendingPathComponent("Library")
        return [
            lib.appendingPathComponent("Application Support/\(bundleID)"),
            lib.appendingPathComponent("Caches/\(bundleID)"),
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            lib.appendingPathComponent("Containers/\(bundleID)"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
            lib.appendingPathComponent("Logs/\(bundleID)"),
            lib.appendingPathComponent("WebKit/\(bundleID)")
        ]
    }
}

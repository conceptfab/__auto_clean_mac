import Foundation

public struct PurgeFailure: Sendable {
    public let path: String
    public let reason: String
    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct PurgeOutcome: Sendable {
    public var appRemoved: Bool
    public var bytesFreed: Int64
    public var itemsDeleted: Int
    public var elevatedFallbackUsed: Bool
    public var failures: [PurgeFailure]
}

public final class AppPurger: Sendable {
    private let deleter: SafeDeleter
    private let prefsDaemon: PreferencesDaemonClient
    private let launchAgents: LaunchAgentClient
    private let elevatedRemove: @Sendable (URL) async throws -> Void
    private let logger: Logger

    public init(
        deleter: SafeDeleter,
        prefsDaemon: PreferencesDaemonClient,
        launchAgents: LaunchAgentClient,
        elevatedRemove: @escaping @Sendable (URL) async throws -> Void,
        logger: Logger
    ) {
        self.deleter = deleter
        self.prefsDaemon = prefsDaemon
        self.launchAgents = launchAgents
        self.elevatedRemove = elevatedRemove
        self.logger = logger
    }

    public func purge(
        bundleID: String,
        displayName: String?,
        appURL: URL,
        homeDirectory: URL,
        systemRoot: URL = URL(fileURLWithPath: "/"),
        includeSystemPaths: Bool
    ) async -> PurgeOutcome {
        let fm = FileManager.default
        var bytes: Int64 = 0
        var items = 0
        var failures: [PurgeFailure] = []
        var elevatedUsed = false

        let appRoot = appURL.deletingLastPathComponent()
        var appRemoved = false
        do {
            let metrics = try deleter.deleteMeasured(appURL, withinRoot: appRoot)
            bytes += metrics.bytesFreed
            items += metrics.itemsDeleted
            appRemoved = true
        } catch {
            if fm.fileExists(atPath: appURL.path), deleter.mode != .dryRun {
                let measured = (try? SafeDeleter.recursiveMetrics(at: appURL).bytesFreed) ?? 0
                do {
                    try await elevatedRemove(appURL)
                    if !fm.fileExists(atPath: appURL.path) {
                        bytes += measured
                        appRemoved = true
                        elevatedUsed = true
                    } else {
                        failures.append(PurgeFailure(path: appURL.path, reason: "Plik nadal istnieje po elewacji."))
                    }
                } catch {
                    failures.append(PurgeFailure(path: appURL.path, reason: "\(error)"))
                }
            } else {
                failures.append(PurgeFailure(path: appURL.path, reason: (error as NSError).localizedDescription))
            }
        }

        // Leftovers user-side — usuwane nawet jeśli .app już nie istniała (czyścimy resztki).
        let userLib = homeDirectory.appendingPathComponent("Library")
        let userLeftovers = LeftoverPathProvider.userPaths(bundleID: bundleID, displayName: displayName, homeDirectory: homeDirectory)
            + LeftoverPathProvider.resolveDynamic(bundleID: bundleID, homeDirectory: homeDirectory)
        for url in userLeftovers where fm.fileExists(atPath: url.path) {
            // Unload LaunchAgents zanim usuniemy plist.
            if url.path.hasPrefix(userLib.appendingPathComponent("LaunchAgents").path) {
                _ = launchAgents.unload(plist: url, domain: .userGUI(uid: getuid()))
            }
            do {
                let metrics = try deleter.deleteMeasured(url, withinRoot: userLib)
                bytes += metrics.bytesFreed
                items += metrics.itemsDeleted
            } catch {
                failures.append(PurgeFailure(path: url.path, reason: (error as NSError).localizedDescription))
            }
        }

        if includeSystemPaths {
            let systemLib = systemRoot.appendingPathComponent("Library")
            let systemLeftovers = LeftoverPathProvider.systemPaths(bundleID: bundleID, displayName: displayName, systemRoot: systemRoot)
                + LeftoverPathProvider.resolveDynamicSystem(bundleID: bundleID, systemRoot: systemRoot)
            for url in systemLeftovers where fm.fileExists(atPath: url.path) {
                if url.path.hasPrefix(systemLib.appendingPathComponent("LaunchDaemons").path)
                    || url.path.hasPrefix(systemLib.appendingPathComponent("LaunchAgents").path) {
                    _ = launchAgents.unload(plist: url, domain: .system)
                }
                let measured = (try? SafeDeleter.recursiveMetrics(at: url).bytesFreed) ?? 0
                if deleter.mode == .dryRun {
                    logger.log(event: "purge_system_dryrun", fields: ["path": url.path, "size": "\(measured)"])
                    continue
                }
                do {
                    try await elevatedRemove(url)
                    if fm.fileExists(atPath: url.path) {
                        failures.append(PurgeFailure(path: url.path, reason: "System path nie usunięty po elewacji."))
                    } else {
                        bytes += measured
                        items += 1
                        elevatedUsed = true
                    }
                } catch {
                    failures.append(PurgeFailure(path: url.path, reason: "\(error)"))
                }
            }
        }

        // Wymuś flush cfprefsd na końcu (po usunięciu plików), niezależnie od trybu.
        if deleter.mode != .dryRun {
            _ = prefsDaemon.deleteAll(bundleID: bundleID)
        }

        logger.log(event: "purge_done", fields: [
            "bundle": bundleID,
            "removed": "\(appRemoved)",
            "bytes": "\(bytes)",
            "items": "\(items)",
            "failures": "\(failures.count)",
            "elevated": "\(elevatedUsed)",
        ])

        return PurgeOutcome(
            appRemoved: appRemoved,
            bytesFreed: bytes,
            itemsDeleted: items,
            elevatedFallbackUsed: elevatedUsed,
            failures: failures
        )
    }
}

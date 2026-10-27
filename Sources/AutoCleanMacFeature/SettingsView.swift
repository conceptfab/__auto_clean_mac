import AppKit
import SwiftUI
import AutoCleanMacCore

public struct UninstallFailure: Sendable {
    public let appName: String
    public let reason: String

    public init(appName: String, reason: String) {
        self.appName = appName
        self.reason = reason
    }
}

public struct UninstallOutcome: Sendable {
    public var freedBytes: Int64
    public var succeeded: Int
    public var failures: [UninstallFailure]

    public init(freedBytes: Int64, succeeded: Int, failures: [UninstallFailure]) {
        self.freedBytes = freedBytes
        self.succeeded = succeeded
        self.failures = failures
    }
}

/// Observable model trzymający EDYTOWALNE preferencje.
public final class SettingsModel: ObservableObject {
    @Published var retentionDays: Int
    @Published var deleteMode: SafeDeleter.Mode
    @Published var reminder: Config.Reminder
    @Published var launchAtLogin: Bool
    @Published public var statistics: AppStatistics
    @Published var tasks: Config.Tasks
    @Published var browsers: [BrowserIdentity: BrowserPreferences]
    @Published var excludedPathsText: String
    @Published var whitelistedCacheAppsText: String
    @Published var globalShortcutEnabled: Bool
    /// Wybrana zakładka okna preferencji (`nil` tylko chwilowo, gdy lista zgubi zaznaczenie).
    @Published public var selectedSection: SettingsSection? = .scanner
    /// Opis przełącznika autostartu w zakładce Ogólne (hub podmienia go na „Sprzątaj po zalogowaniu”).
    public var launchAtLoginTitle = "Uruchamiaj przy logowaniu"
    public var launchAtLoginFooter = "To podstawowa opcja dla komputerów, które rzadko są restartowane. Steruje LaunchAgentem, więc AutoCleanMac może uruchamiać się po zalogowaniu i działać w tle."
    /// `false` w hubie: skrót ⌘⇧C nie jest tam przenoszony (SPEC huba §4.6).
    public var showsGlobalShortcutOption = true

    @Published var orphans: [OrphanGroup] = []
    @Published var selectedOrphans: Set<String> = []
    @Published var orphansScanning: Bool = false

    let onApply: (Config, Bool) -> Void
    let onApplyRun: (Config, Bool) -> Void
    let onPreview: (Config) -> Void
    let onOpenLogsFolder: () -> Void
    let onShowLastLog: () -> Void
    let onUninstall: ([AppInfo], SafeDeleter.Mode) async -> UninstallOutcome
    let onScanOrphans: () async -> [OrphanGroup]
    let onRemoveOrphans: ([OrphanGroup], SafeDeleter.Mode) async -> UninstallOutcome
    let homeDirectory: URL
    private let baseConfig: Config

    public init(
        initial: Config,
        statistics: AppStatistics,
        launchAtLogin: Bool,
        homeDirectory: URL,
        onApply: @escaping (Config, Bool) -> Void,
        onApplyRun: @escaping (Config, Bool) -> Void,
        onPreview: @escaping (Config) -> Void,
        onOpenLogsFolder: @escaping () -> Void,
        onShowLastLog: @escaping () -> Void,
        onUninstall: @escaping ([AppInfo], SafeDeleter.Mode) async -> UninstallOutcome,
        onScanOrphans: @escaping () async -> [OrphanGroup],
        onRemoveOrphans: @escaping ([OrphanGroup], SafeDeleter.Mode) async -> UninstallOutcome
    ) {
        self.baseConfig = initial
        self.retentionDays = initial.retentionDays
        self.deleteMode = initial.deleteMode
        self.reminder = initial.reminder
        self.launchAtLogin = launchAtLogin
        self.statistics = statistics
        self.tasks = initial.tasks
        self.browsers = initial.browsers
        self.excludedPathsText = initial.excludedPaths.joined(separator: "\n")
        self.whitelistedCacheAppsText = initial.whitelistedCacheApps.joined(separator: "\n")
        self.globalShortcutEnabled = initial.globalShortcutEnabled
        self.onApply = onApply
        self.onApplyRun = onApplyRun
        self.onPreview = onPreview
        self.onOpenLogsFolder = onOpenLogsFolder
        self.onShowLastLog = onShowLastLog
        self.onUninstall = onUninstall
        self.onScanOrphans = onScanOrphans
        self.onRemoveOrphans = onRemoveOrphans
        self.homeDirectory = homeDirectory
    }

    @MainActor
    func scanOrphans() async {
        orphansScanning = true
        defer { orphansScanning = false }
        selectedOrphans = []
        orphans = await onScanOrphans()
    }

    @MainActor
    func removeSelectedOrphans() async {
        let chosen = orphans.filter { selectedOrphans.contains($0.id) }
        guard !chosen.isEmpty else { return }
        _ = await onRemoveOrphans(chosen, deleteMode)
        await scanOrphans()
    }

    func toggle(_ browser: BrowserIdentity, _ type: BrowserDataType, _ enabled: Bool) {
        var prefs = browsers[browser, default: .none]
        prefs.set(type, enabled)
        browsers[browser] = prefs
    }

    func isOn(_ browser: BrowserIdentity, _ type: BrowserDataType) -> Bool {
        browsers[browser, default: .none].contains(type)
    }

    var enabledTaskCount: Int {
        [
            tasks.userCaches,
            tasks.systemTemp,
            tasks.trash,
            tasks.dsStore,
            tasks.userLogs,
            tasks.devCaches,
            tasks.homebrewCleanup,
            tasks.projectArtifacts,
            tasks.downloads,
        ].filter { $0 }.count
    }

    var selectedBrowserDataCount: Int {
        browsers.values.reduce(into: 0) { partial, prefs in
            partial += prefs.types.count
        }
    }

    var riskLabel: String {
        switch deleteMode {
        case .trash:
            return "Bezpieczny"
        case .dryRun:
            return "Podgląd"
        case .live:
            return "Ryzykowny"
        }
    }

    var browserSelectionsSummary: String {
        selectedBrowserDataCount == 0
            ? "Brak wybranych danych przeglądarek"
            : "\(selectedBrowserDataCount) aktywnych ustawień przeglądarek"
    }

    var enabledTaskSummary: String {
        "\(enabledTaskCount) zadań systemowych aktywnych"
    }

    public func currentConfig() -> Config {
        var updated = baseConfig
        updated.retentionDays = retentionDays
        updated.deleteMode = deleteMode
        updated.reminder = reminder
        updated.tasks = tasks
        updated.browsers = browsers
        updated.excludedPaths = excludedPathsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.whitelistedCacheApps = whitelistedCacheAppsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.globalShortcutEnabled = globalShortcutEnabled
        return updated
    }

    func apply() { onApply(currentConfig(), launchAtLogin) }
    func applyRun() { onApplyRun(currentConfig(), launchAtLogin) }
    func preview() { onPreview(currentConfig()) }
}

/// Zakładki okna preferencji (11 sekcji).
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case scanner
    case general
    case cleanup
    case browsers
    case uninstaller
    case orphans
    case reminders
    case advanced
    case statistics
    case logs
    case about

    public var id: String { rawValue }

    /// Sekcja z klucza (np. `uninstaller` z `cfab-control://autoclean/open?tab=uninstaller`).
    public init?(key: String) {
        self.init(rawValue: key.lowercased())
    }

    public var title: String {
        switch self {
        case .scanner: return "Skaner"
        case .general: return "Ogólne"
        case .statistics: return "Statystyki"
        case .about: return "O programie"
        case .cleanup: return "Czyszczenie"
        case .browsers: return "Przeglądarki"
        case .uninstaller: return "Deinstalator"
        case .orphans: return "Osierocone preferencje"
        case .reminders: return "Przypominacz"
        case .advanced: return "Zaawansowane"
        case .logs: return "Logi"
        }
    }

    public var symbol: String {
        switch self {
        case .scanner: return "magnifyingglass"
        case .general: return "gearshape"
        case .statistics: return "chart.bar"
        case .about: return "info.circle"
        case .cleanup: return "trash"
        case .browsers: return "globe"
        case .uninstaller: return "app.dashed"
        case .orphans: return "questionmark.folder"
        case .reminders: return "bell"
        case .advanced: return "slider.horizontal.3"
        case .logs: return "doc.text"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    private let embeddedSection: SettingsSection?

    public init(model: SettingsModel, section: SettingsSection? = nil) {
        self.model = model
        embeddedSection = section
    }

    public var body: some View {
        if let embeddedSection {
            editor(section: embeddedSection)
        } else {
            standalone
        }
    }

    private func editor(section: SettingsSection) -> some View {
        detailContent(section: section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
    }

    private var standalone: some View {
        VStack(spacing: 0) {
            HSplitView {
                sidebar
                    .frame(minWidth: 168, idealWidth: 176, maxWidth: 184)

                detailContent(section: model.selectedSection ?? .scanner)
            }

            saveBar
        }
        .frame(width: 920, height: 640)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button("Podgląd sprzątania") { model.preview() }
                Spacer()
                Button("Zapisz") { model.apply() }
                    .buttonStyle(.borderedProminent)
                Menu("Więcej", systemImage: "ellipsis") {
                    Button("Zapisz i wyczyść teraz") { model.applyRun() }
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AutoCleanMac")
                    .font(.title3.weight(.semibold))
                Text("Preferencje")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            List(SettingsSection.allCases, selection: $model.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func detailContent(section: SettingsSection) -> some View {
        switch section {
        case .scanner:
            ScannerTab(settingsModel: model)
        case .general:
            GeneralTab(model: model)
        case .statistics:
            StatisticsTab(model: model)
        case .about:
            AboutTab()
        case .cleanup:
            CleanupTab(model: model)
        case .browsers:
            BrowsersTab(model: model)
        case .uninstaller:
            UninstallerTab(settingsModel: model)
        case .orphans:
            OrphanCleanerTab(settingsModel: model)
        case .reminders:
            RemindersTab(model: model)
        case .advanced:
            AdvancedTab(model: model)
        case .logs:
            LogsTab(model: model)
        }
    }
}

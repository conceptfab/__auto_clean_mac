import AppKit
import SwiftUI
import AutoCleanMacCore

struct UninstallFailure: Sendable {
    let appName: String
    let reason: String
}

struct UninstallOutcome: Sendable {
    var freedBytes: Int64
    var succeeded: Int
    var failures: [UninstallFailure]
}

/// Observable model trzymający EDYTOWALNE preferencje.
final class SettingsModel: ObservableObject {
    @Published var retentionDays: Int
    @Published var deleteMode: DeleteMode
    @Published var reminder: Config.Reminder
    @Published var launchAtLogin: Bool
    @Published var statistics: AppStatistics
    @Published var tasks: Config.Tasks
    @Published var browsers: [BrowserIdentity: BrowserPreferences]
    @Published var excludedPathsText: String
    @Published var whitelistedCacheAppsText: String
    @Published var globalShortcutEnabled: Bool

    let onApply: (Config, Bool) -> Void
    let onApplyRun: (Config, Bool) -> Void
    let onPreview: (Config) -> Void
    let onOpenLogsFolder: () -> Void
    let onShowLastLog: () -> Void
    let onUninstall: ([AppInfo], SafeDeleter.Mode) async -> UninstallOutcome
    let homeDirectory: URL
    private let baseConfig: Config

    init(
        initial: Config,
        statistics: AppStatistics,
        launchAtLogin: Bool,
        homeDirectory: URL,
        onApply: @escaping (Config, Bool) -> Void,
        onApplyRun: @escaping (Config, Bool) -> Void,
        onPreview: @escaping (Config) -> Void,
        onOpenLogsFolder: @escaping () -> Void,
        onShowLastLog: @escaping () -> Void,
        onUninstall: @escaping ([AppInfo], SafeDeleter.Mode) async -> UninstallOutcome
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
        self.homeDirectory = homeDirectory
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

    func currentConfig() -> Config {
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

struct SettingsView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case scanner
        case general
        case cleanup
        case browsers
        case uninstaller
        case reminders
        case advanced
        case statistics
        case logs
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .scanner: return "Skaner"
            case .general: return "Ogólne"
            case .statistics: return "Statystyki"
            case .about: return "O programie"
            case .cleanup: return "Czyszczenie"
            case .browsers: return "Przeglądarki"
            case .uninstaller: return "Deinstalator"
            case .reminders: return "Przypominacz"
            case .advanced: return "Zaawansowane"
            case .logs: return "Logi"
            }
        }

        var symbol: String {
            switch self {
            case .scanner: return "magnifyingglass"
            case .general: return "gearshape"
            case .statistics: return "chart.bar"
            case .about: return "info.circle"
            case .cleanup: return "trash"
            case .browsers: return "globe"
            case .uninstaller: return "app.dashed"
            case .reminders: return "bell"
            case .advanced: return "slider.horizontal.3"
            case .logs: return "doc.text"
            }
        }
    }

    @ObservedObject var model: SettingsModel
    @State private var selection: SettingsSection = .scanner

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                sidebar
                    .frame(minWidth: 168, idealWidth: 176, maxWidth: 184)

                detailContent
            }

            Divider()

            HStack(spacing: 8) {
                Button("Podgląd cleanupu") { model.preview() }
                Spacer()
                Button("Zapisz") { model.apply() }
                Button("Zapisz i wyczyść teraz") { model.applyRun() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .frame(width: 920, height: 640)
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

            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
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
        case .reminders:
            RemindersTab(model: model)
        case .advanced:
            AdvancedTab(model: model)
        case .logs:
            LogsTab(model: model)
        }
    }
}

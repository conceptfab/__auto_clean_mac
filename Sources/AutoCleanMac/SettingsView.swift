import AppKit
import SwiftUI
import AutoCleanMacCore

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

    let onApply: (Config, Bool) -> Void
    let onApplyRun: (Config, Bool) -> Void
    let onPreview: (Config) -> Void
    let onOpenLogsFolder: () -> Void
    let onShowLastLog: () -> Void
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
        onShowLastLog: @escaping () -> Void
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
        self.onApply = onApply
        self.onApplyRun = onApplyRun
        self.onPreview = onPreview
        self.onOpenLogsFolder = onOpenLogsFolder
        self.onShowLastLog = onShowLastLog
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

    private func currentConfig() -> Config {
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
        return updated
    }

    func apply() { onApply(currentConfig(), launchAtLogin) }
    func applyRun() { onApplyRun(currentConfig(), launchAtLogin) }
    func preview() { onPreview(currentConfig()) }
}

struct SettingsView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case cleanup
        case browsers
        case reminders
        case advanced
        case statistics
        case logs
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "Ogólne"
            case .statistics: return "Statystyki"
            case .about: return "O programie"
            case .cleanup: return "Czyszczenie"
            case .browsers: return "Przeglądarki"
            case .reminders: return "Przypominacz"
            case .advanced: return "Zaawansowane"
            case .logs: return "Logi"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .statistics: return "chart.bar"
            case .about: return "info.circle"
            case .cleanup: return "trash"
            case .browsers: return "globe"
            case .reminders: return "bell"
            case .advanced: return "slider.horizontal.3"
            case .logs: return "doc.text"
            }
        }
    }

    @ObservedObject var model: SettingsModel
    @State private var selection: SettingsSection = .general

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
        case .reminders:
            RemindersTab(model: model)
        case .advanced:
            AdvancedTab(model: model)
        case .logs:
            LogsTab(model: model)
        }
    }
}

// MARK: - Tabs

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreferencesGroup("Autostart") {
                    Toggle("Uruchamiaj przy logowaniu", isOn: $model.launchAtLogin)

                    OverviewNote(
                        title: model.launchAtLogin ? "Autostart jest włączony" : "Autostart jest wyłączony",
                        text: "To podstawowa opcja dla komputerów, które rzadko są restartowane. Steruje LaunchAgentem, więc AutoCleanMac może uruchamiać się po zalogowaniu i działać w tle."
                    )
                }

                PreferencesGroup("Tryb pracy") {
                    KeyValueRow(title: "Usuwanie", value: model.deleteMode.title)
                    KeyValueRow(title: "Poziom ryzyka", value: model.riskLabel)
                    KeyValueRow(title: "Retencja", value: "\(model.retentionDays) dni")
                }

                PreferencesGroup("Zakres") {
                    KeyValueRow(title: "Zadania systemowe", value: model.enabledTaskSummary)
                    KeyValueRow(title: "Przeglądarki", value: model.browserSelectionsSummary)
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct StatisticsTab: View {
    @ObservedObject var model: SettingsModel

    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    private var totalBytesString: String {
        Self.bytesFormatter.string(fromByteCount: model.statistics.totalBytesFreed)
    }

    private var lastCleanupString: String {
        guard let date = model.statistics.lastCleanupAt else {
            return "Jeszcze nie było cleanupu"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreferencesGroup("Od instalacji") {
                    KeyValueRow(title: "Zwolnione miejsce", value: totalBytesString)
                    KeyValueRow(title: "Usunięte pliki", value: "\(model.statistics.totalItemsDeleted)")
                    KeyValueRow(title: "Uruchomienia cleanupu", value: "\(model.statistics.totalRuns)")
                    KeyValueRow(title: "Ostatni cleanup", value: lastCleanupString)
                }

                if !model.statistics.recentRuns.isEmpty {
                    PreferencesGroup("Ostatnie cleanupy") {
                        ForEach(model.statistics.recentRuns, id: \.cleanedAt) { run in
                            CleanupHistoryRow(run: run)
                        }
                    }
                }

                PreferencesGroup("Co obejmują statystyki") {
                    OverviewNote(
                        title: "Wliczane są prawdziwe cleanupy",
                        text: "Liczniki rosną po realnym uruchomieniu cleanupu z menu, preferencji, launchd albo automatycznego harmonogramu."
                    )
                    OverviewNote(
                        title: "Podgląd nie zawyża liczb",
                        text: "Tryb preview pokazuje symulację, ale nie dopisuje nic do statystyk od instalacji."
                    )
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CleanupHistoryRow: View {
    let run: CleanupRunRecord

    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    private var bytesString: String {
        Self.bytesFormatter.string(fromByteCount: run.bytesFreed)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.cleanedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Text("\(run.itemsDeleted) plik. · \(String(format: "%.1f", Double(run.durationMs) / 1000.0))s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(bytesString)
                    .font(.subheadline.weight(.medium))
                if run.warningsCount > 0 {
                    Text("\(run.warningsCount) ostrz.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct CleanupTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.tasks.userCaches) {
                    ItemLabel(
                        title: "Cache użytkownika",
                        detail: "Konserwatywne czyszczenie w ~/Library/Caches, z pominięciem aktywnych i chronionych aplikacji"
                    )
                }
                Toggle(isOn: $model.tasks.systemTemp) {
                    ItemLabel(title: "System Temp", detail: "/tmp, TemporaryItems")
                }
                Toggle(isOn: $model.tasks.trash) {
                    ItemLabel(title: "Kosz", detail: "Opróżnia ~/.Trash")
                }
                Toggle(isOn: $model.tasks.dsStore) {
                    ItemLabel(title: ".DS_Store", detail: "W całym katalogu domowym")
                }
                Toggle(isOn: $model.tasks.userLogs) {
                    ItemLabel(title: "Logi użytkownika", detail: "~/Library/Logs (respektuje retencję)")
                }
                Toggle(isOn: $model.tasks.devCaches) {
                    ItemLabel(title: "Cache devtools", detail: "DerivedData, npm, pip")
                }
                Toggle(isOn: $model.tasks.homebrewCleanup) {
                    ItemLabel(title: "Homebrew cleanup", detail: "Uruchamia brew cleanup --prune; tylko w trybie trwałego usuwania")
                }
                Toggle(isOn: $model.tasks.downloads) {
                    ItemLabel(title: "Downloads", detail: "Pliki starsze niż retencja")
                }
            } header: {
                Text("Zadania systemowe")
            } footer: {
                Text("Retencję respektują logi, Downloads, temp i cache devtools. Homebrew cleanup jest osobnym, bardziej agresywnym krokiem i nie działa w trybie Kosza ani podglądu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutTab: View {
    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?) where short != build:
            return "Wersja \(short) (\(build))"
        case let (short?, _):
            return "Wersja \(short)"
        case let (_, build?):
            return "Build \(build)"
        default:
            return "Wersja lokalna"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 18) {
                    AppIconHero()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("AutoCleanMac")
                            .font(.title2.weight(.semibold))
                        Text(versionString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Lekka aplikacja do bezpiecznego czyszczenia cache, logów, danych przeglądarek i innych śmieci, które z czasem zapychają macOS.")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                PreferencesGroup("O aplikacji") {
                    OverviewNote(
                        title: "Po co istnieje AutoCleanMac",
                        text: "Pomaga odzyskać miejsce bez ręcznego przeklikiwania się przez ukryte katalogi i bez agresywnego czyszczenia wszystkiego na ślepo."
                    )
                    OverviewNote(
                        title: "Jak działa",
                        text: "Aplikacja czyści wybrane obszary systemu zgodnie z Twoimi preferencjami, z trybem podglądu, przypomnieniami i bezpieczniejszym domyślnym usuwaniem do Kosza."
                    )
                }

                PreferencesGroup("Twórca") {
                    HStack {
                        Text("CONCEPTFAB.COM")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Link("Otwórz stronę", destination: URL(string: "https://conceptfab.com")!)
                    }
                }

            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct BrowsersTab: View {
    @ObservedObject var model: SettingsModel

    private var installed: [BrowserIdentity] {
        BrowserIdentity.allCases.filter { $0.isInstalled() }
    }

    var body: some View {
        Form {
            if installed.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nie wykryto obsługiwanych przeglądarek.")
                            .font(.headline)
                        Text("AutoCleanMac obsługuje Chrome, Firefox, Edge, Brave, Vivaldi i Arc. Safari wymaga dodatkowych uprawnień, więc nie jest jeszcze dostępne.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    HStack(spacing: 0) {
                        Text("Przeglądarka")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(BrowserDataType.allCases, id: \.self) { type in
                            Text(type.settingsColumnTitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .center)
                        }
                    }
                    .padding(.vertical, 2)

                    ForEach(installed, id: \.self) { browser in
                        HStack(spacing: 0) {
                            Text(browser.displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(BrowserDataType.allCases, id: \.self) { type in
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { model.isOn(browser, type) },
                                        set: { model.toggle(browser, type, $0) }
                                    )
                                )
                                .labelsHidden()
                                .accessibilityLabel("\(browser.displayName) — \(type.displayName(for: browser))")
                                .help(type.helpText(for: browser) ?? "")
                                .frame(width: 80, alignment: .center)
                            }
                        }
                    }
                } header: {
                    Text("Dane do wyczyszczenia")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Ciasteczka zwykle wylogowują z serwisów.", systemImage: "info.circle")
                        Label("„Historia*” czyści też sesje i faviconsy. Dzięki temu Chromium nie wraca do ostatnich kart.", systemImage: "info.circle")
                        Label("Firefox: „Historia*” zachowuje places.sqlite z zakładkami, a czyści autofill i historię pobrań.", systemImage: "info.circle")
                        Label("Uruchomione przeglądarki są pomijane. Zamknij je przed czyszczeniem.", systemImage: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("\(model.retentionDays)")
                            .monospacedDigit()
                            .frame(minWidth: 24, alignment: .trailing)
                        Text("dni")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $model.retentionDays, in: 1...30)
                            .labelsHidden()
                    }
                } label: {
                    Text("Przechowuj rzeczy nowsze niż")
                }
            } header: {
                Text("Retencja")
            } footer: {
                Text("Dotyczy zadań respektujących okres retencji, głównie logów i Downloads. Cache oraz część danych przeglądarek nie korzystają z tej reguły.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(DeleteMode.allCasesOrdered, id: \.self) { mode in
                    DeleteModeRow(
                        mode: mode,
                        selected: model.deleteMode == mode,
                        onSelect: { model.deleteMode = mode }
                    )
                }
            } header: {
                Text("Tryb usuwania")
            } footer: {
                Text("Kosz jest polecany jako tryb codzienny. Trwałe usuwanie zostaw dla sytuacji, gdy świadomie chcesz odzyskać miejsce od razu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $model.excludedPathsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 92)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Wykluczone ścieżki")
            } footer: {
                Text("Jedna ścieżka na linię. Obsługiwane są ścieżki absolutne oraz ~/Downloads/Praca. Wszystko pod wykluczoną ścieżką zostanie pominięte.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RemindersTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Tryb", selection: $model.reminder.mode) {
                    ForEach(ReminderMode.allCasesOrdered, id: \.self) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                }

                LabeledContent("Interwał") {
                    HStack(spacing: 6) {
                        Text("\(model.reminder.intervalHours)")
                            .monospacedDigit()
                            .frame(minWidth: 24, alignment: .trailing)
                        Text("godz.")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $model.reminder.intervalHours, in: 1...168)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Działanie w tle")
            } footer: {
                Text("Domyślnie AutoCleanMac przypomina co 24 godziny. Jeśli wybierzesz automatyczne czyszczenie, aplikacja wykona cleanup sama bez restartu komputera.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ReminderModeNote(
                    title: "Wyłączone",
                    text: "AutoCleanMac nie robi nic pomiędzy ręcznymi uruchomieniami."
                )
                ReminderModeNote(
                    title: "Przypomnienie",
                    text: "Po upływie interwału aplikacja pokaże lokalne przypomnienie o cleanupie."
                )
                ReminderModeNote(
                    title: "Automatyczne czyszczenie",
                    text: "Po upływie interwału aplikacja uruchomi cleanup sama, używając aktualnych ustawień."
                )
            } header: {
                Text("Tryby")
            }
        }
        .formStyle(.grouped)
    }
}

private struct LogsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Button {
                        model.onOpenLogsFolder()
                    } label: {
                        Label("Otwórz folder logów", systemImage: "folder")
                    }
                    Button {
                        model.onShowLastLog()
                    } label: {
                        Label("Pokaż ostatni log", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Logi")
            } footer: {
                Text("Każde uruchomienie zapisuje zdarzenia do ~/Library/Logs/AutoCleanMac/YYYY-MM-DD.log.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DeleteModeRow: View {
    let mode: DeleteMode
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.symbolName)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                    Text(mode.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ItemLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PreferencesGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct KeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

private struct OverviewNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ReminderModeNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppIconHero: View {
    private var iconImage: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        Image(nsImage: iconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

// MARK: - DeleteMode helpers

private extension DeleteMode {
    static var allCasesOrdered: [DeleteMode] { [.trash, .live, .dryRun] }

    var title: String {
        switch self {
        case .trash: return "Kosz"
        case .live: return "Trwale usuń"
        case .dryRun: return "Tylko symulacja"
        }
    }

    var summary: String {
        switch self {
        case .trash:
            return "Pliki trafiają do ~/.Trash. To najbezpieczniejszy tryb codziennego użycia."
        case .live:
            return "Usuwa natychmiast i bez możliwości odzyskania. Używaj tylko świadomie."
        case .dryRun:
            return "Nic nie usuwa, tylko pokazuje, co zostałoby wyczyszczone."
        }
    }

    var overviewSummary: String {
        switch self {
        case .trash:
            return "Najbezpieczniejszy tryb codziennego użycia. Czyści to, co wybrałeś, ale zostawia możliwość odzyskania danych z Kosza."
        case .live:
            return "Tryb natychmiastowego usuwania. Najbardziej agresywny i najszybszy, ale bez cofnięcia operacji."
        case .dryRun:
            return "Tryb podglądu. Pozwala zobaczyć, co zostałoby usunięte, bez ruszania plików."
        }
    }

    var symbolName: String {
        switch self {
        case .trash:
            return "tray.full"
        case .live:
            return "exclamationmark.triangle"
        case .dryRun:
            return "eye"
        }
    }
}

private extension ReminderMode {
    static var allCasesOrdered: [ReminderMode] { [.remind, .autoClean, .off] }

    var settingsTitle: String {
        switch self {
        case .off:
            return "Wyłączone"
        case .remind:
            return "Przypomnienie"
        case .autoClean:
            return "Automatyczne czyszczenie"
        }
    }
}

import SwiftUI
import AutoCleanMacCore

/// Observable model trzymający EDYTOWALNE preferencje.
final class SettingsModel: ObservableObject {
    @Published var retentionDays: Int
    @Published var deleteMode: DeleteMode
    @Published var tasks: Config.Tasks
    @Published var browsers: [BrowserIdentity: BrowserPreferences]

    let onApply:    (Config) -> Void
    let onApplyRun: (Config) -> Void
    let onOpenLogsFolder: () -> Void
    let onShowLastLog: () -> Void
    let homeDirectory: URL
    private let baseConfig: Config

    init(initial: Config,
         homeDirectory: URL,
         onApply:            @escaping (Config) -> Void,
         onApplyRun:         @escaping (Config) -> Void,
         onOpenLogsFolder:   @escaping () -> Void,
         onShowLastLog:      @escaping () -> Void) {
        self.baseConfig = initial
        self.retentionDays = initial.retentionDays
        self.deleteMode = initial.deleteMode
        self.tasks = initial.tasks
        self.browsers = initial.browsers
        self.onApply = onApply
        self.onApplyRun = onApplyRun
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

    private func currentConfig() -> Config {
        var updated = baseConfig
        updated.retentionDays = retentionDays
        updated.deleteMode = deleteMode
        updated.tasks = tasks
        updated.browsers = browsers
        return updated
    }

    func apply()    { onApply(currentConfig()) }
    func applyRun() { onApplyRun(currentConfig()) }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("Ogólne", systemImage: "gear") }
            CleanupTab(model: model)
                .tabItem { Label("Czyszczenie", systemImage: "trash") }
            BrowsersTab(model: model)
                .tabItem { Label("Przeglądarki", systemImage: "globe") }
            LogsTab(model: model)
                .tabItem { Label("Logi", systemImage: "doc.text") }
        }
        .frame(width: 560, height: 480)
        .padding()
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Zapisz") { model.apply() }
                Button("Zapisz i wyczyść teraz") { model.applyRun() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Tabs

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Retencja") {
                Stepper(value: $model.retentionDays, in: 1...30) {
                    Text("Przechowuj rzeczy nowsze niż **\(model.retentionDays)** dni")
                }
                Text("Dotyczy zadań które respektują okres retencji (np. logi, Downloads jeśli włączone). Inne zadania usuwają bez względu na wiek.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Tryb usuwania") {
                Picker("", selection: $model.deleteMode) {
                    Text("Kosz (odwracalne, bezpieczne)").tag(DeleteMode.trash)
                    Text("Trwale usuń (rm)").tag(DeleteMode.live)
                    Text("Tylko symulacja (dry-run)").tag(DeleteMode.dryRun)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }
}

private struct CleanupTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Zadania systemowe") {
                Toggle("Cache użytkownika (~/Library/Caches)",             isOn: $model.tasks.userCaches)
                Toggle("System Temp (/tmp, TemporaryItems)",                isOn: $model.tasks.systemTemp)
                Toggle("Kosz (~/.Trash — opróżnianie)",                     isOn: $model.tasks.trash)
                Toggle(".DS_Store (w całym $HOME)",                         isOn: $model.tasks.dsStore)
                Toggle("Logi użytkownika (~/Library/Logs)",                 isOn: $model.tasks.userLogs)
                Toggle("Cache devtools (DerivedData, npm, pip, brew)",      isOn: $model.tasks.devCaches)
                Toggle("Downloads (pliki starsze niż retencja)",            isOn: $model.tasks.downloads)
            }
            Section {
                Text("Zadania respektują ustawienie retencji z zakładki Ogólne tylko tam gdzie to ma sens (logi, Downloads). Cache usuwane są od razu.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BrowsersTab: View {
    @ObservedObject var model: SettingsModel

    private var installed: [BrowserIdentity] {
        BrowserIdentity.allCases.filter { $0.isInstalled(homeDirectory: model.homeDirectory) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if installed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nie wykryto obsługiwanych przeglądarek.")
                        .font(.headline)
                    Text("AutoCleanMac obsługuje Chrome, Firefox, Edge, Brave, Vivaldi, Arc. Safari wymaga dodatkowych uprawnień i pojawi się w następnej wersji.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                Spacer()
            } else {
                Text("Wybierz co wyczyścić (tylko zainstalowane przeglądarki):")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("").frame(minWidth: 140, alignment: .leading)
                        ForEach(BrowserDataType.allCases, id: \.self) { type in
                            Text(type.displayName).bold().frame(minWidth: 90, alignment: .center)
                        }
                    }
                    Divider()
                    ForEach(installed, id: \.self) { browser in
                        GridRow {
                            Text(browser.displayName).frame(minWidth: 140, alignment: .leading)
                            ForEach(BrowserDataType.allCases, id: \.self) { type in
                                Toggle("", isOn: Binding(
                                    get: { model.isOn(browser, type) },
                                    set: { model.toggle(browser, type, $0) }
                                ))
                                .labelsHidden()
                                .accessibilityLabel("\(browser.displayName) — \(type.displayName)")
                                .frame(minWidth: 90, alignment: .center)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label("Ciasteczka = wylogowanie z serwisów.", systemImage: "info.circle")
                    Label("„Historia” czyści też sesje (Current/Last Session) i faviconsy — bez tego przeglądarka wraca do ostatnio otwartych tabów.", systemImage: "exclamationmark.triangle")
                    Label("Dla Firefoxa historia przeglądania jest w tej samej bazie co zakładki (places.sqlite) — jej nie tykamy. Czyścimy tylko autofill i historię pobrań.", systemImage: "exclamationmark.triangle")
                    Label("Pomijamy przeglądarki które są uruchomione — zamknij je przed sprzątaniem.", systemImage: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding()
    }
}

private struct LogsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logi")
                .font(.headline)
            Text("Każde uruchomienie zapisuje zdarzenia do `~/Library/Logs/AutoCleanMac/YYYY-MM-DD.log`.")
                .font(.footnote).foregroundStyle(.secondary)

            HStack {
                Button("Otwórz folder logów") { model.onOpenLogsFolder() }
                Button("Pokaż ostatni log")   { model.onShowLastLog() }
            }

            Spacer()
        }
        .padding()
    }
}

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
        VStack(spacing: 0) {
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

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("Zapisz") { model.apply() }
                Button("Zapisz i wyczyść teraz") { model.applyRun() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .frame(width: 600, height: 540)
    }
}

// MARK: - Tabs

private struct GeneralTab: View {
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
                Text("Dotyczy zadań respektujących okres retencji (logi, Downloads). Pozostałe zadania usuwają bez względu na wiek.")
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                    Text(mode.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CleanupTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.tasks.userCaches) {
                    ItemLabel(title: "Cache użytkownika",
                              detail: "~/Library/Caches")
                }
                Toggle(isOn: $model.tasks.systemTemp) {
                    ItemLabel(title: "System Temp",
                              detail: "/tmp, TemporaryItems")
                }
                Toggle(isOn: $model.tasks.trash) {
                    ItemLabel(title: "Kosz",
                              detail: "Opróżnia ~/.Trash")
                }
                Toggle(isOn: $model.tasks.dsStore) {
                    ItemLabel(title: ".DS_Store",
                              detail: "W całym katalogu domowym")
                }
                Toggle(isOn: $model.tasks.userLogs) {
                    ItemLabel(title: "Logi użytkownika",
                              detail: "~/Library/Logs (respektuje retencję)")
                }
                Toggle(isOn: $model.tasks.devCaches) {
                    ItemLabel(title: "Cache devtools",
                              detail: "DerivedData, npm, pip, brew")
                }
                Toggle(isOn: $model.tasks.downloads) {
                    ItemLabel(title: "Downloads",
                              detail: "Pliki starsze niż retencja")
                }
            } header: {
                Text("Zadania systemowe")
            } footer: {
                Text("Retencję respektują tylko logi i Downloads. Cache usuwane są od razu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                        Text("AutoCleanMac obsługuje Chrome, Firefox, Edge, Brave, Vivaldi, Arc. Safari wymaga dodatkowych uprawnień — pojawi się w następnej wersji.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Przeglądarka")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(BrowserDataType.allCases, id: \.self) { type in
                            Text(type.displayName)
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
                                Toggle("", isOn: Binding(
                                    get: { model.isOn(browser, type) },
                                    set: { model.toggle(browser, type, $0) }
                                ))
                                .labelsHidden()
                                .accessibilityLabel("\(browser.displayName) — \(type.displayName)")
                                .frame(width: 80, alignment: .center)
                            }
                        }
                    }
                } header: {
                    Text("Dane do wyczyszczenia")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Ciasteczka = wylogowanie z serwisów.", systemImage: "info.circle")
                        Label("„Historia” czyści też sesje i faviconsy — bez tego Chromium wraca do ostatnich tabów.", systemImage: "exclamationmark.triangle")
                        Label("Firefox: historia dzieli bazę z zakładkami (places.sqlite) — jej nie tykamy. Czyścimy autofill i historię pobrań.", systemImage: "exclamationmark.triangle")
                        Label("Uruchomione przeglądarki są pomijane — zamknij je przed czyszczeniem.", systemImage: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
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

// MARK: - DeleteMode helpers

private extension DeleteMode {
    static var allCasesOrdered: [DeleteMode] { [.trash, .live, .dryRun] }

    var title: String {
        switch self {
        case .trash:  return "Kosz"
        case .live:   return "Trwale usuń (rm)"
        case .dryRun: return "Tylko symulacja (dry-run)"
        }
    }

    var summary: String {
        switch self {
        case .trash:  return "Pliki trafiają do ~/.Trash. Odwracalne, bezpieczne."
        case .live:   return "Usuwa natychmiast. Zwalnia miejsce od razu, bez odzyskiwania."
        case .dryRun: return "Nic nie usuwa, tylko loguje. Do testów ustawień."
        }
    }
}

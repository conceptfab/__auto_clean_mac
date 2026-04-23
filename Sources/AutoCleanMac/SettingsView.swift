import SwiftUI
import AutoCleanMacCore

/// Observable model trzymający edytowalne preferencje. Zapisywany przez Apply.
final class SettingsModel: ObservableObject {
    @Published var browsers: [BrowserIdentity: BrowserPreferences]

    let onApply:    (Config) -> Void         // tylko zapis
    let onApplyRun: (Config) -> Void         // zapis + natychmiastowe sprzątanie
    private let baseConfig: Config

    init(initial: Config,
         onApply:    @escaping (Config) -> Void,
         onApplyRun: @escaping (Config) -> Void) {
        self.baseConfig = initial
        self.browsers = initial.browsers
        self.onApply = onApply
        self.onApplyRun = onApplyRun
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
            BrowsersTab(model: model)
                .tabItem { Label("Przeglądarki", systemImage: "globe") }
        }
        .frame(width: 520, height: 420)
        .padding()
    }
}

private struct BrowsersTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wybierz co wyczyścić w każdej przeglądarce:")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("").frame(minWidth: 140, alignment: .leading)
                    ForEach(BrowserDataType.allCases, id: \.self) { type in
                        Text(type.displayName).bold().frame(minWidth: 90, alignment: .center)
                    }
                }
                Divider()
                ForEach(BrowserIdentity.allCases, id: \.self) { browser in
                    GridRow {
                        Text(browser.displayName)
                            .frame(minWidth: 140, alignment: .leading)
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
                Label("Dla Firefoxa „Historia” czyści tylko autofill formularzy i historię pobrań. Historia przeglądania i zakładki pozostają (ta sama baza places.sqlite).", systemImage: "exclamationmark.triangle")
                Label("Pomijamy przeglądarki które są uruchomione — zamknij je przed sprzątaniem.", systemImage: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Zapisz") { model.apply() }
                Button("Zapisz i wyczyść teraz") { model.applyRun() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

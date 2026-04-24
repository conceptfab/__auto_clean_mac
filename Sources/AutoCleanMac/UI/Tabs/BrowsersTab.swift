import SwiftUI
import AutoCleanMacCore

struct BrowsersTab: View {
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

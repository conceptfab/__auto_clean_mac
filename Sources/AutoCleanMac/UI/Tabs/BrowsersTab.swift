import SwiftUI
import AppKit
import AutoCleanMacCore

struct BrowsersTab: View {
    @ObservedObject var model: SettingsModel

    // Snapshot of installed browsers, probed once on appear (see `.task` below). Intentionally
    // does not refresh if the user installs/removes a browser while Settings stays open.
    @State private var installed: [BrowserIdentity] = []
    @State private var fullDiskAccessGranted = true

    var body: some View {
        Form {
            if !fullDiskAccessGranted {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Brak Pełnego dostępu do dysku", systemImage: "lock.shield")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("macOS blokuje czyszczenie historii i ciasteczek Chrome/Brave/Edge, bo ich dane leżą w chronionym katalogu Application Support. Cache działa bez tego uprawnienia, ale historia i ciasteczka wymagają Pełnego dostępu do dysku.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Otwórz Pełny dostęp do dysku") {
                                openFullDiskAccessSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Sprawdź ponownie") {
                                fullDiskAccessGranted = FullDiskAccess.isGranted()
                            }
                        }
                        Text("Po dodaniu AutoCleanMac na liście uruchom czyszczenie ponownie. Jeśli aplikacja już jest na liście — usuń ją i dodaj ponownie po tej aktualizacji.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
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
        .task {
            if installed.isEmpty {
                installed = BrowserIdentity.allCases.filter { $0.isInstalled() }
            }
            fullDiskAccessGranted = FullDiskAccess.isGranted()
        }
    }

    private func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

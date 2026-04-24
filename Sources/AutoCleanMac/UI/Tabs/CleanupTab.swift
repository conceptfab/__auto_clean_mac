import SwiftUI
import AutoCleanMacCore

struct CleanupTab: View {
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

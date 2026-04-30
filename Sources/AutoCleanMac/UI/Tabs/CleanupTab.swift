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
                    ItemLabel(title: "Cache devtools", detail: "DerivedData, npm, pip oraz natywne cleanupy narzędzi w trybie live")
                }
                Toggle(isOn: $model.tasks.homebrewCleanup) {
                    ItemLabel(title: "Homebrew cleanup", detail: "Uruchamia brew cleanup --prune; tylko w trybie trwałego usuwania")
                }
                Toggle(isOn: $model.tasks.projectArtifacts) {
                    ItemLabel(title: "Artefakty projektów", detail: "Opcjonalne build cache w ~/dev, ~/Developer, ~/Projects i ~/GitHub")
                }
                Toggle(isOn: $model.tasks.downloads) {
                    ItemLabel(title: "Downloads", detail: "Pliki starsze niż retencja")
                }
            } header: {
                Text("Zadania systemowe")
            } footer: {
                Text("Retencję respektują logi, Downloads, temp i cache devtools. Homebrew i natywne cleanupy devtools działają tylko w trybie trwałego usuwania; artefakty projektów są domyślnie wyłączone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

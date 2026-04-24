import SwiftUI
import AutoCleanMacCore

struct AdvancedTab: View {
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
            Section {
                TextEditor(text: $model.whitelistedCacheAppsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 92)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Wykluczone aplikacje z czyszczenia Cache")
            } footer: {
                Text("Jedna aplikacja na linię. Podaj dokładny Bundle Identifier (np. com.spotify.client). Pamięci podręczne tych programów nie będą ruszane.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

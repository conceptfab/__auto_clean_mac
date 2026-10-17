import SwiftUI
import AutoCleanMacCore

public struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                Toggle(model.launchAtLoginTitle, isOn: $model.launchAtLogin)
            } header: {
                Text("Autostart")
            } footer: {
                Text(model.launchAtLoginFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if model.showsGlobalShortcutOption {
                Section {
                    Toggle("Włącz globalny skrót (Cmd+Shift+C)", isOn: $model.globalShortcutEnabled)
                } header: {
                    Text("Skróty Klawiszowe")
                } footer: {
                    Text("Po włączeniu naciśnij Cmd+Shift+C z dowolnego miejsca w systemie, aby wywołać okno Skanera.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Usuwanie", value: model.deleteMode.title)
                LabeledContent("Poziom ryzyka", value: model.riskLabel)
                LabeledContent("Retencja", value: "\(model.retentionDays) dni")
            } header: {
                Text("Obecne ustawienia (informacyjnie)")
            }

            Section {
                LabeledContent("Zadania systemowe", value: model.enabledTaskSummary)
                LabeledContent("Przeglądarki", value: model.browserSelectionsSummary)
            } header: {
                Text("Zakres czyszczenia")
            }
        }
        .formStyle(.grouped)
    }
}

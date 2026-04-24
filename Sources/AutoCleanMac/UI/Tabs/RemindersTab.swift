import SwiftUI
import AutoCleanMacCore

struct RemindersTab: View {
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

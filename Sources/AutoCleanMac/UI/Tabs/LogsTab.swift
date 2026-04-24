import SwiftUI
import AutoCleanMacCore

struct LogsTab: View {
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

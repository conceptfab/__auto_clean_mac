import SwiftUI
import AutoCleanMacCore

public struct OrphanCleanerTab: View {
    @ObservedObject var settingsModel: SettingsModel
    @State private var showingConfirmation = false

    public init(settingsModel: SettingsModel) {
        self.settingsModel = settingsModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Osierocone preferencje")
                    .font(.headline)
                Spacer()
                if settingsModel.orphansScanning {
                    ProgressView().controlSize(.small)
                }
                Button("Skanuj") {
                    Task { await settingsModel.scanOrphans() }
                }
                .disabled(settingsModel.orphansScanning)
            }
            .padding()

            if settingsModel.orphans.isEmpty {
                Spacer()
                Text(settingsModel.orphansScanning ? "Skanowanie..." : "Brak osieroconych preferencji.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $settingsModel.selectedOrphans) {
                    ForEach(settingsModel.orphans) { group in
                        Section(group.bundleID) {
                            ForEach(group.paths, id: \.url) { path in
                                HStack {
                                    Text(path.url.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(ByteFormatting.string(path.bytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(group.id)
                    }
                }
                .listStyle(.inset)

                HStack {
                    Text("Wybrano: \(settingsModel.selectedOrphans.count) grup")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showingConfirmation = true
                    } label: {
                        Text("Usuń zaznaczone")
                    }
                    .disabled(settingsModel.selectedOrphans.isEmpty || settingsModel.orphansScanning)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .alert("Usunąć \(selectedPaths.count) elementów?", isPresented: $showingConfirmation) {
            Button("Usuń", role: .destructive) {
                Task { await settingsModel.removeSelectedOrphans() }
            }
            Button("Anuluj", role: .cancel) { }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var selectedPaths: [URL] {
        settingsModel.orphans
            .filter { settingsModel.selectedOrphans.contains($0.id) }
            .flatMap { $0.paths.map(\.url) }
    }

    /// Lista ścieżek do potwierdzenia (przycięta, żeby alert nie wyszedł poza ekran).
    private var confirmationMessage: String {
        let paths = selectedPaths
        let limit = 15
        var lines = paths.prefix(limit).map { "• \($0.path)" }
        if paths.count > limit {
            lines.append("…oraz \(paths.count - limit) więcej.")
        }
        return "Tryb usuwania: \(settingsModel.deleteMode.title).\n\n" + lines.joined(separator: "\n")
    }
}

import SwiftUI
import AutoCleanMacCore

struct OrphanCleanerTab: View {
    @ObservedObject var settingsModel: SettingsModel

    var body: some View {
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
                        Task { await settingsModel.removeSelectedOrphans() }
                    } label: {
                        Text("Usuń zaznaczone")
                    }
                    .disabled(settingsModel.selectedOrphans.isEmpty || settingsModel.orphansScanning)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}

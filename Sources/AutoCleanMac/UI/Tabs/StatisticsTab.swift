import SwiftUI
import AutoCleanMacCore

struct StatisticsTab: View {
    @ObservedObject var model: SettingsModel

    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    private var totalBytesString: String {
        Self.bytesFormatter.string(fromByteCount: model.statistics.totalBytesFreed)
    }

    private var lastCleanupString: String {
        guard let date = model.statistics.lastCleanupAt else {
            return "Jeszcze nie było cleanupu"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreferencesGroup("Od instalacji") {
                    KeyValueRow(title: "Zwolnione miejsce", value: totalBytesString)
                    KeyValueRow(title: "Usunięte pliki", value: "\(model.statistics.totalItemsDeleted)")
                    KeyValueRow(title: "Uruchomienia cleanupu", value: "\(model.statistics.totalRuns)")
                    KeyValueRow(title: "Ostatni cleanup", value: lastCleanupString)
                }

                if !model.statistics.recentRuns.isEmpty {
                    PreferencesGroup("Ostatnie cleanupy") {
                        ForEach(model.statistics.recentRuns, id: \.cleanedAt) { run in
                            CleanupHistoryRow(run: run)
                        }
                    }
                }

                PreferencesGroup("Co obejmują statystyki") {
                    OverviewNote(
                        title: "Wliczane są prawdziwe cleanupy",
                        text: "Liczniki rosną po realnym uruchomieniu cleanupu z menu, preferencji, launchd albo automatycznego harmonogramu."
                    )
                    OverviewNote(
                        title: "Podgląd nie zawyża liczb",
                        text: "Tryb preview pokazuje symulację, ale nie dopisuje nic do statystyk od instalacji."
                    )
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CleanupHistoryRow: View {
    let run: CleanupRunRecord

    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    private var bytesString: String {
        Self.bytesFormatter.string(fromByteCount: run.bytesFreed)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.cleanedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Text("\(run.itemsDeleted) plik. · \(String(format: "%.1f", Double(run.durationMs) / 1000.0))s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(bytesString)
                    .font(.subheadline.weight(.medium))
                if run.warningsCount > 0 {
                    Text("\(run.warningsCount) ostrz.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

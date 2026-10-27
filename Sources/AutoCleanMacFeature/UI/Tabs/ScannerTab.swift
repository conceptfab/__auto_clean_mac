import SwiftUI
import AutoCleanMacCore

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var results: [(name: String, result: TaskResult)] = []
    @Published var totalBytes: Int64 = 0
    @Published var totalItems: Int = 0
    @Published var errorMessage: String?

    func scan(config: Config) async {
        results.removeAll()
        totalBytes = 0
        totalItems = 0
        errorMessage = nil

        // Brak miejsca na dysku / plik w miejscu katalogu nie może wywrócić całego huba —
        // pokazujemy błąd zamiast `try!`.
        let tempLogDir = FileManager.default.temporaryDirectory.appendingPathComponent("AutoCleanMacScannerLogs")
        let logger: Logger
        do {
            logger = try Logger(directory: tempLogDir)
        } catch {
            NSLog("AutoCleanMac: failed to create scanner logger at \(tempLogDir.path): \(error)")
            errorMessage = "Nie udało się przygotować skanowania: \(error.localizedDescription)"
            hasScanned = false
            return
        }
        isScanning = true
        let deleter = SafeDeleter(mode: .dryRun, logger: logger)
        let ctx = CleanupContext(
            retentionDays: config.retentionDays,
            deleter: deleter,
            logger: logger,
            excludedPaths: config.resolvedExcludedPathURLs()
        )
        let engine = CleanupEngine.makeDefault(config: config)
        
        let _ = await engine.run(context: ctx) { @MainActor [weak self] event in
            guard let self else { return }
            switch event {
            case .taskFinished(let name, let result):
                if !result.skipped {
                    self.results.append((name, result))
                    self.totalBytes += result.bytesFreed
                    self.totalItems += result.itemsDeleted
                }
            default:
                break
            }
        }
        
        isScanning = false
        hasScanned = true
    }
}

public struct ScannerTab: View {
    @ObservedObject var settingsModel: SettingsModel
    @StateObject private var viewModel = ScannerViewModel()

    public init(settingsModel: SettingsModel) {
        self.settingsModel = settingsModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                if viewModel.isScanning {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Skanowanie systemu...")
                        .font(.headline)
                } else if viewModel.hasScanned {
                    Image(systemName: viewModel.totalBytes > 0 ? "trash.circle.fill" : "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(viewModel.totalBytes > 0 ? .orange : .green)
                    Text(viewModel.totalBytes > 0 ? "Można zwolnić miejsce" : "Twój Mac jest czysty!")
                        .font(.headline)
                    if viewModel.totalBytes > 0 {
                        Text("\(ByteFormatting.string(viewModel.totalBytes)) w \(viewModel.totalItems) plikach")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.orange)
                    Text("Skanowanie nie powiodło się")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Image(systemName: "sparkles")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.blue)
                    Text("Gotowy do skanowania")
                        .font(.headline)
                    Text("Sprawdź, ile miejsca zajmują zbędne pliki i pamięci podręczne.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // List
            if viewModel.hasScanned || viewModel.isScanning {
                List {
                    ForEach(viewModel.results, id: \.name) { item in
                        HStack {
                            Text(item.name)
                                .font(.body)
                            Spacer()
                            if item.result.bytesFreed > 0 {
                                Text(ByteFormatting.string(item.result.bytesFreed))
                                    .font(.body)
                                    .monospacedDigit()
                            } else {
                                Text("Czysto")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button {
                    Task {
                        await viewModel.scan(config: settingsModel.currentConfig())
                    }
                } label: {
                    Text(viewModel.hasScanned ? "Skanuj ponownie" : "Skanuj")
                }
                .disabled(viewModel.isScanning)
                
                Spacer()
                
                Button(role: .destructive) {
                    settingsModel.applyRun()
                } label: {
                    Text("Wyczyść teraz")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning || !viewModel.hasScanned || viewModel.totalBytes == 0)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

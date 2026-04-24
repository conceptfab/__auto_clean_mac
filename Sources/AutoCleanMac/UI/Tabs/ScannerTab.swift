import SwiftUI
import AutoCleanMacCore

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var results: [(name: String, result: TaskResult)] = []
    @Published var totalBytes: Int64 = 0
    @Published var totalItems: Int = 0

    func scan(config: Config) async {
        isScanning = true
        results.removeAll()
        totalBytes = 0
        totalItems = 0
        
        let tempLogDir = FileManager.default.temporaryDirectory.appendingPathComponent("AutoCleanMacScannerLogs")
        let logger = try! Logger(directory: tempLogDir)
        let deleter = SafeDeleter(mode: .dryRun, logger: logger)
        let ctx = CleanupContext(
            retentionDays: config.retentionDays,
            deleter: deleter,
            deletionMode: .dryRun,
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


struct ScannerTab: View {
    @ObservedObject var settingsModel: SettingsModel
    @StateObject private var viewModel = ScannerViewModel()
    
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()
    
    var body: some View {
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
                        Text("\(Self.bytesFormatter.string(fromByteCount: viewModel.totalBytes)) w \(viewModel.totalItems) plikach")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
                                Text(Self.bytesFormatter.string(fromByteCount: item.result.bytesFreed))
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
                        // Pobieramy config z settingsModel za pomocą reflection lub przez wymuszenie,
                        // ale tu możemy po prostu uzyć opcji apply/preview
                        // Najlepiej dodać metodę currentConfig do publicznego dostępu lub zduplikować logikę.
                        // Ale czekaj, nie mamy bezpośrednio metody `currentConfig()` dostępnej. Zróbmy w modelu!
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

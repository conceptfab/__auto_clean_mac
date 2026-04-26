import SwiftUI
import AutoCleanMacCore

@MainActor
final class UninstallerViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var isScanning = false
    @Published var searchText = ""
    @Published var selectedAppIDs = Set<UUID>()
    @Published var isUninstalling = false
    @Published var uninstalledCount = 0
    @Published var lastFreedBytes: Int64 = 0
    
    private let scanner = AppScanner()
    private let homeDirectory: URL
    
    init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
    }
    
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    func scan() async {
        isScanning = true
        let scanned = await scanner.scanApps(homeDirectory: homeDirectory)
        self.apps = scanned
        self.isScanning = false
    }
}

struct UninstallerTab: View {
    @StateObject private var viewModel: UninstallerViewModel
    @ObservedObject var settingsModel: SettingsModel
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    init(settingsModel: SettingsModel) {
        self.settingsModel = settingsModel
        _viewModel = StateObject(wrappedValue: UninstallerViewModel(homeDirectory: settingsModel.homeDirectory))
    }
    
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Deinstalator Aplikacji")
                    .font(.headline)
                Spacer()
                if viewModel.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                    Text("Skanowanie...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(viewModel.apps.count) programów")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Szukaj aplikacji...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // List
            List(selection: $viewModel.selectedAppIDs) {
                ForEach(viewModel.filteredApps) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(app.name)
                                .font(.body)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(Self.bytesFormatter.string(fromByteCount: app.totalSize))
                                .font(.body)
                            if app.leftoversSize > 0 {
                                Text("\(Self.bytesFormatter.string(fromByteCount: app.leftoversSize)) resztek")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(app.id)
                }
            }
            .listStyle(.inset)
            .disabled(viewModel.isUninstalling || viewModel.isScanning)
            
            // Footer
            HStack {
                if viewModel.uninstalledCount > 0 {
                    Text("Usunięto \(viewModel.uninstalledCount) aplikacji. Zwolniono \(Self.formatFreed(viewModel.lastFreedBytes)).")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Text("Zaznacz aplikacje do usunięcia. Pliki zostaną usunięte zgodnie z trybem (\(settingsModel.deleteMode.title)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    Task {
                        await uninstallSelected()
                    }
                } label: {
                    Text("Odinstaluj wybrane (\(viewModel.selectedAppIDs.count))")
                }
                .disabled(viewModel.selectedAppIDs.isEmpty || viewModel.isUninstalling || viewModel.isScanning)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task {
            if viewModel.apps.isEmpty {
                await viewModel.scan()
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func uninstallSelected() async {
        guard !viewModel.selectedAppIDs.isEmpty else { return }
        viewModel.isUninstalling = true
        
        let toUninstall = viewModel.apps.filter { viewModel.selectedAppIDs.contains($0.id) }
        
        let safeDeleterMode: SafeDeleter.Mode
        switch settingsModel.deleteMode {
        case .live: safeDeleterMode = .live
        case .dryRun: safeDeleterMode = .dryRun
        case .trash: safeDeleterMode = .trash
        }
        
        let outcome = await settingsModel.onUninstall(toUninstall, safeDeleterMode)
        let attempted = toUninstall.count

        viewModel.lastFreedBytes = outcome.freedBytes
        viewModel.uninstalledCount = outcome.succeeded
        viewModel.selectedAppIDs.removeAll()

        await viewModel.scan()
        viewModel.isUninstalling = false

        let freedText = Self.formatFreed(outcome.freedBytes)
        let failureLines = outcome.failures
            .prefix(5)
            .map { "• \($0.appName): \($0.reason)" }
            .joined(separator: "\n")
        let extraFailures = max(0, outcome.failures.count - 5)
        let failureSuffix: String = {
            guard !outcome.failures.isEmpty else { return "" }
            let header = "\n\nNie udało się usunąć \(outcome.failures.count) z \(attempted):\n"
            let tail = extraFailures > 0 ? "\n…oraz \(extraFailures) więcej." : ""
            return header + failureLines + tail
        }()

        if outcome.succeeded > 0 {
            alertTitle = outcome.failures.isEmpty ? "Operacja zakończona" : "Operacja zakończona z błędami"
            let verb = safeDeleterMode == .dryRun ? "Zwolnionoby" : "Zwolniono"
            let action = safeDeleterMode == .dryRun ? "Symulacja: usunięto" : "Usunięto"
            alertMessage = "\(action) \(outcome.succeeded) z \(attempted) aplikacji.\n\(verb) \(freedText).\(failureSuffix)"
        } else {
            alertTitle = "Nie usunięto żadnych aplikacji"
            alertMessage = outcome.failures.isEmpty
                ? "Operacja została zablokowana."
                : "Żadna aplikacja nie została usunięta.\(failureSuffix)"
        }
        showingAlert = true
    }

    private static func formatFreed(_ bytes: Int64) -> String {
        bytes <= 0 ? "0 KB" : Self.bytesFormatter.string(fromByteCount: bytes)
    }
}

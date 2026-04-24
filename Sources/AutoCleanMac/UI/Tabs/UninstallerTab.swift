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
                    Text("Usunięto \(viewModel.uninstalledCount) aplikacji. Zwolniono \(Self.bytesFormatter.string(fromByteCount: viewModel.lastFreedBytes)).")
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
        
        let (freed, count) = await settingsModel.onUninstall(toUninstall, safeDeleterMode)
        
        viewModel.lastFreedBytes = freed
        viewModel.uninstalledCount = count
        viewModel.selectedAppIDs.removeAll()
        
        await viewModel.scan()
        viewModel.isUninstalling = false
        
        if count > 0 {
            alertTitle = "Operacja zakończona"
            if safeDeleterMode == .dryRun {
                alertMessage = "Symulacja zakończona.\nZwolnionoby \(Self.bytesFormatter.string(fromByteCount: freed)) z \(count) aplikacji."
            } else {
                alertMessage = "Pomyślnie usunięto \(count) aplikacji.\nZwolniono \(Self.bytesFormatter.string(fromByteCount: freed))."
            }
        } else {
            alertTitle = "Uwaga"
            alertMessage = "Nie usunięto żadnych aplikacji (błąd lub operacja zablokowana)."
        }
        showingAlert = true
    }
}

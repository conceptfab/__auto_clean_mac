import SwiftUI

final class ConsoleViewModel: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let prefix: String // "✓", "⚠", "✗", "•"
        let text: String
    }

    @Published var lines: [Line] = []
    @Published var title: String = "AutoCleanMac"
    @Published var subtitle: String = "Przygotowywanie uruchomienia"
    @Published var statusBadge: String = "cleanup"
    @Published var statusColor: Color = .green
    @Published var currentTask: String? = nil
    @Published var completedTasks: Int = 0
    @Published var totalTasks: Int = 0
    @Published var currentRunItemsDeleted: Int = 0
    @Published var currentRunBytesFreed: Int64 = 0
    @Published var warningsCount: Int = 0
    @Published var skippedCount: Int = 0
    @Published var lifetimeRuns: Int = 0
    @Published var lifetimeItemsDeleted: Int = 0
    @Published var lifetimeBytesFreed: Int64 = 0
    @Published var summary: String? = nil
    @Published var finished: Bool = false

    var progressValue: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    var progressText: String {
        totalTasks == 0 ? "Oczekiwanie" : "\(completedTasks)/\(totalTasks) kroków"
    }

    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    var currentRunBytesText: String {
        Self.bytesFormatter.string(fromByteCount: currentRunBytesFreed)
    }

    var lifetimeBytesText: String {
        Self.bytesFormatter.string(fromByteCount: lifetimeBytesFreed)
    }
}

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.title)
                        .font(.title3.weight(.semibold))
                    Text(model.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.statusBadge)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.progressText)
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text("ostrzeżenia: \(model.warningsCount) · pominięte: \(model.skippedCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: model.progressValue)
                    .tint(Color.accentColor)

                if let currentTask = model.currentTask {
                    Text("Teraz: \(currentTask)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("ten cleanup: \(model.currentRunItemsDeleted) plik. · \(model.currentRunBytesText)")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text("od instalacji: \(model.lifetimeItemsDeleted) plik. · \(model.lifetimeBytesText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.prefix)
                                    .frame(width: 14, alignment: .leading)
                                Text(line.text)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.vertical, 1)
                            .id(line.id)
                        }
                    }
                }
                .onChange(of: model.lines.count) { _ in
                    if let last = model.lines.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let summary = model.summary {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Podsumowanie")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("Łącznie od instalacji: \(model.lifetimeRuns) cleanupów · \(model.lifetimeItemsDeleted) plik. · \(model.lifetimeBytesText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(width: 600, height: 500)
    }
}

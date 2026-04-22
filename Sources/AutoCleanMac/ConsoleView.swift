import SwiftUI

final class ConsoleViewModel: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let prefix: String // "✓", "⚠", "✗", "•"
        let text: String
    }
    @Published var lines: [Line] = []
    @Published var summary: String? = nil
    @Published var finished: Bool = false
}

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("🧹  AutoCleanMac")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Divider().opacity(0.4)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.prefix)
                                    .frame(width: 14, alignment: .leading)
                                Text(line.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11, design: .monospaced))
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
                Text(summary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .frame(width: 480, height: 320)
    }
}

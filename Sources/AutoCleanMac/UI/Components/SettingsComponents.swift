import SwiftUI
import AutoCleanMacCore

// MARK: - Components

struct DeleteModeRow: View {
    let mode: DeleteMode
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.symbolName)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                    Text(mode.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ItemLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct PreferencesGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct KeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct OverviewNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ReminderModeNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AppIconHero: View {
    private var iconImage: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        Image(nsImage: iconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

// MARK: - Helpers

extension DeleteMode {
    static var allCasesOrdered: [DeleteMode] { [.trash, .live, .dryRun] }

    var title: String {
        switch self {
        case .trash: return "Kosz"
        case .live: return "Trwale usuń"
        case .dryRun: return "Tylko symulacja"
        }
    }

    var summary: String {
        switch self {
        case .trash:
            return "Pliki trafiają do ~/.Trash. To najbezpieczniejszy tryb codziennego użycia."
        case .live:
            return "Usuwa natychmiast i bez możliwości odzyskania. Używaj tylko świadomie."
        case .dryRun:
            return "Nic nie usuwa, tylko pokazuje, co zostałoby wyczyszczone."
        }
    }

    var overviewSummary: String {
        switch self {
        case .trash:
            return "Najbezpieczniejszy tryb codziennego użycia. Czyści to, co wybrałeś, ale zostawia możliwość odzyskania danych z Kosza."
        case .live:
            return "Tryb natychmiastowego usuwania. Najbardziej agresywny i najszybszy, ale bez cofnięcia operacji."
        case .dryRun:
            return "Tryb podglądu. Pozwala zobaczyć, co zostałoby usunięte, bez ruszania plików."
        }
    }

    var symbolName: String {
        switch self {
        case .trash:
            return "tray.full"
        case .live:
            return "exclamationmark.triangle"
        case .dryRun:
            return "eye"
        }
    }
}

extension ReminderMode {
    static var allCasesOrdered: [ReminderMode] { [.remind, .autoClean, .off] }

    var settingsTitle: String {
        switch self {
        case .off:
            return "Wyłączone"
        case .remind:
            return "Przypomnienie"
        case .autoClean:
            return "Automatyczne czyszczenie"
        }
    }
}

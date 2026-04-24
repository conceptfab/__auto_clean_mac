import SwiftUI

struct AboutTab: View {
    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?) where short != build:
            return "Wersja \(short) (\(build))"
        case let (short?, _):
            return "Wersja \(short)"
        case let (_, build?):
            return "Build \(build)"
        default:
            return "Wersja lokalna"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 18) {
                    AppIconHero()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("AutoCleanMac")
                            .font(.title2.weight(.semibold))
                        Text(versionString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Lekka aplikacja do bezpiecznego czyszczenia cache, logów, danych przeglądarek i innych śmieci, które z czasem zapychają macOS.")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                PreferencesGroup("O aplikacji") {
                    OverviewNote(
                        title: "Po co istnieje AutoCleanMac",
                        text: "Pomaga odzyskać miejsce bez ręcznego przeklikiwania się przez ukryte katalogi i bez agresywnego czyszczenia wszystkiego na ślepo."
                    )
                    OverviewNote(
                        title: "Jak działa",
                        text: "Aplikacja czyści wybrane obszary systemu zgodnie z Twoimi preferencjami, z trybem podglądu, przypomnieniami i bezpieczniejszym domyślnym usuwaniem do Kosza."
                    )
                }

                PreferencesGroup("Twórca") {
                    HStack {
                        Text("CONCEPTFAB.COM")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Link("Otwórz stronę", destination: URL(string: "https://conceptfab.com")!)
                    }
                }

            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

# Plan Rozwoju i Poprawek: AutoCleanMac

Poniższy dokument przedstawia propozycje zmian architektonicznych, nowych funkcjonalności oraz usprawnień UX dla aplikacji AutoCleanMac.

> [!NOTE]
> Projekt jest stabilny i posiada doskonałe pokrycie testami (83 zielone testy). Zaproponowane zmiany mają na celu lepszą organizację kodu oraz dodanie funkcji oczekiwanych od dojrzałych "czyścików" dla systemu macOS.

## Oczekiwana decyzja użytkownika

Zanim przystąpimy do pisania kodu, proszę o wskazanie, które z poniższych punktów chciałbyś zrealizować w pierwszej kolejności. Możemy zacząć od prostej refaktoryzacji, albo od razu przejść do wdrażania nowych funkcji.

---

## 1. Architektura i Kod (Refaktoryzacja)

Obecna architektura jest solidna, jednak pewne elementy interfejsu zaczynają puchnąć.

### 1.1. Rozbicie `SettingsView.swift`
Plik z ustawieniami osiągnął prawie 900 linii ze względu na przechowywanie wszystkich zakładek (Tabs) w jednym miejscu.
- **Działanie:** Wydzielenie prywatnych struktur (np. `GeneralTab`, `CleanupTab`, `BrowsersTab`) do osobnych plików w katalogu `Sources/AutoCleanMac/UI/Tabs/`.
- **Zalety:** Znaczna poprawa czytelności i ułatwienie przyszłego dodawania nowych opcji.

### 1.2. Przejście na natywne cykle życia SwiftUI (Opcjonalnie)
Aplikacja obecnie korzysta z `AppDelegate` i ręcznie tworzy `NSWindow` dla ustawień.
- **Działanie:** Wykorzystanie struktury `App`, `MenuBarExtra` i `Window` (natywnych dla macOS 13+).
- **Zalety:** Zmniejszenie ilości kodu zarządzającego oknami i zbliżenie aplikacji do nowoczesnych standardów SwiftUI.

---

## 2. Nowe Funkcjonalności

Propozycje dodające realną wartość dla końcowego użytkownika.

### 2.1. Pełne wsparcie dla Safari
Obecnie Safari jest pomijane ze względu na restrykcje systemowe (Full Disk Access).
- **Działanie:** Dodanie przycisku "Odblokuj Safari" w ustawieniach przeglądarek, otwierającego panel `Full Disk Access` w Ustawieniach Systemowych. Zaimplementowanie czyszczenia dla `~/Library/Containers/com.apple.Safari`.
- **Zalety:** Pełne pokrycie dla wszystkich najpopularniejszych przeglądarek na Macu.

### 2.2. Deinstalator Aplikacji (Uninstaller)
- **Działanie:** Dodanie nowego zadania i zakładki w UI, która skanuje zainstalowane programy, a następnie pozwala na ich usunięcie wraz z powiązanymi danymi z `~/Library/Application Support/`, `~/Library/Caches/` itp.
- **Zalety:** Znaczące podniesienie rangi aplikacji z prostego czyścika do kompleksowego narzędzia konserwacji.

### 2.3. Selektywne pobrane (Downloads)
- **Działanie:** Wzbogacenie zadania `DownloadsTask` o filtry pozwalające zachować określone typy plików. Np. usuwanie tylko obrazów dysków (`.dmg`) i archiwów (`.zip`, `.pkg`).
- **Zalety:** Bezpieczeństwo. Minimalizuje ryzyko usunięcia ważnych dokumentów użytkownika z folderu Pobrane.

### 2.4. Whitelisting dla Cache Aplikacji
- **Działanie:** Dodanie wizualnej listy programów przy czyszczeniu cache'u (`User Caches`), z możliwością odznaczenia tych, których nie chcemy ruszać (np. Spotify, Final Cut Pro).
- **Zalety:** Lepsza kontrola dla zaawansowanych użytkowników.

---

## 3. Usprawnienia UX / Interfejsu

### 3.1. Natywne Powiadomienia w tle (UserNotifications)
- **Działanie:** Zastąpienie okna `ConsoleWindow` podczas automatycznych działań w tle natywnymi powiadomieniami systemu macOS (np. *"AutoCleanMac: Zwolniono 1.5 GB"*).
- **Zalety:** Dyskrecja i zgodność z filozofią działania w tle na macOS.

### 3.2. Skaner i podgląd miejsca
- **Działanie:** Przebudowa funkcji `Preview` na skaner dysku prezentujący graficzny wykres objętościowy (system, aplikacje, przeglądarki).
- **Zalety:** Większa atrakcyjność wizualna aplikacji.

### 3.3. Globalne Skróty Klawiszowe
- **Działanie:** Rejestracja globalnego skrótu (np. `Cmd + Shift + C`), który natychmiast wywołuje sprzątanie w tle.
- **Zalety:** Wygoda i szybkość działania.

---

## Plan Weryfikacji (Verification Plan)

Dla każdej wprowadzonej zmiany zostaną podjęte następujące kroki:
1. **Zgodność z testami:** Utrzymanie (lub rozszerzenie) 100% sprawności obecnego zestawu testów (aktualnie 83 testy w `AutoCleanMacTests`).
2. **Kompilacja i Lintowanie:** Zapewnienie, że `swift build` przechodzi bez ostrzeżeń.
3. **Manualny test end-to-end:** W przypadku zmian wpływających na system (np. deinstalator lub Safari) przeprowadzenie ręcznej weryfikacji usuniętych plików.

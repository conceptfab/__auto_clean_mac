# Port funkcji z MacSai → AutoCleanMac — Plan implementacji

> **Dla agentów:** WYMAGANA SUB-SKILL: `superpowers:subagent-driven-development` lub `superpowers:executing-plans` do realizacji task-by-task. Kroki używają checkboxów (`- [ ]`) do śledzenia. TDD obowiązuje wszędzie (RED → GREEN → REFACTOR).

**Data:** 2026-06-27
**Źródło:** `MacSai-main/` (MacClean / „Mac Sai", BSD-3-Clause, Swift 6 / macOS 14)
**Cel:** `AutoCleanMac` (menu-bar / LaunchAgent, Swift 5.9 / macOS 13)

---

## Cel ogólny

Przenieść do `AutoCleanMac` najwartościowsze, samowystarczalne fragmenty logiki z `MacSai-main` — przede wszystkim z biblioteki `MacCleanKit` (czysty Foundation, bez GRDB) — adaptując je do Swift 5.9 / macOS 13 i lekkiej architektury menu-bar. **Nie** przenosimy ciężkich widoków SwiftUI ani warstwy GRDB.

## Założenia architektoniczne

- Logika trafia do `Sources/AutoCleanMacCore`, UI (jeśli trzeba) do `Sources/AutoCleanMac/UI/Tabs`.
- Każdy port jest **adaptowany**, nie kopiowany 1:1: usuwamy zależności od `MacCleanKit.L10n`, `MCConstants`, modeli `FileItem`/`AppInfo` MacSai — albo przenosimy minimalne wersje tych typów.
- Zachowujemy istniejące wzorce projektu: `protocol` + shell-backed impl (jak `LaunchServicesClient`), `CleanupTask`/`CleanupContext`, wstrzykiwanie zależności, spies w testach.
- Swift 5.9: zamieniamy składnię `switch` zwracającą wartość bez `return` (Swift 6) na poprawną dla 5.9; pilnujemy `Sendable`/aktorów tylko tam, gdzie potrzeba.
- macOS 13: weryfikujemy dostępność API (np. `URL.path(percentEncoded:)` jest OK od macOS 13).

## Wymóg licencyjny (BLOKUJĄCY — Task 0)

MacSai jest na **BSD-3-Clause**. Port wymaga:
1. Zachowania noty copyright + tekstu licencji.
2. Zakazu używania nazwy „Mac Sai" / nazwisk autorów do promocji.

**Task 0 musi być zrobiony przed mergem dowolnego portu.**

---

## Task 0: Atrybucja licencyjna (BLOKUJĄCY)

**Pliki:**
- Utwórz: `THIRD_PARTY_NOTICES.md` w korzeniu repo.

- [ ] **Krok 1:** Utwórz `THIRD_PARTY_NOTICES.md` zawierający:
  - Nagłówek „Portions of this software are derived from Mac Sai (MacClean)".
  - Pełny tekst `MacSai-main/LICENSE` (BSD-3-Clause, Copyright (c) 2026, Mac Sai Contributors).
  - Listę plików `AutoCleanMac`, które zawierają kod pochodny (uzupełniana w kolejnych taskach).
- [ ] **Krok 2:** W każdym ported pliku Swift dodaj nagłówek-komentarz:
  `// Derived from Mac Sai (MacClean), BSD-3-Clause. See THIRD_PARTY_NOTICES.md`
- [ ] **Krok 3:** Weryfikacja: `THIRD_PARTY_NOTICES.md` istnieje i zawiera pełny tekst licencji.

---

## FAZA 1 — Maintenance / Optimize (najwyższy priorytet)

Port `MacCleanKit/MaintenanceTask.swift` → nowa zakładka „Maintenance" w oknie ustawień. Zgodne z istniejącym `TODO.md` (kategoria „Optimize"). Mały nakład, duża wartość.

### Task 1.1: `MaintenanceTask` (pure data) w Core

**Pliki:**
- Utwórz: `Sources/AutoCleanMacCore/MaintenanceTask.swift`
- Test: `Tests/AutoCleanMacCoreTests/MaintenanceTaskTests.swift`

- [ ] **Krok 1 (RED):** Test sprawdzający, że każdy `MaintenanceTask` ma niepusty `title`, `icon`, `description`, poprawny `severity` i (dla zadań komendowych) `systemCommand` z absolutną ścieżką do egzekutywy.
- [ ] **Krok 2 (GREEN):** Przenieś enum z MacSai, ale:
  - Usuń `L10n.tr(...)` → zostaw same stringi angielskie (lub PL, do decyzji — projekt jest EN-only).
  - Zamień `MCConstants.maxFilesPerOperation` itp. (tu nieobecne).
  - Dostosuj składnię `switch` do Swift 5.9 (dodaj `return` jeśli wymaga kompilator).
  - Zachowaj `severity` (.safe/.advanced), `requiresAdmin`, `systemCommand`, `dockerCandidatePaths`, `resolveDockerPath`.
- [ ] **Krok 3 (GREEN):** Testy zielone.
- [ ] **Krok 4:** Dodaj plik do `THIRD_PARTY_NOTICES.md`.

### Task 1.2: `MaintenanceExecutor` (wykonanie)

**Pliki:**
- Utwórz: `Sources/AutoCleanMacCore/MaintenanceExecutor.swift`
- Test: `Tests/AutoCleanMacCoreTests/MaintenanceExecutorTests.swift`

- [ ] **Krok 1 (RED):** Test ze spy/fake `ProcessRunner` (protokół), sprawdzający że:
  - zadanie `.safe` bez admina woła egzekutywę z poprawnymi argumentami,
  - zadanie `requiresAdmin == true` idzie przez ścieżkę elewacji (reuse istniejącego `ElevatedUninstall`/mechanizmu auth),
  - `.speedUpMail`/`.pruneDocker` (systemCommand == nil) mają dedykowaną obsługę (Mail: usunięcie pliku Envelope Index; Docker: `resolveDockerPath` + `system prune`).
- [ ] **Krok 2 (GREEN):** Zaimplementuj `MaintenanceExecutor` jako `protocol` + impl, wstrzykiwany runner. Wzór: istniejące `*Client.swift`.
- [ ] **Krok 3:** Obsłuż anulowanie (long-running) przez `Task.isCancelled`.
- [ ] **Krok 4:** Testy zielone, dopisz do NOTICES.

### Task 1.3: Zakładka UI „Maintenance"

**Pliki:**
- Utwórz: `Sources/AutoCleanMac/UI/Tabs/MaintenanceTab.swift`
- Zmień: `Sources/AutoCleanMac/SettingsView.swift` (dodaj case w `SettingsSection`)
- Zmień: `Sources/AutoCleanMac/AppDelegate.swift` (wiring egzekutora)
- Test: `Tests/AutoCleanMacTests/` (jeśli istnieje test nawigacji ustawień — dopisz case)

- [ ] **Krok 1:** Dodaj nowy case do enuma `SettingsSection` (tytuł + symbol SF) — wzór: jak dodano `OrphanCleaner` (zob. memory S987/1217).
- [ ] **Krok 2:** Zbuduj `MaintenanceTab`: lista zadań z `severity` badge, przycisk „Run", modal potwierdzenia dla `.advanced` (pokazuje `sideEffects`), „Run All" pomija `.advanced`.
- [ ] **Krok 3:** Wepnij `MaintenanceExecutor` w `AppDelegate` (jak inne closures/modele).
- [ ] **Krok 4:** `swift build` + `swift test` zielone; ręczna weryfikacja zakładki.

---

## FAZA 2 — Wzmocnienie bezpieczeństwa: `SafetyGuard`

Port `MacCleanKit/SafetyGuard.swift` — kanonikalizacja firmlinków, blokada SIP, anty-TOCTOU, limit plików. Wzmacnia istniejące `SafeDeleter` + `AppProtectionGuard`.

### Task 2.1: Port `SafetyGuard` do Core

**Pliki:**
- Utwórz: `Sources/AutoCleanMacCore/SafetyGuard.swift`
- Test: `Tests/AutoCleanMacCoreTests/SafetyGuardTests.swift`

- [ ] **Krok 1 (RED):** Testy adwersaryjne (port z MacSai `SafetyGuardTests`): symlink redirect, `/private/var`↔`/var`, `/System/*` → `.sipProtected`, NULL byte → `.invalidPath`, pusty path, limit plików.
- [ ] **Krok 2 (GREEN):** Przenieś `SafetyGuard`:
  - Usuń `L10n.tr` z `errorDescription`.
  - Zastąp `MCConstants.protectedPaths` / `protectedApps` / `maxFilesPerOperation` / ścieżki `userCaches` itd. — albo nową stałą `SafetyConstants` w Core, albo zmapuj na istniejące w `AutoCleanMacCore` (sprawdź `AppProtectionGuard`, `LeftoverPathProvider`, `Config`).
  - Zachowaj `canonicalizeMacOSFirmlinks`, `validatePath`, `validateDeletion`, `isSafeForOrphanDeletion`.
- [ ] **Krok 3:** Testy zielone.

### Task 2.2: Wpięcie `SafetyGuard` w `SafeDeleter`

**Pliki:**
- Zmień: `Sources/AutoCleanMacCore/SafeDeleter.swift`
- Test: `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`

- [ ] **Krok 1 (RED):** Test: `SafeDeleter` odmawia usunięcia ścieżki odrzuconej przez `SafetyGuard` (np. symlink do `/System`).
- [ ] **Krok 2 (GREEN):** Wywołaj `validatePath` przed `removeItem`/trash. Uwaga: nie zepsuć istniejących 99 testów — uruchom pełny suite.
- [ ] **Krok 3:** `swift test` cały suite zielony.

---

## FAZA 3 — Menu-bar: live statystyki systemu

Twoja apka jest menu-bar → naturalne miejsce na live CPU/RAM/dysk/bateria. Port czystych parserów z `MacCleanKit/SystemStats/*` + kolektora z `MacCleanMenu/SystemStats/SystemStatsCollector.swift`.

### Task 3.1: Czyste parsery statystyk

**Pliki:**
- Utwórz: `Sources/AutoCleanMacCore/SystemStats/CPUStats.swift`, `MemoryStats.swift`, `DiskStats.swift`
- Test: `Tests/AutoCleanMacCoreTests/SystemStatsTests.swift`

- [ ] **Krok 1 (RED):** Testy na fixture'ach (port `SystemStatsTests`): `CPUTicks.summed`, `CPUUsage(previous:current:)`, `VMStatistics`/`MemoryUsage`, `DiskUsage.fromStatfs`.
- [ ] **Krok 2 (GREEN):** Przenieś `CPUStats`/`MemoryStats`/`DiskStats` (czysty Foundation, bez zmian poza pakietem).
- [ ] **Krok 3:** Testy zielone.

### Task 3.2: `SystemStatsCollector` (Mach/IOKit)

**Pliki:**
- Utwórz: `Sources/AutoCleanMacCore/SystemStats/SystemStatsCollector.swift`
- Test: smoke test (kolektor zwraca sensowne wartości na realnym systemie — oznacz jako integration).

- [ ] **Krok 1:** Przenieś aktor `SystemStatsCollector` (host_processor_info / vm_statistics64 / statfs / IOKit power). Sprawdź dostępność API na macOS 13.
- [ ] **Krok 2:** Zweryfikuj brak `import MacCleanKit` → użyj lokalnych typów z Task 3.1.

### Task 3.3: UI w menu-bar

**Pliki:**
- Zmień: `Sources/AutoCleanMac/MenuBarController.swift`

- [ ] **Krok 1:** Dodaj sekcję live stats (timer co N s, odczyt z `SystemStatsCollector`). Lekko, żeby nie podnosić RAM/CPU (zgodnie z wcześniejszą optymalizacją menu-bar, memory S992).
- [ ] **Krok 2:** Ręczna weryfikacja: wartości aktualizują się, brak wzrostu zużycia zasobów.

---

## FAZA 4 — Precyzyjniejszy Uninstaller: `AppMatching`

Port `MacCleanKit/AppMatching.swift` — 10-poziomowy silnik dopasowania plików aplikacji. Rozszerza istniejący `LeftoverPathProvider`/`AppPurger`. Zgodne z `TODO.md` (rozszerzenie LeftoverPathProvider).

### Task 4.1: Port `AppMatching`

**Pliki:**
- Utwórz: `Sources/AutoCleanMacCore/AppMatching.swift`
- Test: `Tests/AutoCleanMacCoreTests/AppMatchingTests.swift`

- [ ] **Krok 1 (RED):** Testy (port): generowanie wzorców per poziom, domyślny `maxLevel = .versionStripped`, `filenameMatches`.
- [ ] **Krok 2 (GREEN):** Przenieś enum; zmapuj `AppInfo` MacSai na istniejący model aplikacji w `AutoCleanMacCore` (sprawdź `AppScanner`/`InstalledAppRegistry` — jaki typ reprezentuje app) lub dodaj minimalny adapter.
- [ ] **Krok 3:** Testy zielone.

### Task 4.2: Wpięcie w `LeftoverPathProvider`/`AppPurger`

**Pliki:**
- Zmień: `Sources/AutoCleanMacCore/LeftoverPathProvider.swift`
- Test: `Tests/AutoCleanMacCoreTests/LeftoverPathProviderTests.swift`

- [ ] **Krok 1 (RED):** Test: dla przykładowej aplikacji `LeftoverPathProvider` znajduje pliki pasujące przez `AppMatching` w `librarySubdirectories`.
- [ ] **Krok 2 (GREEN):** Użyj `AppMatching.generatePatterns` + skan `librarySubdirectories`; połącz z istniejącą logiką. Zachowaj guard `AppProtectionGuard`.
- [ ] **Krok 3:** Cały suite zielony (uwaga na regresje w Uninstallerze).

---

## FAZA 5 — Opcjonalne moduły (niższy priorytet, większy nakład)

Realizować tylko po akceptacji Fazy 1–4. Każdy jako osobny, niezależny task TDD.

### Task 5.1: Duplicate finder
- Port `MacCleanKit/DuplicateDetection.swift` (czysty pipeline) + `FileItem` (minimalny model) → nowy moduł + zakładka. Hashowanie (CryptoKit SHA-256) w warstwie Core jako osobny komponent.

### Task 5.2: Universal Binary thinning
- Port `MacCleanKit/UniversalBinariesPolicy.swift` + `Cleaner/MachOWalker.swift` + `ThinBinaryOperation.swift` → nowy `CleanupTask` (`lipo`). Wymaga ostrożności (modyfikuje binaria).

### Task 5.3: Malware scanner (sygnatury)
- Port `MacCleanKit/MalwareSignatures.swift` (czyste) + adaptacja `MalwareModule` skanera → nowa zakładka „Protection".

### Task 5.4: Rozbudowa System Junk
- Port kategorii z `MacCleanKit/Categories/*` (DeveloperCache, BrokenPreferences, BrokenLoginItems, UniversalBinaries) jako nowe `CleanupTask`. Pokrywa się z `TODO.md` (Xcode/JetBrains/broken prefs).

### Task 5.5: SpaceLens (treemap)
- Port `MacCleanKit/SquarifiedTreemap.swift` → wizualizacja dysku. Najcięższe UI; rozważyć tylko jeśli apka ma rozrosnąć się do pełnego okna.

---

## Kolejność realizacji (rekomendowana)

1. **Task 0** (licencja) — blokujący.
2. **Faza 1** (Maintenance) — największy zysk/nakład.
3. **Faza 2** (SafetyGuard) — bezpieczeństwo.
4. **Faza 3** (menu-bar stats) — najlepiej pasuje do architektury.
5. **Faza 4** (AppMatching) — lepszy Uninstaller.
6. **Faza 5** — opcjonalnie, po decyzji.

## Definicja ukończenia (każda faza)

- [ ] `swift build` bez błędów (Swift 5.9).
- [ ] `swift test` — wszystkie testy zielone (baseline 99 + nowe).
- [ ] Nowe/zmienione pliki dopisane do `THIRD_PARTY_NOTICES.md` z nagłówkiem atrybucji.
- [ ] Brak `import MacCleanKit` w `AutoCleanMacCore`/`AutoCleanMac` (port = adaptacja, nie zależność).
- [ ] Ręczna weryfikacja UI (dla faz z UI).

## Ryzyka / uwagi

- **Swift 6 → 5.9:** `switch` jako wyrażenie bez `return`, `Sendable` strictness, aktorzy — wymagają drobnych poprawek przy porcie.
- **macOS 14 → 13:** zweryfikować każde API (szczególnie IOKit/Mach w Fazie 3 i ewentualne nowe API SwiftUI).
- **Stałe MCConstants:** wiele plików MacSai zależy od `MCConstants` (protected paths, ścieżki Library). Przed Fazą 2/4 zmapować je na istniejące stałe w `AutoCleanMacCore` lub utworzyć `SafetyConstants`.
- **Regresje:** Fazy 2 i 4 dotykają krytycznych ścieżek usuwania — uruchamiać pełny suite po każdym kroku.

# Safety & Accuracy Pass — Plan Implementacji

> **Dla wykonawcy (agenta lub człowieka):** WYMAGANY SUB-SKILL: superpowers:subagent-driven-development (rekomendowany) albo superpowers:executing-plans — implementacja krok po kroku. Kroki używają składni `- [ ]` do oznaczania postępu.

**Cel:** Naprawić dwa problemy w `SafeDeleter` podważające zaufanie do aplikacji: (1) raportowane "zwolnione bajty" dla katalogów są błędne (bo zwraca rozmiar inode'u zamiast sumy plików w środku), (2) pliki są trwale usuwane przez `removeItem`, bez możliwości przywrócenia. Dodajemy rekurencyjne sumowanie rozmiaru oraz nowy tryb `.trash` (przenoszenie do Kosza), który staje się domyślny.

**Architektura:** Zmiany są lokalne w `AutoCleanMacCore.SafeDeleter` (nowa logika liczenia rozmiaru, nowy case enum `Mode`), w `AutoCleanMacCore.Config` (nowe pole `deleteMode`), i w `AutoCleanMac.AppDelegate` (wybór trybu wg configu). Istniejąca semantyka `.live` i `.dryRun` nie zmienia się. Env var `AUTOCLEANMAC_DRY_RUN` dalej ma najwyższy priorytet.

**Tech Stack:** Swift 5.9, Swift Package Manager, XCTest, Foundation (`FileManager.trashItem`, `FileManager.enumerator`).

---

## Struktura plików

- **Modyfikacja:** `Sources/AutoCleanMacCore/SafeDeleter.swift` — dodanie `recursiveSize(at:)`, nowy case `.trash` w `Mode`, rozgałęzienie w `delete(_:withinRoot:)`.
- **Modyfikacja:** `Sources/AutoCleanMacCore/Config.swift` — enum `DeleteMode`, pole `Config.deleteMode`, parsowanie `delete_mode` z JSON.
- **Modyfikacja:** `Sources/AutoCleanMac/AppDelegate.swift` — wybór trybu na podstawie `config.deleteMode` (z zachowaniem override env var), aktualizacja default JSON generowanego przy pierwszym otwarciu konfiguracji.
- **Modyfikacja:** `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift` — testy rekurencyjnego rozmiaru i trybu `.trash`.
- **Modyfikacja:** `Tests/AutoCleanMacCoreTests/ConfigTests.swift` — testy parsowania `delete_mode`.

---

## Task 1: Rekurencyjne sumowanie rozmiaru katalogów w `SafeDeleter`

**Dlaczego:** Obecnie `FileManager.attributesOfItem(atPath:)[.size]` dla katalogu zwraca ~96 B (rozmiar inode'u), a nie sumę plików w środku. W efekcie podsumowanie "Zwolniono: X" w UI jest drastycznie zaniżone dla zadań operujących na katalogach (np. `TrashTask`, `UserCachesTask`).

**Files:**
- Modify: `Sources/AutoCleanMacCore/SafeDeleter.swift`
- Test: `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`

---

- [ ] **Step 1: Napisz failing test dla rekurencyjnego rozmiaru katalogu**

Dodaj na końcu `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift` (przed zamykającą klamrą klasy):

```swift
func test_delete_directory_returns_recursive_size() throws {
    let root = tempDir.appendingPathComponent("root")
    let dir = root.appendingPathComponent("cache")
    try Fixtures.makeFile(at: dir.appendingPathComponent("a.bin"), size: 1_000)
    try Fixtures.makeFile(at: dir.appendingPathComponent("sub/b.bin"), size: 2_500)
    try Fixtures.makeFile(at: dir.appendingPathComponent("sub/deeper/c.bin"), size: 500)
    let deleter = SafeDeleter(mode: .live, logger: logger)
    let freed = try deleter.delete(dir, withinRoot: root)
    XCTAssertEqual(freed, 4_000)
    XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
}

func test_dry_run_directory_returns_recursive_size_without_deleting() throws {
    let root = tempDir.appendingPathComponent("root")
    let dir = root.appendingPathComponent("cache")
    try Fixtures.makeFile(at: dir.appendingPathComponent("x.bin"), size: 300)
    try Fixtures.makeFile(at: dir.appendingPathComponent("y.bin"), size: 700)
    let deleter = SafeDeleter(mode: .dryRun, logger: logger)
    let freed = try deleter.delete(dir, withinRoot: root)
    XCTAssertEqual(freed, 1_000)
    XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
}
```

- [ ] **Step 2: Uruchom testy i potwierdź, że nowe failują**

Run: `swift test --filter SafeDeleterTests/test_delete_directory_returns_recursive_size`

Expected: FAIL. Oczekiwane `4000`, otrzymane prawdopodobnie wartość bliska `0` lub `96` (rozmiar inode'u).

Run: `swift test --filter SafeDeleterTests/test_dry_run_directory_returns_recursive_size_without_deleting`

Expected: FAIL z tego samego powodu.

- [ ] **Step 3: Dodaj `recursiveSize(at:)` i użyj jej w `delete`**

W `Sources/AutoCleanMacCore/SafeDeleter.swift` zastąp blok liczenia rozmiaru (aktualnie linie 40-43, `guard let attrs = …` + `let size = …`) następującym kodem:

```swift
        let size: Int64
        do {
            size = try Self.recursiveSize(at: path)
        } catch {
            throw DeletionError.notFound(path: path.path)
        }
```

Następnie dodaj prywatną metodę statyczną tuż przed zamykającą klamrą klasy `SafeDeleter`:

```swift
    /// Zwraca sumę rozmiarów pliku lub całego drzewa katalogów (bez podążania za symlinkami).
    /// Symlinki są liczone po rozmiarze samego dowiązania (lstat).
    private static func recursiveSize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        if type == .typeDirectory {
            var total: Int64 = 0
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles /* brak skipsSubdirectoryDescendants: chcemy zejść w głąb */],
                errorHandler: { _, _ in true } // ignoruj pojedyncze błędy dostępu
            ) else {
                return (attrs[.size] as? Int64) ?? 0
            }
            for case let child as URL in enumerator {
                let values = try? child.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                if values?.isSymbolicLink == true {
                    let linkAttrs = try? fm.attributesOfItem(atPath: child.path)
                    total += (linkAttrs?[.size] as? Int64) ?? 0
                    continue
                }
                total += Int64(values?.fileSize ?? 0)
            }
            return total
        } else {
            return (attrs[.size] as? Int64) ?? 0
        }
    }
```

Uwaga: `FileManager.enumerator(at:…)` domyślnie nie podąża za symlinkami na katalogi, co jest pożądane (nie chcemy liczyć rozmiaru rzeczy spoza drzewa).

- [ ] **Step 4: Uruchom wszystkie testy i potwierdź, że przechodzą**

Run: `swift test`

Expected: wszystkie testy PASS, w tym oba nowe. Istniejące testy dla pojedynczych plików (`test_delete_file_within_root_removes_and_returns_size`, `test_dry_run_does_not_delete_but_returns_size`) powinny dalej przechodzić, bo dla zwykłego pliku `recursiveSize` sprowadza się do `attrs[.size]`.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/SafeDeleter.swift Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift
git commit -m "fix(core): report recursive directory size in SafeDeleter

Directories previously reported their inode size (~96 B) instead of the
sum of contained files, making the 'freed bytes' summary misleading for
tasks operating on cache/temp directories. Now recurses with
FileManager.enumerator, skipping symlinks to avoid escaping the tree."
```

---

## Task 2: Nowy tryb `.trash` w `SafeDeleter`

**Dlaczego:** Aktualny `.live` wywołuje `removeItem`, czyli trwale kasuje. Użytkownik nie ma jak odzyskać pliku jeśli task będzie miał bug. `FileManager.trashItem(at:resultingItemURL:)` przenosi do systemowego Kosza — odwracalnie.

**Files:**
- Modify: `Sources/AutoCleanMacCore/SafeDeleter.swift`
- Test: `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`

---

- [ ] **Step 1: Napisz failing test dla trybu `.trash`**

Dodaj do `Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift`:

```swift
func test_trash_mode_moves_file_and_returns_size() throws {
    let root = tempDir.appendingPathComponent("root")
    let file = root.appendingPathComponent("doomed.txt")
    try Fixtures.makeFile(at: file, size: 128)
    let deleter = SafeDeleter(mode: .trash, logger: logger)
    let freed = try deleter.delete(file, withinRoot: root)
    XCTAssertEqual(freed, 128)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
}

func test_trash_mode_still_rejects_path_outside_root() throws {
    let root = tempDir.appendingPathComponent("root")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let outside = tempDir.appendingPathComponent("safe.txt")
    try Fixtures.makeFile(at: outside)
    let deleter = SafeDeleter(mode: .trash, logger: logger)
    XCTAssertThrowsError(try deleter.delete(outside, withinRoot: root)) { error in
        guard case SafeDeleter.DeletionError.outsideAllowedRoot = error else {
            return XCTFail("Wrong error: \(error)")
        }
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
}
```

- [ ] **Step 2: Uruchom testy i potwierdź, że nowe failują**

Run: `swift test --filter SafeDeleterTests/test_trash_mode_moves_file_and_returns_size`

Expected: FAIL — błąd kompilacji "type 'SafeDeleter.Mode' has no member 'trash'".

- [ ] **Step 3: Dodaj `.trash` do enum i obsłuż w `delete`**

W `Sources/AutoCleanMacCore/SafeDeleter.swift` zmień definicję enum:

```swift
    public enum Mode { case live, dryRun, trash }
```

Następnie zastąp końcówkę metody `delete(_:withinRoot:)` (od linii z `let event = mode == .dryRun ? …` do `return size`) następującym blokiem:

```swift
        let event: String
        switch mode {
        case .dryRun: event = "dryrun"
        case .live:   event = "delete"
        case .trash:  event = "trash"
        }
        logger.log(event: event, fields: ["path": path.path, "size": "\(size)"])

        switch mode {
        case .dryRun:
            break
        case .live:
            try FileManager.default.removeItem(at: path)
        case .trash:
            var resulting: NSURL? = nil
            try FileManager.default.trashItem(at: path, resultingItemURL: &resulting)
            if let dst = resulting as URL? {
                logger.log(event: "trash_dst", fields: ["path": path.path, "dst": dst.path])
            }
        }
        return size
```

- [ ] **Step 4: Uruchom wszystkie testy**

Run: `swift test`

Expected: PASS. Wszystkie poprzednie testy dalej zielone, dwa nowe testy `.trash` zielone. Jeśli któryś test dla `.live` zawiedzie — sprawdź, czy nie dodałeś przypadkowo `@unknown default` w innym miejscu w kodzie.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/SafeDeleter.swift Tests/AutoCleanMacCoreTests/SafeDeleterTests.swift
git commit -m "feat(core): add .trash mode to SafeDeleter

Moves items to the user's Trash via FileManager.trashItem instead of
permanently deleting. Same root-containment checks apply. Logger emits
'trash' events and 'trash_dst' entries recording the resulting URL."
```

---

## Task 3: Pole `deleteMode` w `Config`

**Dlaczego:** Tryb usuwania powinien być konfigurowalny per-instalacja, nie zaszyty w kodzie. Domyślny `.trash` — bezpieczniejszy.

**Files:**
- Modify: `Sources/AutoCleanMacCore/Config.swift`
- Test: `Tests/AutoCleanMacCoreTests/ConfigTests.swift`

---

- [ ] **Step 1: Napisz failing testy dla parsowania `delete_mode`**

Dodaj do `Tests/AutoCleanMacCoreTests/ConfigTests.swift`:

```swift
func test_default_delete_mode_is_trash() {
    let missing = tempDir.appendingPathComponent("nope.json")
    let config = Config.loadOrDefault(from: missing, warn: { _ in })
    XCTAssertEqual(config.deleteMode, .trash)
}

func test_loads_delete_mode_live() throws {
    let file = tempDir.appendingPathComponent("c.json")
    try #"{ "delete_mode": "live" }"#.write(to: file, atomically: true, encoding: .utf8)
    let config = Config.loadOrDefault(from: file, warn: { _ in })
    XCTAssertEqual(config.deleteMode, .live)
}

func test_loads_delete_mode_dry_run() throws {
    let file = tempDir.appendingPathComponent("c.json")
    try #"{ "delete_mode": "dry_run" }"#.write(to: file, atomically: true, encoding: .utf8)
    let config = Config.loadOrDefault(from: file, warn: { _ in })
    XCTAssertEqual(config.deleteMode, .dryRun)
}

func test_unknown_delete_mode_warns_and_keeps_default() throws {
    let file = tempDir.appendingPathComponent("c.json")
    try #"{ "delete_mode": "nuke_everything" }"#.write(to: file, atomically: true, encoding: .utf8)
    var warnings: [String] = []
    let config = Config.loadOrDefault(from: file, warn: { warnings.append($0) })
    XCTAssertEqual(config.deleteMode, .trash)
    XCTAssertTrue(warnings.contains(where: { $0.contains("delete_mode") }))
}
```

- [ ] **Step 2: Uruchom testy i potwierdź, że failują**

Run: `swift test --filter ConfigTests/test_default_delete_mode_is_trash`

Expected: FAIL — błąd kompilacji "value of type 'Config' has no member 'deleteMode'".

- [ ] **Step 3: Dodaj `DeleteMode` i pole w `Config`**

W `Sources/AutoCleanMacCore/Config.swift`:

(a) Dodaj enum na górze pliku, bezpośrednio pod `import Foundation`:

```swift
public enum DeleteMode: String, Equatable {
    case trash
    case live
    case dryRun

    public static func parse(_ raw: String) -> DeleteMode? {
        switch raw {
        case "trash":    return .trash
        case "live":     return .live
        case "dry_run":  return .dryRun
        default:         return nil
        }
    }
}
```

(b) Rozszerz `struct Config`: dodaj pole `deleteMode` oraz zaktualizuj `default`:

```swift
    public var retentionDays: Int
    public var window: Window
    public var tasks: Tasks
    public var deleteMode: DeleteMode

    public static let `default` = Config(
        retentionDays: 7, window: .default, tasks: .default, deleteMode: .trash
    )
```

(c) W `loadOrDefault(from:warn:)` dodaj parsowanie `delete_mode` tuż przed `return config`:

```swift
        if let raw = json["delete_mode"] as? String {
            if let mode = DeleteMode.parse(raw) {
                config.deleteMode = mode
            } else {
                warn("Nieznana wartość delete_mode: \"\(raw)\" — używam wartości domyślnej (\(config.deleteMode.rawValue))")
            }
        }
```

- [ ] **Step 4: Uruchom wszystkie testy**

Run: `swift test`

Expected: PASS. Nowe cztery testy `Config*delete_mode*` zielone, istniejące testy `ConfigTests` dalej zielone (bo nie referują `deleteMode`).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMacCore/Config.swift Tests/AutoCleanMacCoreTests/ConfigTests.swift
git commit -m "feat(core): add delete_mode option to Config (default: trash)

Config now carries a DeleteMode {trash, live, dryRun}, parsed from
'delete_mode' in config.json. Default is .trash so users get recoverable
deletes out of the box. Unknown values fall back to default and emit a
warning."
```

---

## Task 4: `AppDelegate` używa `config.deleteMode`

**Dlaczego:** Core wie o nowym trybie, ale aplikacja go nie wywołuje. Wciąż twardokodowane `.live`/`.dryRun` w `runCleanup`.

**Files:**
- Modify: `Sources/AutoCleanMac/AppDelegate.swift`

---

- [ ] **Step 1: Zmień wybór trybu w `runCleanup(source:)`**

W `Sources/AutoCleanMac/AppDelegate.swift`, w metodzie `runCleanup(source:)`, znajdź linię:

```swift
        let mode: SafeDeleter.Mode = ProcessInfo.processInfo.environment["AUTOCLEANMAC_DRY_RUN"] != nil ? .dryRun : .live
```

Zastąp ją:

```swift
        let mode: SafeDeleter.Mode = {
            if ProcessInfo.processInfo.environment["AUTOCLEANMAC_DRY_RUN"] != nil { return .dryRun }
            switch config.deleteMode {
            case .trash:  return .trash
            case .live:   return .live
            case .dryRun: return .dryRun
            }
        }()
        logger.log(event: "mode", fields: ["mode": "\(mode)"])
```

- [ ] **Step 2: Zaktualizuj default JSON w `openInDefaultEditor`**

W tej samej metodzie `openInDefaultEditor(_:)`, znajdź blok `let defaultJson = """ … """` (aktualnie linie 123-138) i zastąp go następującym (dodaje `"delete_mode": "trash"` + komentarz przez pole meta):

```swift
            let defaultJson = """
            {
              "retention_days": 7,
              "delete_mode": "trash",
              "window": { "fade_in_ms": 800, "hold_after_ms": 3000, "fade_out_ms": 800 },
              "tasks": {
                "user_caches": true,
                "system_temp": true,
                "trash": true,
                "ds_store": true,
                "user_logs": true,
                "browser_caches": true,
                "dev_caches": true,
                "downloads": false
              }
            }
            """
```

- [ ] **Step 3: Zbuduj aplikację i potwierdź kompilację**

Run: `swift build`

Expected: `Build complete!`, bez ostrzeżeń dot. wyczerpania case'ów enumu.

- [ ] **Step 4: Uruchom smoke test z dry-run override**

Run (sanity, jeśli masz skonfigurowaną binarkę lokalnie — możesz pominąć jeśli nie):

```bash
AUTOCLEANMAC_DRY_RUN=1 swift run AutoCleanMac 2>&1 | head -5 || true
```

Expected: aplikacja startuje, ustawia tryb `dryRun` (widoczne w logu `event=mode mode=dryRun`).

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoCleanMac/AppDelegate.swift
git commit -m "feat(app): honor config.delete_mode when selecting SafeDeleter mode

AUTOCLEANMAC_DRY_RUN env var still overrides to .dryRun. Otherwise the
runtime mode is taken from config.delete_mode (default .trash). The
chosen mode is logged as a 'mode' event for auditability. Default JSON
template generated on first-run config now includes delete_mode."
```

---

## Task 5: Dokumentacja zmiany

**Dlaczego:** Istniejący użytkownicy z plikiem `~/.config/autoclean-mac/config.json` nie dostaną `delete_mode` automatycznie (ich config jest starszy). Potrzebują wiedzieć, że domyślnie dalej działa jak wcześniej — z jednym wyjątkiem: gdy config nie istnieje, nowa instalacja używa Kosza zamiast `rm`.

**Files:**
- Modify: `docs/plan_implementacji.md` — nic do zmiany, ten plik to plan.
- Create or modify: `docs/CHANGELOG.md` albo `docs/safety-modes.md` (poniżej użyjemy drugiego, bo CHANGELOG nie istnieje i nie chcemy wprowadzać nowej konwencji dla pojedynczej zmiany).

---

- [ ] **Step 1: Utwórz `docs/safety-modes.md`**

Zapisz nowy plik `docs/safety-modes.md` z zawartością:

```markdown
# Tryby usuwania (`delete_mode`)

`AutoCleanMac` obsługuje trzy tryby usuwania. Wybierasz je w `~/.config/autoclean-mac/config.json` pod kluczem `delete_mode`.

| Wartość   | Zachowanie                                                                     | Odwracalne? |
|-----------|--------------------------------------------------------------------------------|-------------|
| `trash`   | **Domyślny.** Przenosi pliki do systemowego Kosza (`FileManager.trashItem`).   | Tak         |
| `live`    | Trwale usuwa plik (`FileManager.removeItem`). Zachowanie sprzed v0.x.          | Nie         |
| `dry_run` | Niczego nie kasuje, tylko loguje co *zostałoby* usunięte i zlicza rozmiar.     | —           |

## Override środowiskowy

Zmienna `AUTOCLEANMAC_DRY_RUN` (jakakolwiek niepusta wartość) wymusza `dry_run` niezależnie od configu. Przydatne do testów bez edycji pliku.

```bash
AUTOCLEANMAC_DRY_RUN=1 ./AutoCleanMac.app/Contents/MacOS/AutoCleanMac
```

## Migracja z wcześniejszych wersji

Wcześniejsze wersje używały `.live` na sztywno. Istniejące configi nie mają klucza `delete_mode` i nowa wersja nadaje im wartość domyślną `trash`. Jeśli chcesz zachować stare zachowanie, dopisz:

```json
{ "delete_mode": "live" }
```

## Co oznacza "zwolniono X GB" dla trybu `trash`?

Rozmiar jest liczony **przed** przeniesieniem, rekurencyjnie dla katalogów. W Koszu pliki dalej zajmują miejsce dopóki nie opróżnisz Kosza — wartość z podsumowania odzwierciedla potencjalną ilość zwolnionej przestrzeni, nie stan po operacji.
```

- [ ] **Step 2: Commit**

```bash
git add docs/safety-modes.md
git commit -m "docs: document delete_mode and AUTOCLEANMAC_DRY_RUN override

Explains the three modes (trash/live/dry_run), the env override,
migration from older configs (which default to trash on the new
version), and the meaning of the 'freed bytes' figure in trash mode."
```

---

## Poza zakresem (osobne plany w przyszłości)

- **Okno Preferencji w SwiftUI** (#1 z przeglądu) — znaczący nakład, wymaga osobnego planu: `Settings` scene, `@AppStorage`/binding do `Config`, zapis do JSON przy zamknięciu okna, podpięcie pod `MenuBarController.onOpenConfig`. Orientacyjnie 6-8 tasków.
- **Deny-list ścieżek** (#9) — defence in depth: `SafeDeleter` odrzuca ścieżki równe `~`, `~/Documents`, `~/Desktop`, `/`, `$HOME/Library/Mail`. Osobny plan, ~3 taski.
- **Ikona SF Symbols** (#2) — prosta zmiana ale warta krótkiego własnego commita z review UI na jasnym/ciemnym motywie.

---

## Self-review

- [x] **Spec coverage:** Rekomendacje #7 (rekurencyjny rozmiar) i #8 (Kosz) w pełni pokryte przez Task 1 i Task 2. Konfigurowalność trybu + domyślny `trash` pokryta przez Task 3. Spięcie z UI/launch — Task 4. Dokumentacja — Task 5.
- [x] **Placeholder scan:** Brak "TBD", "handle edge cases", "similar to Task N". Każdy krok ma konkretny kod lub komendę.
- [x] **Type consistency:** `DeleteMode` (enum w Config) → `SafeDeleter.Mode` (enum w SafeDeleter) — odwzorowanie 1-1 w `AppDelegate` (Task 4 Step 1 pokazuje wszystkie trzy case'y). `recursiveSize(at:)` zdefiniowana w Task 1 Step 3 używana niejawnie przez `delete` w Task 2 Step 3. Klucz JSON `delete_mode` konsekwentnie snake_case (Task 3 + Task 4 Step 2 + Task 5 Step 1). Nazwy case'ów enum JSON: `trash`/`live`/`dry_run` wszędzie tak samo.

---

## Execution Handoff

Plan ukończony, zapisany jako `docs/plan_implementacji.md`. Dwie opcje wykonania:

1. **Subagent-Driven (rekomendowane)** — dispatchuję świeżego subagenta per task, review między taskami, szybka iteracja.
2. **Inline Execution** — wykonanie w tej sesji przez `superpowers:executing-plans`, batch z checkpointami do review.

Które podejście?

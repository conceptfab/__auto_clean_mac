# Jeden Panel Preferencji + Ikona — Plan

**Cel:** Jedno okno Preferencji pokrywa wszystko co wcześniej było rozrzucone po menu baru (Otwórz konfigurację, Otwórz folder logów, Pokaż ostatni log). Menu bara zredukowane do trzech pozycji. Ikona aplikacji z `icon.png`. Tabela przeglądarek pokazuje tylko **zainstalowane**.

**Taski:**

1. **Ikona aplikacji** — konwersja `icon.png` → `icon.icns`, włączenie do bundla.
2. **SettingsView z tabami** — Ogólne / Czyszczenie / Przeglądarki / Logi. Wszystkie sekcje edytowalne z GUI; JSON nietykany.
3. **Filtr zainstalowanych przeglądarek** — tylko te z istniejącymi `profileRoots`.
4. **Uproszczone MenuBarController** — tylko: Uruchom teraz / Preferencje… / Zakończ.
5. **ConfigWriter rozszerzony** — round-trip wszystkich pól (już jest, ale dodać test że retention/delete_mode/tasks też przechodzą przez Save).
6. **Smoke test + merge + install**.

---

## Task 1: Ikona aplikacji

- [ ] Konwersja `icon.png` → `icon.icns` w `resources/`:

```bash
cd /Users/micz/__DEV__/__auto_clean_mac/.claude/worktrees/unified-prefs
mkdir -p resources/AutoCleanMac.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size icon.png --out "resources/AutoCleanMac.iconset/icon_${size}x${size}.png"
  sips -z $((size*2)) $((size*2)) icon.png --out "resources/AutoCleanMac.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns -o resources/AutoCleanMac.icns resources/AutoCleanMac.iconset
rm -rf resources/AutoCleanMac.iconset
```

- [ ] W `scripts/build-app-bundle.sh`, po kopiowaniu binarki dodaj:

```bash
cp "$REPO_ROOT/resources/AutoCleanMac.icns" "$RESOURCES_DIR/AutoCleanMac.icns"
```

- [ ] W tym samym skrypcie, w `Info.plist` heredoc dodaj klucz:

```
    <key>CFBundleIconFile</key>               <string>AutoCleanMac</string>
```

- [ ] Commit: `feat(app): add app icon from icon.png`.

## Task 2: SettingsView z pełnymi tabami

Nowe taby w `SettingsView`:

- **Ogólne**: `retention_days` (Stepper 1-30), `delete_mode` (Picker trash/live/dry_run)
- **Czyszczenie**: Toggle per: user_caches, system_temp, trash, ds_store, user_logs, dev_caches, downloads
- **Przeglądarki**: dotychczasowy grid, ale tylko zainstalowane
- **Logi**: 2 przyciski: "Otwórz folder logów", "Pokaż ostatni log"

`SettingsModel` trzyma cały `Config` (nie tylko `browsers`), `apply()` wysyła zmodyfikowaną kopię przez `onApply`.

- [ ] Rozszerz `SettingsModel` do pełnego configu.
- [ ] Dodaj `GeneralTab`, `TasksTab`, `LogsTab` obok `BrowsersTab`.
- [ ] `LogsTab` potrzebuje callbacków `onOpenLogsFolder` / `onShowLastLog` wstrzykniętych z AppDelegate.
- [ ] Commit: `feat(app): unified Preferences with general/cleanup/browsers/logs tabs`.

## Task 3: Filtr zainstalowanych przeglądarek

`BrowserIdentity.isInstalled(homeDirectory:) -> Bool` — true jeśli jakikolwiek `profileRoot` istnieje.

- [ ] Dodać metodę + test.
- [ ] W `BrowsersTab` filtrować `BrowserIdentity.allCases.filter { $0.isInstalled(homeDirectory: home) }`.
- [ ] Jeśli lista pusta — pokaż "Nie wykryto obsługiwanych przeglądarek."
- [ ] Commit: `feat(core): hide uninstalled browsers from Preferences`.

## Task 4: Uproszczone MenuBarController

Menu tylko: Uruchom teraz / separator / Preferencje… / separator / Zakończ.

- [ ] Usuń `onShowLastLog`, `onOpenConfig`, `onOpenLogsFolder` z `MenuBarController`.
- [ ] W `AppDelegate.applicationDidFinishLaunching` zostaw tylko `onRunNow` / `onOpenSettings` / `onQuit`.
- [ ] Osierocone metody (`openMostRecentLog`, `openInDefaultEditor`) przenieś do callbacków SettingsModel.
- [ ] Commit: `refactor(app): collapse menu bar to run/prefs/quit`.

## Task 5: ConfigWriter test dla pełnego round-trip

- [ ] Dodaj do `ConfigWriterTests` test: ustaw wszystkie pola (retention, delete_mode, window, tasks, browsers), zapisz, wczytaj, porównaj `==` (`Config: Equatable` już jest).
- [ ] Commit: `test(core): full-config round-trip through ConfigWriter`.

## Task 6: Build + install + smoke

- [ ] `swift test` — wszystko zielone.
- [ ] `./scripts/install.sh` — rebuild + reinstall.
- [ ] Manual: ikona w menu barze wygląda jak `icon.png`. Ikona Docka (jeśli widoczna) = icon.png. Preferencje → Ogólne/Czyszczenie/Przeglądarki/Logi działają i zapisują. Menu bara ma tylko 3 pozycje.
- [ ] Commit: `chore: smoke-test unified Preferences` (--allow-empty).

---

## Poza zakresem

- Tłumaczenia systemowe (Settings scene vs NSWindow) — zostaje NSHostingController.
- Live progress bar — osobny plan.
- Ikona SF Symbols dla menu bara (obok ikony Docka) — osobny plan.

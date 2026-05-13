# TODO — przeniesienie funkcji z `__mole/` do `AutoCleanMac`

Raport sporządzony 2026-05-13 na podstawie analizy `__mole/` (Bash 52 plików + Go cmd/analyze, cmd/status) vs `Sources/AutoCleanMac*` (Swift, ~2 651 LOC).

## Stan obecny

- Swift app pokrywa ~20% funkcjonalności `__mole`.
- `__mole` to dojrzała hybryda: 52 skrypty Bash (lib/ + bin/) jako jądro, 2 narzędzia Go (`cmd/analyze` ~6.7k LOC, `cmd/status` ~6.6k LOC). Brak `go.mod`, brak README — Go niezmodularyzowany.

---

## Najwyższy priorytet — uzupełnienia `AppPurger` (Uninstaller)

`AppPurger.swift` + `LeftoverPathProvider.swift` pokrywają ~30% tego, co `__mole/lib/uninstall/batch.sh`.

| Status | Funkcja w `__mole` | Co robi | Gdzie wstawić w Swift |
|---|---|---|---|
| ❌ | `stop_launch_services` (`batch.sh:102`) | `launchctl unload` + skanowanie ProgramArguments | rozszerzenie `LaunchAgentClient` |
| ✅ | `unregister_app_bundle` + `refresh_launch_services_after_uninstall` (`batch.sh:165,183`) | `lsregister -u` + `-gc -r` (czyści Spotlight/Dock) | `LaunchServicesClient` (Tasks 7+9) |
| ✅ | `remove_login_item` (`batch.sh:213`) | osascript usuwa wpisy z Login Items | `LoginItemsClient` (Task 6) |
| ✅ | `force_kill_app` (`app_protection.sh:1887`) | drabinka quit→SIGTERM→SIGKILL przed usunięciem | `AppTerminator` (Tasks 4+5) |
| ❌ | `remove_apps_from_dock` (`common.sh:150`) | usuwa wpis z Docka | nowy helper |
| ❌ | `find_app_files` / `find_app_system_files` (`app_protection.sh:1151,1635`) | znacznie szerszy zestaw ścieżek niż `LeftoverPathProvider` (DiagnosticReports, vendor-nested, shared apps, pkg receipts) | rozszerzenie `LeftoverPathProvider` |
| ✅ | `should_protect_from_uninstall` / `is_critical_system_component` (`app_protection.sh:605,686`) | guard chroniący przed usunięciem komponentów systemowych | `AppProtectionGuard` (Tasks 1-3) |
| ❌ | `get_brew_cask_name` + `brew_uninstall_cask` (`uninstall/brew.sh:163,183`) | wykrywa cask i woła `brew uninstall --cask --zap` | nowy `HomebrewCaskClient` |
| ❌ | `has_sensitive_data` (`batch.sh:40`) | wykrywa pliki wrażliwe (.ssh, .aws, keychain) → ostrzeżenie | nowy helper |
| ❌ | System extension warning (`batch.sh:955`) | sprawdza `/Library/SystemExtensions` po usunięciu | post-purge check |
| ❌ | Local Network permissions warning (`batch.sh:21`) | wykrywa `NSLocalNetworkUsageDescription` | post-purge UI hint |
| ❌ | `pkg_receipt_nonstandard_app_paths` (`pkg_receipts.sh:31`) | parsuje `pkgutil` receipts | rozszerzenie skanera |

### Zrealizowana iteracja (2026-05-13)

Plan: [docs/superpowers/plans/2026-05-13-app-protection-and-purger-ux.md](docs/superpowers/plans/2026-05-13-app-protection-and-purger-ux.md) — 9 tasków TDD, 10 commitów (`00af347..d3eadc3`), 134/134 testów green.

**Nowe pliki Swift:**
- [AppProtectionGuard.swift](Sources/AutoCleanMacCore/AppProtectionGuard.swift) — pure-value enum z listami `systemCriticalPatterns` (~50 wzorców) + `appleUninstallablePatterns` (Xcode/iWork/FinalCut). Wzorce z `*` (glob → regex). Pusty bundleID = chroniony (defensywny default).
- [AppTerminator.swift](Sources/AutoCleanMacCore/AppTerminator.swift) — protocol + `ShellAppTerminator` z drabinką osascript quit (3s timeout) → SIGTERM (2s) → SIGKILL (2s).
- [LoginItemsClient.swift](Sources/AutoCleanMacCore/LoginItemsClient.swift) — protocol + `ShellLoginItemsClient` (osascript do System Events, usuwa po nazwie).
- [LaunchServicesClient.swift](Sources/AutoCleanMacCore/LaunchServicesClient.swift) — protocol + `ShellLaunchServicesClient` z `unregister(app:)` per-app i `rebuild()` per-batch (15s timeout + fallback bez `system` domain).

**Zmienione pliki:**
- [AppScanner.swift](Sources/AutoCleanMacCore/AppScanner.swift) — używa `AppProtectionGuard` zamiast `com.apple.*` prefix (Xcode/iWork teraz widoczne w uninstallerze).
- [AppPurger.swift](Sources/AutoCleanMacCore/AppPurger.swift) — guard na początku (refuse for protected), kolejność: terminate → loginItems → unregister → delete. Wszystko skipowane w dryRun.
- [AppDelegate.swift](Sources/AutoCleanMac/AppDelegate.swift) — produkcyjne wiring shell klientów; `rebuild()` w `Task.detached(priority: .utility)` po batchu (fire-and-forget, ~5-15s nie blokuje UI).

**Follow-upy zanotowane podczas review (nie blokujące):**
- `ShellAppTerminator.terminate` z `executableName: nil` używa bundleID jako `pgrep -x` match — rzadko trafia. Powinien być rozwiązany przez plumbing `CFBundleExecutable` z `Info.plist`.
- `ShellLoginItemsClient` ma lukę w escape (newline w `appName` może wybić AppleScript) i global `.app` strip — w praktyce display names z `CFBundleDisplayName` są bezpieczne, ale harden warto przed user-supplied names.
- Hardcoded `lsregister` path — silent fail jeśli kiedyś Apple go przeniesie. Warto `os_log` ostrzeżenie.
- Brak SIGKILL eskalacji w `ShellLaunchServicesClient.run` po timeout `terminate()` (low risk dla short-lived CLI).
- `osascript` może osierocić proces przy timeout w `ShellAppTerminator.runWithTimeout` (brak `terminate()` po stronie work-taska).

---

## Wysoki priorytet — rozszerzenia `CleanupTask`

`DevCachesTask.swift` (324 LOC) vs `lib/clean/dev.sh` (1 517 LOC). Mole ma czyszczenie dla:

- **JVM**: gradle daemon detection, JetBrains Toolbox/logs, Maven repo
- **Mobile**: Xcode derived data + device support + simulator runtime volumes + Android NDK
- **AI agents**: Codex runtimes (z detekcją stale runtimes)
- **JS**: npm, corepack, uv, frontend caches
- **Inne**: rust toolchains, conda metadata, mise, docker, nix, cloud SDKs, CI/CD, database, API tools, elixir/haskell/ocaml
- **Editors** (`clean_dev_editors`): cache edytorów IDE

**Najszybsze wygrane do dodania jako nowe `CleanupTask`:**

- `XcodeCleanupTask` — derived data + device support + simulator runtimes (`dev.sh:456,549,653`) — ogromne zwolnienie miejsca
- `TimeMachineSnapshotsTask` — `tmutil deletelocalsnapshots` (`system.sh:500`)
- `BrowserOldVersionsTask` — czyszczenie starych bundli po update Chrome/Edge/Brave (`user.sh:325,440,599`)
- `MavenRepoTask` (`maven.sh:8`)
- `JetBrainsCachesTask` (`dev.sh:1042,1149`)

---

## Średni priorytet — nowa kategoria „Optimize"

`lib/optimize/tasks.sh` (1 414 LOC) — kategoria której Swift app w ogóle nie ma.

**Bezpieczne do przeniesienia jako osobna zakładka w `SettingsView`:**

- `flush_dns_cache` — `dscacheutil -flushcache`
- `opt_sqlite_vacuum` — VACUUM na bazach SQLite użytkownika
- `opt_launch_services_rebuild` / `opt_font_cache_rebuild`
- `opt_quarantine_cleanup` — czyści `LSQuarantineEvents*.db`
- `opt_launch_agents_cleanup` (`tasks.sh:1008`) + `opt_login_items_audit` (`tasks.sh:1414`) — naturalnie pasują do `OrphanScanner`
- `opt_periodic_maintenance` — `periodic daily weekly monthly`
- `fix_broken_preferences` (`maintenance.sh:56`) — naprawa uszkodzonych plistów

---

## Średni priorytet — Whitelist UI

`__mole` ma pełny system whitelisty (`manage/whitelist.sh`) z walidacją path-traversal, ochroną systemu, deduplikacją. Swift app **nie ma whitelisty w ogóle**.

Logika do skopiowania jako `WhitelistManager.swift` + nowa zakładka w UI.

---

## Niższy priorytet (większy nakład pracy)

- **Disk analyzer** (`cmd/analyze/`, 6.7k LOC Go) — heap-based top-N skaner z TUI. Wymaga przepisania w Swift albo dołączenia binarki Go z UI. Praktycznie osobna apka.
- **System metrics** (`cmd/status/`, 6.6k LOC Go) — CPU/dysk/GPU/bateria/sieć/Bluetooth. Fajny dodatek do menu bar, ale duża praca i nakłada się z Activity Monitor.
- **TouchID dla sudo** (`bin/touchid.sh`) — Swift app już używa `ElevatedUninstall` z OSAuth/Helper, więc to byłaby alternatywa, nie uzupełnienie.

---

## Rekomendowana kolejność implementacji

1. **`AppProtectionGuard`** (najpierw bezpieczeństwo) — żeby `AppPurger` nie usunął np. Findera
2. **Login Items + LaunchServices unregister/rebuild + force_kill** w `AppPurger` (małe pliki, duża wartość UX)
3. **Brew cask detection** w `AppPurger` (typowy use-case — apki instalowane przez `brew install --cask`)
4. **Rozszerzenie `LeftoverPathProvider`** o ścieżki z `find_app_files`/`find_app_system_files`
5. **`XcodeCleanupTask`** + **`TimeMachineSnapshotsTask`** jako nowe taski
6. **Zakładka „Optimize"** z 3–4 bezpiecznymi zadaniami (DNS flush, font cache, periodic maintenance, SQLite vacuum)
7. **Whitelist UI**

---

## Mapa kluczowych plików `__mole` (do referencji przy implementacji)

```
__mole/
├── bin/
│   ├── uninstall.sh        (1331 LOC — main flow uninstallera)
│   ├── clean.sh            (47 KB — main flow czyszczenia)
│   ├── optimize.sh         (10 KB — main flow optimize)
│   └── purge.sh            (10 KB — quick purge project artifacts)
├── lib/
│   ├── core/
│   │   ├── app_protection.sh   (KRYTYCZNE — guards, find_app_files)
│   │   ├── file_ops.sh         (safe_remove, mole_delete, trash batch)
│   │   ├── pkg_receipts.sh     (pkgutil receipts parsing)
│   │   ├── sudo.sh             (sudo session + TouchID)
│   │   └── common.sh           (remove_apps_from_dock + utils)
│   ├── uninstall/
│   │   ├── batch.sh        (1162 LOC — pełny uninstall pipeline)
│   │   ├── brew.sh         (Homebrew cask detection/uninstall)
│   │   └── file_selector.sh (interaktywny picker plików)
│   ├── clean/
│   │   ├── dev.sh          (1517 LOC — wszystkie dev caches)
│   │   ├── system.sh       (deep system, Time Machine snapshots)
│   │   ├── user.sh         (chrome/edge/brave old versions, browsers)
│   │   ├── apps.sh         (DS_Store, orphan app data)
│   │   ├── app_caches.sh   (Xcode, JetBrains, FinalCut, etc.)
│   │   ├── caches.sh       (project caches)
│   │   ├── project.sh      (project artifacts purge)
│   │   └── maven.sh        (Maven repo)
│   ├── optimize/
│   │   ├── tasks.sh        (1414 LOC — wszystkie optimize tasks)
│   │   ├── maintenance.sh  (fix_broken_preferences)
│   │   └── diagnostics.sh  (detached disk images, CPU monitoring)
│   ├── manage/
│   │   ├── whitelist.sh    (whitelist management)
│   │   └── purge_paths.sh
│   └── check/
│       └── health_json.sh  (system metrics JSON)
└── cmd/
    ├── analyze/            (6.7k LOC Go — heap-based disk analyzer)
    └── status/             (6.6k LOC Go — CPU/mem/disk/GPU/battery/net)
```

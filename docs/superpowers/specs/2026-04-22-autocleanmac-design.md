# AutoCleanMac — Design

**Status:** Approved (brainstorming → implementation)
**Author:** micz
**Date:** 2026-04-22

## Purpose

Native macOS utility that runs at user login, shows a small "cute console" window on screen, and silently removes unneeded temporary files in a safe, auditable way. The app stays resident in the menu bar so the user can trigger cleanup manually, inspect logs, or edit configuration.

## Goals

- Elegant native look: small translucent floating window, vibrancy background, monospace output, gentle fade-in / fade-out.
- Safe by construction: no `rm -rf` on globs, every deletion constrained to an explicit allowed root with realpath verification, `--dry-run` mode available.
- Auditable: every deletion logged with path + size to `~/Library/Logs/AutoCleanMac/`.
- Configurable: retention window, per-task enable/disable, window timing — all in a user-editable JSON file.
- Zero ongoing noise: no Dock icon, no notifications, only a menu bar icon and the transient login window.

## Non-goals

- System-wide cleanup requiring `sudo` (no LaunchDaemon, no `/Library/Caches`).
- Aggressive deletion of user data (no `~/Downloads` by default — opt-in only).
- Cross-platform support (macOS only).
- Sandboxed App Store distribution (ad-hoc signed local install).

## User flow

1. User logs in.
2. LaunchAgent launches `AutoCleanMac.app`.
3. The app registers a menu bar icon (🧹) and opens a 480×320 floating console window centered on screen with a 0.8s fade-in.
4. `CleanupEngine` iterates over enabled tasks. Each line appears in the console as a task starts/finishes:
   ```
   ✓ User caches            92.4 MB
   ✓ System temp (>7d)      14.1 MB
   ⚠ Chrome cache — brak uprawnień do 1 pliku
   ✓ Xcode DerivedData       2.1 GB
   ─────────────────────────────────
     Zwolniono: 2.3 GB · 4.2s
   ```
5. After the summary line appears, the window holds for 3s then fades out (0.8s).
6. The app stays alive in the menu bar. Menu entries:
   - **Uruchom teraz** — repeat the cleanup flow (same window, same animation).
   - **Pokaż ostatnie sprzątanie** — open the most recent log file.
   - **Otwórz konfigurację** — open `~/.config/autoclean-mac/config.json` in the default editor.
   - **Otwórz folder logów** — reveal `~/Library/Logs/AutoCleanMac/` in Finder.
   - **Zakończ** — quit the app (LaunchAgent will restart it next login).

## Architecture

```
AutoCleanMac.app (SwiftUI, LSUIElement=true)
├── App                           ← @main, wires MenuBar + ConsoleWindow
├── MenuBarController             ← NSStatusItem, builds NSMenu
├── ConsoleWindow                 ← NSPanel w/ SwiftUI ConsoleView, floating level, vibrancy
│   └── ConsoleView               ← SF Mono lines, auto-scroll, ✓/⚠/✗ prefixes, summary footer
├── CleanupEngine                 ← async sequence of tasks; emits Progress events
├── Tasks/                        ← one file per task, all conform to CleanupTask protocol
│   ├── UserCachesTask
│   ├── SystemTempTask
│   ├── TrashTask
│   ├── DSStoreTask
│   ├── UserLogsTask
│   ├── BrowserCachesTask         ← Chrome, Safari, Firefox — cache only, never cookies/history
│   ├── DevCachesTask              ← npm, pip, brew cleanup, Xcode DerivedData
│   └── DownloadsTask              ← default OFF
├── SafeDeleter                   ← realpath + allowed-root check, per-file delete + size tally
├── Logger                        ← appends to ~/Library/Logs/AutoCleanMac/YYYY-MM-DD.log
└── Config                        ← loads/writes ~/.config/autoclean-mac/config.json

~/Library/LaunchAgents/com.micz.autocleanmac.plist
install.sh  /  uninstall.sh
```

### `CleanupTask` protocol

```swift
protocol CleanupTask {
    var displayName: String { get }     // "User caches"
    var isEnabled: Bool { get }         // from Config
    func run(context: CleanupContext) async throws -> TaskResult
}

struct TaskResult {
    let bytesFreed: Int64
    let warnings: [String]              // e.g. "brak uprawnień do 1 pliku"
}

struct CleanupContext {
    let retentionDays: Int
    let dryRun: Bool
    let logger: Logger
    let deleter: SafeDeleter
}
```

Each task:
1. Declares its allowed root(s) (absolute, resolved paths).
2. Enumerates candidate entries within that root using `FileManager`.
3. Filters by modification time (`mtime > retentionDays` when applicable).
4. For each candidate: calls `SafeDeleter.delete(path, withinRoot: allowedRoot)` which re-verifies realpath containment and records size.
5. Collects warnings (permission errors, busy files) but does not throw — errors are surfaced as ⚠ lines, never fatal.

### `SafeDeleter` contract

```swift
final class SafeDeleter {
    enum Mode { case live, dryRun }
    init(mode: Mode, logger: Logger)

    /// Deletes `path`. Returns bytes freed.
    /// Throws if `path` does not realpath-resolve inside `withinRoot`.
    /// In `.dryRun`, computes size and logs intent, never removes.
    func delete(_ path: URL, withinRoot: URL) throws -> Int64
}
```

Invariants:
- `path` is resolved with `URL.resolvingSymlinksInPath()` and `realpath(3)` before deletion.
- The resolved path must have `withinRoot`'s resolved path as a prefix; otherwise `DeletionError.outsideAllowedRoot`.
- Never follows symlinks out of `withinRoot`.
- Logs every deletion (or would-be deletion) with absolute path, size, mtime.

### Event flow (login scenario)

```
launchd (user) → AutoCleanMac.app starts
             ↓
   App.init:
     - MenuBarController installs NSStatusItem
     - ConsoleWindow created, fade-in 0.8s
     - CleanupEngine.run() kicked off
             ↓
   CleanupEngine loops tasks sequentially
     - Publishes ConsoleEvent.taskStarted / .taskFinished / .taskWarning
     - ConsoleView subscribes via Combine/@Observable
             ↓
   Summary event → ConsoleView renders footer
             ↓
   Timer 3s → window.fadeOut(0.8s) → window.orderOut
             ↓
   App keeps running (menu bar only)
```

### Tasks — concrete scope

**Enabled by default (A + B minus downloads):**

| Task | Root | Rule |
|------|------|------|
| User caches | `~/Library/Caches` | All regular files inside (busy files skipped via error handling) |
| System temp | `$TMPDIR` (resolves to `/private/var/folders/.../T`) | `mtime > 7d` |
| Trash | `~/.Trash` | `mtime > 7d` |
| DSStore | `~/Desktop`, `~/Documents`, `~/Downloads` | Files named exactly `.DS_Store` |
| User logs | `~/Library/Logs` | `mtime > 7d`, files only |
| Browser caches | Application Support cache dirs: `~/Library/Application Support/Google/Chrome/*/Cache`, `~/Library/Application Support/Google/Chrome/*/Code Cache`, `~/Library/Application Support/Firefox/Profiles/*/cache2` | Cache contents only; explicit allow-list by exact directory name `Cache`/`Code Cache`/`cache2` — never `Cookies`, `History`, `Bookmarks`, `Login Data`, etc. Safari cache already covered by User caches. |
| Dev caches | `~/Library/Developer/Xcode/DerivedData` (contents), `~/.npm/_cacache`, `~/Library/Caches/pip` | Contents older than 7d; plus run `brew cleanup --prune=7` if `brew` exists |

**Disabled by default:**

| Task | Root | Rule |
|------|------|------|
| Downloads | `~/Downloads` | `mtime > 7d`, files only, skip hidden files |

### Config file

`~/.config/autoclean-mac/config.json`:
```json
{
  "retention_days": 7,
  "window": {
    "fade_in_ms": 800,
    "hold_after_ms": 3000,
    "fade_out_ms": 800
  },
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
```

If the file is missing or malformed, the app falls back to defaults and logs a warning. Unknown keys are ignored (forward compatibility).

### LaunchAgent

`~/Library/LaunchAgents/com.micz.autocleanmac.plist`:

- `Label`: `com.micz.autocleanmac`
- `ProgramArguments`: `["/Users/micz/Applications/AutoCleanMac.app/Contents/MacOS/AutoCleanMac"]`
- `RunAtLoad`: `true`
- `KeepAlive`: `false` (we don't want to respawn after user quits via menu)
- `ProcessType`: `Interactive`

### Logging

`~/Library/Logs/AutoCleanMac/YYYY-MM-DD.log`. One file per day, appended if the app runs multiple times. Format (one line per event):

```
2026-04-22T08:30:12Z  start    login
2026-04-22T08:30:12Z  task     user_caches  begin
2026-04-22T08:30:13Z  delete   /Users/micz/Library/Caches/com.apple.Safari/WebKitCache/Version 16/Records/...   size=1432
2026-04-22T08:30:14Z  task     user_caches  end    freed=96784512 warnings=0
...
2026-04-22T08:30:18Z  summary  freed=2471234567 duration_ms=4210
```

## Install / uninstall

`install.sh`:
1. Check that Command Line Tools are present (`xcode-select -p`); if not, prompt `xcode-select --install` and exit.
2. Compile the Swift package (`swift build -c release`).
3. Assemble `.app` bundle (set `LSUIElement=true`, `CFBundleIdentifier=com.micz.autocleanmac`, icon if present).
4. Move bundle to `~/Applications/AutoCleanMac.app` (create `~/Applications` if missing).
5. Ad-hoc sign: `codesign --force --deep --sign - ~/Applications/AutoCleanMac.app`.
6. Write default `~/.config/autoclean-mac/config.json` if absent.
7. Write LaunchAgent plist and `launchctl load -w ~/Library/LaunchAgents/com.micz.autocleanmac.plist`.
8. Print a summary of what was installed and how to uninstall.

`uninstall.sh`:
1. `launchctl unload ~/Library/LaunchAgents/com.micz.autocleanmac.plist` and remove the plist.
2. Remove `~/Applications/AutoCleanMac.app`.
3. Prompt before removing `~/.config/autoclean-mac/` and `~/Library/Logs/AutoCleanMac/` (keep by default).

## Error handling

- Missing task root (e.g. user doesn't have Firefox): task reports "pominięte — katalog nie istnieje" as an info line, no warning.
- Permission denied: counted into `warnings`, surfaced as ⚠ line with the count (e.g. "brak uprawnień do 3 plików"), full paths in log file.
- Busy file (EBUSY, ETXTBSY): treated like permission denied — log and move on.
- Realpath escapes allowed root: treated as a bug — log an ERROR line and abort that task, continue to next.
- Config file malformed: log warning, use defaults, continue.
- `brew`/`npm`/`pip` commands missing or failing: info line "pominięte — narzędzie niedostępne", no warning.

## Testing strategy

- **Unit:** `SafeDeleter` realpath check with symlink escape attempts, allowed-root boundary cases.
- **Unit:** each task in `dryRun` mode against a fixture directory tree — verifies candidate selection without touching real files.
- **Integration:** full engine run against a temp directory populated by fixture — assert bytes freed, warnings count, log file contents.
- **Manual smoke:** install on the actual machine, verify login trigger, menu bar behavior, window animation, log output.

## Open questions (none at this time)

All design decisions resolved during brainstorming:
- Scope: options A + B with `downloads: false` default, retention 7 days.
- Trigger: LaunchAgent at login, plus manual via menu bar.
- UI: small floating console (480×320), always on top, fade in/out, shows all messages and warnings.
- Safety: realpath containment, dry-run mode, log every deletion.

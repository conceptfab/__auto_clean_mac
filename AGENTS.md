<claude-mem-context>
# Memory Context

# [__auto_clean_mac] recent context, 2026-04-24 10:05pm GMT+2

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 50 obs (18,777t read) | 570,254t work | 97% savings

### Apr 23, 2026
233 11:47p 🟣 AppDelegate.swift — Launch-at-Login Feature Fully Wired End-to-End
234 " 🟣 install.sh Respects Disabled Marker — Skips LaunchAgent on Reinstall When Autostart Is Off
235 " ✅ All 72 Tests Pass After Launch-at-Login Wiring; Release Build Clean
236 " ✅ AutoCleanMac v-launch-at-login Deployed to /Users/micz/Applications via install.sh
237 11:48p ✅ ConsoleView/ConsoleWindow Panel Size Increased from 560×400 to 600×500
238 11:49p ✅ SettingsSection Enum Reordered — Statistics Moved Near End, Before Logs
239 11:51p ✅ Autostart Toggle Relocated from RemindersTab to OverviewTab as Primary Control
240 " ✅ OverviewTab Removed Entirely — Settings Now Opens on CleanupTab by Default
241 11:52p 🔴 apply_patch Failed — RemindersTab Autostart Section Already Removed, File State Diverged
242 " 🔴 Autostart Section Re-Added to RemindersTab with Enhanced LabeledContent Status Row
### Apr 24, 2026
243 8:39a 🔵 AutoCleanMac Codebase Structure and Current Branch State
244 8:40a 🔵 AutoCleanMac Codebase Audit: Polish Hardcoded Strings, Manual JSON, LaunchAgent Architecture
245 8:41a 🔵 AutoCleanMac SettingsView Architecture: 8-Tab Settings with ObservableObject Model
246 " 🔵 LaunchAgentManager: Marker-File Pattern for Launch-at-Login State Persistence
247 " 🔵 BrowserDataTask: Chromium vs Firefox Path Discrimination for Cache/Cookies/History
248 " 🟣 CleanupContext Gains deletionMode Property for Task-Level Mode Inspection
249 " 🔴 FileEnumerator: Files with Missing mtime Now Excluded Instead of Silently Included
250 8:42a 🔴 AppDelegate: Cleanup No Longer Runs if Config Save Fails
251 " 🟣 DevCachesTask: brew cleanup Skipped in Non-Live Deletion Modes + Injectable Process Runner
252 " 🟣 DevCachesTask Dry-Run Test Added and Full Suite Passes: 73/73 Tests Green
253 8:45a 🔄 AppDelegate Major Refactor: LaunchContext + RunPresentation Enums, Live Statistics, Preview Mode
254 " 🟣 TaskResult Gains itemsDeleted Field and Sendable Conformance
255 " 🔵 AutoCleanMac Codebase: 25 Modified Files + 4 New Files in Working Tree (Uncommitted)
256 " 🟣 Homebrew Cleanup Promoted to First-Class Opt-In Config Task with UI Toggle
257 " 🔵 AutoCleanMac Package Structure: macOS 13+, Accessory App (No Dock Icon), Three Targets
258 8:46a ✅ homebrew_cleanup Propagated to All Default Config Sources: AppDelegate, install.sh, ConfigTests
259 " 🟣 DevCachesTask Brew Mode Coverage Expanded: Trash Skip + Live Run Tests Added
260 8:47a 🟣 AutoCleanMac Full Test Suite: 75/75 Tests Pass After homebrewCleanup Feature Addition
261 " 🔄 AppStatistics Migrated to AutoCleanMacCore with CleanupRunRecord History and Public API
262 8:48a 🟣 StatisticsTab Now Shows Cleanup Run History via CleanupHistoryRow Component
263 " 🟣 AppStatisticsTests Added: 4 Tests Cover Recording, History Capping, Round-Trip, and Legacy Compat
264 " 🟣 AutoCleanMac Test Suite Reaches 80/80: AppStatisticsTests Fully Green
265 8:49a 🟣 Config Gains excludedPaths Field with Tilde Expansion for User-Defined Cleanup Exclusions
266 " 🟣 CleanupContext Enforces Excluded Paths via isExcluded() and deleteMeasured() Wrapper
267 8:50a 🟣 Excluded Paths Feature Fully Wired: All Tasks Use context.deleteMeasured, UI Editor Added
268 " 🟣 CleanupTab Gets TextEditor for Excluded Paths + ConfigTests Cover Parsing and Tilde Resolution
269 " 🟣 Excluded Paths Integration Test: DownloadsTask Respects Exclusions with Warning per Skipped File
270 8:51a 🔴 Excluded Paths Test Corrected: File-Level Exclusion Instead of Directory-Level
271 " 🟣 Excluded Paths Feature Complete: 82/82 Tests Pass, Full End-to-End Coverage
272 " 🟣 Package.swift Gains AutoCleanMacTests Target for UI-Layer Unit Tests
273 " 🔄 LaunchAgentManager.launchAgentPlist() Promoted from private to internal for Testability
274 " 🟣 LaunchAgentManagerTests: Plist Content Verified via PropertyListSerialization Without launchctl
275 8:54a 🟣 AutoCleanMac — excludedPaths Feature Fully Shipped (82→83 Tests Green)
276 " 🟣 AutoCleanMac — AppStatistics Migrated to Core with Per-Run CleanupRunRecord History
277 " 🔴 brew cleanup Ran Destructively in dryRun/trash Modes
278 " 🟣 AutoCleanMacTests UI-Layer Test Target Added with LaunchAgentManagerTests
279 " 🔄 AppDelegate Refactored with LaunchContext/RunPresentation Enums and Statistics Tracking
280 " ✅ AutoCleanMac Full Code Review Session — 83 Tests, 1386 Insertions, 0 Failures
281 8:56a 🟣 AutoCleanMac — Single-Instance Enforcement via DistributedNotificationCenter
282 " 🔵 AutoCleanMac — Production Install Verified: LaunchAgent Running, statistics.json Populated with recentRuns

Access 570k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>
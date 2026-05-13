import Foundation

/// Bezpiecznościowa zapora przed usunięciem komponentów systemowych.
/// Czysto wartościowa — bez I/O. Logika oparta na `__mole/lib/core/app_protection.sh`.
///
/// Reguła: `isProtected = matchesSystemCritical && !matchesAppleUninstallable`.
/// Pusty bundle ID jest traktowany jako chroniony (defensywny default).
public enum AppProtectionGuard {

    /// Lista wzorców bundle ID krytycznych dla systemu — chronione przed odinstalowaniem.
    /// Wzorce wspierają `*` jako wildcard (konwertowany do `.*` w regex).
    public static let systemCriticalPatterns: [String] = [
        // Core macOS shell
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.Settings.*",
        "com.apple.controlcenter",
        "com.apple.controlcenter.*",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.AppStore",

        // System utility apps (built-in, in /System/Applications)
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.Photos",
        "com.apple.calculator",
        "com.apple.Dictionary",
        "com.apple.ScreenSharing",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility",
        "com.apple.KeychainAccess",
        "com.apple.Terminal",
        "com.apple.ScriptEditor2",
        "com.apple.FontBook",
        "com.apple.SystemProfiler",
        "com.apple.audio.AudioMIDISetup",
        "com.apple.MigrateAssistant",
        "com.apple.BootCampAssistant",

        // System services / daemons / frameworks
        "com.apple.SecurityAgent",
        "com.apple.CoreServices.*",
        "com.apple.SystemUIServer",
        "com.apple.backgroundtaskmanagement.*",
        "com.apple.loginitems.*",
        "com.apple.sharedfilelist.*",
        "com.apple.sfl.*",
        "com.apple.installer.*",
        "com.apple.security.*",
        "com.apple.keychain.*",
        "com.apple.trustd",
        "com.apple.securityd",
        "com.apple.cloudd",
        "com.apple.iCloud.*",
        "com.apple.WiFi.*",
        "com.apple.Bluetooth.*",

        // Input methods (system built-in)
        "com.apple.inputmethod.*",
        "com.apple.inputsource.*",
        "com.apple.TextInput.*",
        "com.apple.CharacterPicker.*",
        "com.apple.PressAndHold.*",

        // Legacy short tokens (some apps use plain names, not reverse-DNS)
        "loginwindow",
        "dock",
        "systempreferences",
        "finder",
        "safari",
    ]

    /// Lista aplikacji od Apple, które MOGĄ być odinstalowane (App Store / developer.apple.com).
    /// Te wzorce nadpisują `systemCriticalPatterns` gdy oba pasują.
    public static let appleUninstallablePatterns: [String] = [
        "com.apple.dt.*",          // Xcode, Instruments, FileMerge
        "com.apple.FinalCut.*",
        "com.apple.FinalCut",
        "com.apple.FinalCutPro",
        "com.apple.Motion",
        "com.apple.Compressor",
        "com.apple.logic.*",
        "com.apple.garageband.*",
        "com.apple.iMovie",
        "com.apple.iWork.*",
        "com.apple.MainStage.*",
        "com.apple.server.*",
        "com.apple.Playgrounds",
    ]

    /// Zwraca `true` jeśli aplikacji o danym bundle ID nie wolno odinstalowywać.
    public static func isProtected(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return true }
        if matches(bundleID: bundleID, patterns: appleUninstallablePatterns) {
            return false
        }
        return matches(bundleID: bundleID, patterns: systemCriticalPatterns)
    }

    private static func matches(bundleID: String, patterns: [String]) -> Bool {
        for pattern in patterns where wildcardMatch(bundleID, pattern: pattern) {
            return true
        }
        return false
    }

    /// Glob-style match: `*` w pattern = `.*` w regex. Reszta znaków eskejpowana.
    /// Case-sensitive (bundle ID-y są case-sensitive na APFS i w LaunchServices).
    private static func wildcardMatch(_ input: String, pattern: String) -> Bool {
        var regex = "^"
        for ch in pattern {
            if ch == "*" {
                regex += ".*"
            } else if ".\\+?()[]{}|^$".contains(ch) {
                regex += "\\\(ch)"
            } else {
                regex += String(ch)
            }
        }
        regex += "$"
        return input.range(of: regex, options: .regularExpression) != nil
    }
}

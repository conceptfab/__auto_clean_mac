import Foundation
import UserNotifications
@preconcurrency import AutoCleanMacCore

@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let logger: Logger
    private let notificationCenter: UNUserNotificationCenter
    private let onAutoCleanup: () -> Void

    private var timer: Timer?
    private var currentReminder: Config.Reminder = .default

    init(
        logger: Logger,
        notificationCenter: UNUserNotificationCenter = .current(),
        onAutoCleanup: @escaping () -> Void
    ) {
        self.logger = logger
        self.notificationCenter = notificationCenter
        self.onAutoCleanup = onAutoCleanup
        super.init()
        self.notificationCenter.delegate = self
    }

    func update(with reminder: Config.Reminder) {
        currentReminder = reminder
        timer?.invalidate()
        timer = nil

        guard reminder.mode != .off else {
            logger.log(event: "reminder_disabled")
            return
        }

        if reminder.mode == .remind {
            requestNotificationAuthorization()
        }

        let interval = TimeInterval(max(1, reminder.intervalHours) * 3600)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fire()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        logger.log(event: "reminder_scheduled", fields: [
            "mode": reminder.mode.rawValue,
            "interval_hours": "\(max(1, reminder.intervalHours))",
        ])
    }

    private func fire() {
        switch currentReminder.mode {
        case .off:
            break
        case .remind:
            sendReminderNotification()
        case .autoClean:
            logger.log(event: "reminder_auto_cleanup_trigger")
            onAutoCleanup()
        }
    }

    private func requestNotificationAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.log(event: "reminder_notifications_error", fields: ["error": "\(error)"])
                return
            }
            logger.log(event: "reminder_notifications_auth", fields: [
                "granted": granted ? "true" : "false",
            ])
        }
    }

    private func sendReminderNotification() {
        let content = UNMutableNotificationContent()
        content.title = "AutoCleanMac"
        content.subtitle = "Czas na cleanup"
        content.body = "Minął ustawiony interwał. Otwórz aplikację i odzyskaj trochę miejsca."
        content.sound = .default
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .active
        }

        let request = UNNotificationRequest(
            identifier: "autocleanmac.reminder.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { [logger] error in
            if let error {
                logger.log(event: "reminder_notification_failed", fields: ["error": "\(error)"])
            } else {
                logger.log(event: "reminder_notification_sent")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
        Task { @MainActor [weak self] in
            self?.logger.log(event: "reminder_notification_presented")
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        Task { @MainActor [weak self] in
            self?.logger.log(event: "reminder_notification_opened")
        }
    }
}

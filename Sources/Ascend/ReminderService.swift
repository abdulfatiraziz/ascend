import AppKit
import UserNotifications
import AscendCore

@MainActor final class ReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var status = "Off"
    @Published private(set) var authorized = false
    private let center = UNUserNotificationCenter.current()
    private var scheduling: Task<Void, Never>?

    override init() { super.init(); center.delegate = self }

    func enable(_ document: TrackerDocument) async -> Bool {
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            authorized = allowed
            status = allowed ? "Allowed by macOS" : "Blocked in macOS Settings"
            return allowed
        } catch { status = "Permission failed: \(error.localizedDescription)"; return false }
    }
    func refresh(_ document: TrackerDocument) {
        let previous = scheduling
        previous?.cancel()
        scheduling = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let settings = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            status = document.reminders.enabled ? (authorized ? "Reminders on" : "Blocked in macOS Settings") : "Reminders off"
            // This app owns only its own notification center namespace.
            center.removeAllPendingNotificationRequests()
            guard document.reminders.enabled, authorized else { return }
            let engine = TrackerEngine(document: document)
            for item in engine.plannedReminders(now: Date()) {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title; content.body = item.body
                if document.reminders.sound { content.sound = .default }
                var components = engine.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                components.calendar = engine.calendar; components.timeZone = engine.calendar.timeZone
                do {
                    try await center.add(UNNotificationRequest(identifier: item.id, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                } catch { status = "Scheduling failed: \(error.localizedDescription)" }
                if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [item.id]); return }
            }
        }
    }
    func test(sound: Bool) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { status = "Allow notifications in macOS Settings first."; return }
        let content = UNMutableNotificationContent()
        content.title = "Ascend is ready"; content.body = "Your next version starts with a check-in."
        if sound { content.sound = .default }
        do {
            try await center.add(UNNotificationRequest(identifier: "ascend.test", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
            status = "Test scheduled for 3 seconds from now"
            try await Task.sleep(for: .seconds(4))
            let delivered = await center.deliveredNotifications()
            status = delivered.contains { $0.request.identifier == "ascend.test" }
                ? "Test delivered to Notification Center"
                : "Test scheduled. Check macOS Focus and notification settings if it does not appear."
        } catch { status = error.localizedDescription }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .ascendNotificationOpened, object: nil)
            NSApp.windows.first { $0.title == "Ascend" }?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        completionHandler()
    }
}
extension Notification.Name { static let ascendNotificationOpened = Notification.Name("AscendNotificationOpened") }

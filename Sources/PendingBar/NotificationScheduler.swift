import AppKit
import Foundation
import PendingKit
import UserNotifications

enum NotificationAction {
    case open
    case done
    case snoozeHour
}

@MainActor
final class NotificationScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "PENDINGBAR_TASK"
    static let identifierPrefix = "pendingbar|"

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduledCount = 0
    @Published private(set) var nextFireAt: Date?

    var onAction: ((String, NotificationAction) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        let done = UNNotificationAction(identifier: "DONE", title: "Mark done")
        let snooze = UNNotificationAction(identifier: "SNOOZE_1H", title: "Snooze 1 hour")
        let open = UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [open, done, snooze],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
        }
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
    }

    func reschedule(tasks: [TaskItem], offsets: [ReminderOffset], now: Date = Date()) {
        let plans = ReminderPlanner.plan(tasks: tasks, offsets: offsets, now: now)
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        Task {
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for plan in plans {
                guard let task = byID[plan.taskID] else { continue }
                let request = UNNotificationRequest(
                    identifier: plan.identifier,
                    content: content(for: task, offset: plan.offset),
                    trigger: trigger(at: plan.fireAt)
                )
                try? await center.add(request)
            }
            scheduledCount = plans.count
            nextFireAt = plans.first?.fireAt
        }
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "PendingBar reminders work"
        content.subtitle = "Due in 20 min · Test"
        content.body = "This is how a reminder will look."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pendingbar-test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        center.add(request)
    }

    private func content(for task: TaskItem, offset: ReminderOffset) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.subtitle = "\(offset.shortPhrase) · \(SourceCatalog.displayName(for: task.source))"
        if let detail = task.detail, !detail.isEmpty {
            content.body = detail
        } else if let dueAt = task.dueAt {
            content.body = "Due \(dueAt.formatted(date: .abbreviated, time: .shortened))"
        }
        content.sound = .default
        content.threadIdentifier = task.id
        content.categoryIdentifier = Self.categoryIdentifier
        var info: [String: String] = ["taskID": task.id]
        if let url = task.url {
            info["url"] = url.absoluteString
        }
        content.userInfo = info
        return content
    }

    private func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let taskID = info["taskID"] as? String
        let action: NotificationAction
        switch response.actionIdentifier {
        case "DONE":
            action = .done
        case "SNOOZE_1H":
            action = .snoozeHour
        default:
            action = .open
        }
        Task { @MainActor in
            if let taskID {
                self.onAction?(taskID, action)
            }
        }
        completionHandler()
    }
}

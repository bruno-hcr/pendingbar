import Foundation

public struct ReminderOffset: Hashable, Codable, Sendable, Identifiable {
    public var minutes: Int

    public var id: Int { minutes }

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public var seconds: TimeInterval { TimeInterval(minutes * 60) }

    public static let presets: [ReminderOffset] = [2880, 1440, 60, 20, 10, 5].map(ReminderOffset.init(minutes:))
    public static let atDue = ReminderOffset(minutes: 0)

    public var label: String {
        if minutes == 0 {
            return "At due time"
        }
        if minutes % 1440 == 0, minutes >= 1440 {
            let hours = minutes / 60
            return "\(hours) hours before"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour before" : "\(hours) hours before"
        }
        return "\(minutes) minutes before"
    }

    public var shortPhrase: String {
        if minutes == 0 {
            return "Due now"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "Due in 1 hour" : "Due in \(hours) hours"
        }
        return "Due in \(minutes) min"
    }
}

public struct PlannedReminder: Hashable, Sendable {
    public var taskID: String
    public var offset: ReminderOffset
    public var fireAt: Date
    public var dueAt: Date

    public var identifier: String { "pendingbar|\(taskID)|\(offset.minutes)" }
}

public enum ReminderPlanner {
    public static let systemPendingLimit = 60

    public static func plan(
        tasks: [TaskItem],
        offsets: [ReminderOffset],
        now: Date,
        limit: Int = systemPendingLimit
    ) -> [PlannedReminder] {
        let uniqueOffsets = Array(Set(offsets)).sorted { $0.minutes > $1.minutes }
        var plans: [PlannedReminder] = []
        for task in tasks where task.isOpen {
            guard let dueAt = task.dueAt else { continue }
            for offset in uniqueOffsets {
                let fireAt = dueAt.addingTimeInterval(-offset.seconds)
                guard fireAt > now else { continue }
                if let snoozedUntil = task.snoozedUntil, snoozedUntil > fireAt {
                    continue
                }
                plans.append(PlannedReminder(taskID: task.id, offset: offset, fireAt: fireAt, dueAt: dueAt))
            }
        }
        plans.sort { lhs, rhs in
            if lhs.fireAt != rhs.fireAt {
                return lhs.fireAt < rhs.fireAt
            }
            return lhs.taskID < rhs.taskID
        }
        return Array(plans.prefix(limit))
    }
}

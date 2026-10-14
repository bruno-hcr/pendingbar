import PendingKit
import SwiftUI

extension TaskPriority {
    var color: Color {
        switch self {
        case .urgent: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .gray
        }
    }
}

enum DueText {
    static func describe(_ due: Date, now: Date, calendar: Calendar = .current) -> String {
        let delta = due.timeIntervalSince(now)
        if delta <= 0 {
            return "overdue \(span(-delta))"
        }
        if delta < 3600 {
            return "in \(span(delta))"
        }
        if calendar.isDate(due, inSameDayAs: now) {
            return "today \(due.formatted(date: .omitted, time: .shortened))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            return "tomorrow \(due.formatted(date: .omitted, time: .shortened))"
        }
        if delta < 6 * 86400 {
            return due.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return due.formatted(.dateTime.month(.abbreviated).day())
    }

    static func color(_ due: Date, now: Date) -> Color {
        let delta = due.timeIntervalSince(now)
        if delta <= 0 { return .red }
        if delta < 3600 { return .orange }
        if delta < 86400 { return .primary }
        return .secondary
    }

    static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

enum SnoozeChoice: CaseIterable, Identifiable {
    case oneHour
    case threeHours
    case tomorrowMorning
    case nextMonday

    var id: Self { self }

    var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .threeHours: "3 hours"
        case .tomorrowMorning: "Tomorrow 9:00"
        case .nextMonday: "Monday 9:00"
        }
    }

    func date(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .threeHours:
            return now.addingTimeInterval(3 * 3600)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .nextMonday:
            let monday = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2), matchingPolicy: .nextTime)
            return monday ?? now.addingTimeInterval(7 * 86400)
        }
    }
}

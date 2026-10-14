import Foundation

public enum TaskSortOrder: String, CaseIterable, Codable, Sendable, Identifiable {
    case priority
    case dueDate
    case source

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .priority: "Priority"
        case .dueDate: "Due date"
        case .source: "App"
        }
    }
}

public struct TaskSection: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var tasks: [TaskItem]
}

public enum DueBucket: Int, CaseIterable, Sendable {
    case overdue
    case today
    case tomorrow
    case thisWeek
    case later
    case noDueDate

    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "Next 7 days"
        case .later: "Later"
        case .noDueDate: "No due date"
        }
    }

    public static func of(_ task: TaskItem, now: Date, calendar: Calendar = .current) -> DueBucket {
        guard let dueAt = task.dueAt else { return .noDueDate }
        if dueAt <= now { return .overdue }
        if calendar.isDate(dueAt, inSameDayAs: now) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(dueAt, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        if dueAt.timeIntervalSince(now) <= 7 * 86400 { return .thisWeek }
        return .later
    }
}

public enum TaskSorting {
    public static func sorted(_ tasks: [TaskItem], by order: TaskSortOrder) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch order {
            case .priority:
                return compare(
                    lhs, rhs,
                    keys: [rankKey, dueKey, titleKey]
                )
            case .dueDate:
                return compare(
                    lhs, rhs,
                    keys: [dueKey, rankKey, titleKey]
                )
            case .source:
                return compare(
                    lhs, rhs,
                    keys: [sourceKey, rankKey, dueKey, titleKey]
                )
            }
        }
    }

    public static func sections(_ tasks: [TaskItem], by order: TaskSortOrder, now: Date) -> [TaskSection] {
        let ordered = sorted(tasks, by: order)
        switch order {
        case .priority:
            return TaskPriority.allCases.compactMap { priority in
                let items = ordered.filter { $0.priority == priority }
                guard !items.isEmpty else { return nil }
                return TaskSection(id: "priority-\(priority.rawValue)", title: priority.label, tasks: items)
            }
        case .dueDate:
            return DueBucket.allCases.compactMap { bucket in
                let items = ordered.filter { DueBucket.of($0, now: now) == bucket }
                guard !items.isEmpty else { return nil }
                return TaskSection(id: "due-\(bucket.rawValue)", title: bucket.title, tasks: items)
            }
        case .source:
            var seen: [String] = []
            for task in ordered where !seen.contains(task.source.lowercased()) {
                seen.append(task.source.lowercased())
            }
            return seen.map { source in
                let items = ordered.filter { $0.source.lowercased() == source }
                return TaskSection(id: "source-\(source)", title: SourceCatalog.displayName(for: source), tasks: items)
            }
        }
    }

    private typealias Key = (TaskItem, TaskItem) -> ComparisonResult

    private static let rankKey: Key = { lhs, rhs in
        order(lhs.priority.rank, rhs.priority.rank)
    }

    private static let dueKey: Key = { lhs, rhs in
        order(lhs.dueAt ?? .distantFuture, rhs.dueAt ?? .distantFuture)
    }

    private static let sourceKey: Key = { lhs, rhs in
        order(lhs.source.lowercased(), rhs.source.lowercased())
    }

    private static let titleKey: Key = { lhs, rhs in
        lhs.title.localizedCaseInsensitiveCompare(rhs.title)
    }

    private static func order<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private static func compare(_ lhs: TaskItem, _ rhs: TaskItem, keys: [Key]) -> Bool {
        for key in keys {
            let result = key(lhs, rhs)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        }
        return lhs.id < rhs.id
    }
}

public enum SourceCatalog {
    public static func displayName(for source: String) -> String {
        switch source.lowercased() {
        case "slack": "Slack"
        case "slack-todo": "Slack To-dos"
        case "gmail", "email": "Email"
        case "calendar": "Calendar"
        case "linear": "Linear"
        case "pagerduty": "PagerDuty"
        case "signoz": "SigNoz"
        case "github": "GitHub"
        case "manual": "Manual"
        default: source.capitalized
        }
    }

    public static func symbol(for source: String) -> String {
        switch source.lowercased() {
        case "slack": "number"
        case "slack-todo": "bell"
        case "gmail", "email": "envelope"
        case "calendar": "calendar"
        case "linear": "square.stack.3d.up"
        case "pagerduty": "light.beacon.max"
        case "signoz": "waveform.path.ecg"
        case "github": "chevron.left.forwardslash.chevron.right"
        case "manual": "pencil"
        default: "tray"
        }
    }
}

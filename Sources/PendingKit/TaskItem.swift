import Foundation

public enum TaskPriority: String, Codable, CaseIterable, Comparable, Sendable {
    case urgent
    case high
    case medium
    case low

    public var rank: Int {
        switch self {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }

    public var label: String {
        switch self {
        case .urgent: "Urgent"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rank < rhs.rank
    }

    public init?(loose value: String) {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "urgent", "critical", "p0", "1":
            self = .urgent
        case "high", "p1", "2":
            self = .high
        case "medium", "normal", "warning", "p2", "3":
            self = .medium
        case "low", "none", "p3", "4", "0":
            self = .low
        default:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self), let parsed = TaskPriority(loose: String(number)) {
            self = parsed
            return
        }
        let text = try container.decode(String.self)
        guard let parsed = TaskPriority(loose: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown priority '\(text)'")
        }
        self = parsed
    }
}

public enum CompletionReason: String, Codable, Sendable {
    case user
    case resolvedUpstream
}

public struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String?
    public var source: String
    public var url: URL?
    public var priority: TaskPriority
    public var dueAt: Date?
    public var origin: String
    public var firstSeenAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var completionReason: CompletionReason?
    public var snoozedUntil: Date?

    public static let manualOrigin = "manual"

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        source: String,
        url: URL? = nil,
        priority: TaskPriority = .medium,
        dueAt: Date? = nil,
        origin: String = TaskItem.manualOrigin,
        firstSeenAt: Date,
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        completionReason: CompletionReason? = nil,
        snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.source = source
        self.url = url
        self.priority = priority
        self.dueAt = dueAt
        self.origin = origin
        self.firstSeenAt = firstSeenAt
        self.updatedAt = updatedAt ?? firstSeenAt
        self.completedAt = completedAt
        self.completionReason = completionReason
        self.snoozedUntil = snoozedUntil
    }

    public var isOpen: Bool { completedAt == nil }

    public var isManual: Bool { origin == TaskItem.manualOrigin }

    public func isSnoozed(at now: Date) -> Bool {
        guard let snoozedUntil else { return false }
        return snoozedUntil > now
    }

    public func isOverdue(at now: Date) -> Bool {
        guard isOpen, let dueAt else { return false }
        return dueAt <= now
    }
}

public struct SyncStamp: Codable, Hashable, Sendable {
    public var at: Date
    public var mode: SyncMode
    public var result: SyncResult
    public var checkedSources: [String]?

    public init(at: Date, mode: SyncMode, result: SyncResult, checkedSources: [String]?) {
        self.at = at
        self.mode = mode
        self.result = result
        self.checkedSources = checkedSources
    }
}

public struct StoreDocument: Codable, Sendable {
    public var version: Int
    public var tasks: [TaskItem]
    public var lastSync: [String: SyncStamp]

    public init(version: Int = 1, tasks: [TaskItem] = [], lastSync: [String: SyncStamp] = [:]) {
        self.version = version
        self.tasks = tasks
        self.lastSync = lastSync
    }
}

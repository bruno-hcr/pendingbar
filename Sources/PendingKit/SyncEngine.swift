import Foundation

public enum SyncMode: String, Codable, Sendable {
    case snapshot
    case merge
}

public struct IncomingTask: Decodable, Sendable {
    public var id: String
    public var title: String
    public var detail: String?
    public var source: String
    public var url: URL?
    public var priority: TaskPriority?
    public var dueAt: Date?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        source: String,
        url: URL? = nil,
        priority: TaskPriority? = nil,
        dueAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.source = source
        self.url = url
        self.priority = priority
        self.dueAt = dueAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, source, url, priority, dueAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        source = try container.decode(String.self, forKey: .source)
        if let rawURL = try container.decodeIfPresent(String.self, forKey: .url), !rawURL.isEmpty {
            url = URL(string: rawURL)
        } else {
            url = nil
        }
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
    }
}

public struct SyncPayload: Decodable, Sendable {
    public var origin: String
    public var mode: SyncMode
    public var checkedSources: [String]?
    public var tasks: [IncomingTask]
    public var resolved: [String]?

    public init(origin: String, mode: SyncMode = .merge, checkedSources: [String]? = nil, tasks: [IncomingTask], resolved: [String]? = nil) {
        self.origin = origin
        self.mode = mode
        self.checkedSources = checkedSources
        self.tasks = tasks
        self.resolved = resolved
    }

    private enum CodingKeys: String, CodingKey {
        case origin, mode, checkedSources, tasks, resolved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        origin = try container.decode(String.self, forKey: .origin)
        mode = try container.decodeIfPresent(SyncMode.self, forKey: .mode) ?? .merge
        checkedSources = try container.decodeIfPresent([String].self, forKey: .checkedSources)
        tasks = try container.decodeIfPresent([IncomingTask].self, forKey: .tasks) ?? []
        resolved = try container.decodeIfPresent([String].self, forKey: .resolved)
    }
}

public struct SyncResult: Codable, Hashable, Sendable {
    public var added = 0
    public var updated = 0
    public var reopened = 0
    public var unchanged = 0
    public var resolved = 0
    public var keptDoneByUser = 0

    public init() {}
}

public enum SyncError: Error, LocalizedError {
    case manualOrigin
    case emptyID

    public var errorDescription: String? {
        switch self {
        case .manualOrigin:
            "The origin 'manual' is reserved for tasks added by hand."
        case .emptyID:
            "Every task needs a non-empty id."
        }
    }
}

public enum SyncEngine {
    public static let completedRetention: TimeInterval = 14 * 86400

    public static func apply(_ payload: SyncPayload, to tasks: [TaskItem], now: Date) throws -> ([TaskItem], SyncResult) {
        guard payload.origin != TaskItem.manualOrigin else {
            throw SyncError.manualOrigin
        }
        var result = SyncResult()
        var byID: [String: Int] = [:]
        var output = tasks
        for (index, task) in output.enumerated() {
            byID[task.id] = index
        }

        var incomingIDs = Set<String>()
        for incoming in payload.tasks {
            let id = incoming.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw SyncError.emptyID
            }
            incomingIDs.insert(id)

            guard let index = byID[id] else {
                let task = TaskItem(
                    id: id,
                    title: incoming.title,
                    detail: incoming.detail,
                    source: incoming.source,
                    url: incoming.url,
                    priority: incoming.priority ?? .medium,
                    dueAt: incoming.dueAt,
                    origin: payload.origin,
                    firstSeenAt: now
                )
                byID[id] = output.count
                output.append(task)
                result.added += 1
                continue
            }

            var existing = output[index]
            if existing.completionReason == .user {
                result.keptDoneByUser += 1
                continue
            }

            let wasResolved = existing.completedAt != nil
            var changed = false
            changed = assign(&existing.title, incoming.title) || changed
            changed = assign(&existing.detail, incoming.detail) || changed
            changed = assign(&existing.source, incoming.source) || changed
            changed = assign(&existing.url, incoming.url) || changed
            changed = assign(&existing.priority, incoming.priority ?? existing.priority) || changed
            changed = assign(&existing.dueAt, incoming.dueAt) || changed
            if !existing.isManual {
                existing.origin = payload.origin
            }

            if wasResolved {
                existing.completedAt = nil
                existing.completionReason = nil
                existing.updatedAt = now
                result.reopened += 1
            } else if changed {
                existing.updatedAt = now
                result.updated += 1
            } else {
                result.unchanged += 1
            }
            output[index] = existing
        }

        if payload.mode == .snapshot {
            let checked = payload.checkedSources.map { Set($0.map { $0.lowercased() }) }
            for index in output.indices {
                let task = output[index]
                guard task.isOpen, task.origin == payload.origin, !incomingIDs.contains(task.id) else {
                    continue
                }
                if let checked, !checked.contains(task.source.lowercased()) {
                    continue
                }
                output[index].completedAt = now
                output[index].completionReason = .resolvedUpstream
                output[index].updatedAt = now
                result.resolved += 1
            }
        }

        let explicitlyResolved = Set(payload.resolved ?? []).subtracting(incomingIDs)
        for index in output.indices where explicitlyResolved.contains(output[index].id) {
            guard output[index].isOpen, output[index].origin == payload.origin else { continue }
            output[index].completedAt = now
            output[index].completionReason = .resolvedUpstream
            output[index].updatedAt = now
            result.resolved += 1
        }

        return (output, result)
    }

    public static func prune(_ tasks: [TaskItem], now: Date) -> [TaskItem] {
        tasks.filter { task in
            guard let completedAt = task.completedAt else { return true }
            return now.timeIntervalSince(completedAt) < completedRetention
        }
    }

    private static func assign<Value: Equatable>(_ target: inout Value, _ value: Value) -> Bool {
        guard target != value else { return false }
        target = value
        return true
    }
}

public enum TaskMutation {
    public static func complete(_ id: String, in tasks: inout [TaskItem], now: Date) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        tasks[index].completedAt = now
        tasks[index].completionReason = .user
        tasks[index].updatedAt = now
        return true
    }

    public static func reopen(_ id: String, in tasks: inout [TaskItem], now: Date) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        tasks[index].completedAt = nil
        tasks[index].completionReason = nil
        tasks[index].updatedAt = now
        return true
    }

    public static func snooze(_ id: String, until: Date?, in tasks: inout [TaskItem], now: Date) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        tasks[index].snoozedUntil = until
        tasks[index].updatedAt = now
        return true
    }

    public static func delete(_ id: String, in tasks: inout [TaskItem]) -> Bool {
        let before = tasks.count
        tasks.removeAll { $0.id == id }
        return tasks.count != before
    }

    @discardableResult
    public static func addManual(
        title: String,
        detail: String? = nil,
        source: String = "manual",
        url: URL? = nil,
        priority: TaskPriority = .medium,
        dueAt: Date? = nil,
        id: String? = nil,
        in tasks: inout [TaskItem],
        now: Date
    ) -> TaskItem {
        let task = TaskItem(
            id: id ?? "manual:\(UUID().uuidString.lowercased())",
            title: title,
            detail: detail,
            source: source,
            url: url,
            priority: priority,
            dueAt: dueAt,
            origin: TaskItem.manualOrigin,
            firstSeenAt: now
        )
        tasks.removeAll { $0.id == task.id }
        tasks.append(task)
        return task
    }
}

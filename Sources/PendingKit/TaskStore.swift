import Foundation

public enum TaskStoreError: Error, LocalizedError {
    case lockFailed(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case let .lockFailed(path):
            "Could not lock \(path)."
        case let .unreadable(message):
            "Could not read the task store: \(message)"
        }
    }
}

public final class TaskStore: @unchecked Sendable {
    public let directory: URL

    public var fileURL: URL { directory.appendingPathComponent("tasks.json") }
    public var lockURL: URL { directory.appendingPathComponent(".tasks.lock") }

    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["PENDINGBAR_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PendingBar", isDirectory: true)
    }

    public init(directory: URL = TaskStore.defaultDirectory) {
        self.directory = directory
    }

    public func read() throws -> StoreDocument {
        try ensureDirectory()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoreDocument()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            if data.isEmpty {
                return StoreDocument()
            }
            return try DateParsing.makeDecoder().decode(StoreDocument.self, from: data)
        } catch {
            throw TaskStoreError.unreadable(error.localizedDescription)
        }
    }

    @discardableResult
    public func mutate<Result>(now: Date = Date(), _ body: (inout StoreDocument) throws -> Result) throws -> Result {
        try ensureDirectory()
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw TaskStoreError.lockFailed(lockURL.path)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw TaskStoreError.lockFailed(lockURL.path)
        }
        defer { flock(descriptor, LOCK_UN) }

        var document = try read()
        let result = try body(&document)
        document.tasks = SyncEngine.prune(document.tasks, now: now)
        let data = try DateParsing.makeEncoder().encode(document)
        try data.write(to: fileURL, options: [.atomic])
        return result
    }

    public func sync(_ payload: SyncPayload, now: Date = Date()) throws -> SyncResult {
        try mutate(now: now) { document in
            let (tasks, result) = try SyncEngine.apply(payload, to: document.tasks, now: now)
            document.tasks = tasks
            document.lastSync[payload.origin] = SyncStamp(
                at: now,
                mode: payload.mode,
                result: result,
                checkedSources: payload.checkedSources
            )
            return result
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

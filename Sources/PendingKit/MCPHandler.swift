import Foundation

public final class MCPHandler {
    public static let serverName = "pendingbar"
    public static let serverVersion = "0.1.0"
    public static let fallbackProtocolVersion = "2025-06-18"

    private let store: TaskStore
    private let clock: () -> Date

    public init(store: TaskStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
    }

    public func handle(line: String) -> String? {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? [String: Any]
        else {
            return encode(errorResponse(id: NSNull(), code: -32700, message: "Parse error"))
        }
        guard let response = handle(message: message) else { return nil }
        return encode(response)
    }

    public func handle(message: [String: Any]) -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        guard let id, !(id is NSNull) else {
            return nil
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            return success(id: id, result: [
                "protocolVersion": requested ?? Self.fallbackProtocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": Self.serverName, "version": Self.serverVersion],
                "instructions": "Task list behind the PendingBar menu bar app. Use pending_sync with mode snapshot and checkedSources to publish a daily sweep; tasks missing from a snapshot are resolved only when their source was checked."
            ])
        case "ping":
            return success(id: id, result: [:])
        case "tools/list":
            return success(id: id, result: ["tools": Self.toolDefinitions])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return success(id: id, result: callTool(name: name, arguments: arguments))
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            let output: Any
            switch name {
            case "pending_sync":
                output = try syncTool(arguments)
            case "pending_list":
                output = try listTool(arguments)
            case "pending_add":
                output = try addTool(arguments)
            case "pending_complete":
                output = try completeTool(arguments)
            case "pending_snooze":
                output = try snoozeTool(arguments)
            default:
                return toolError("Unknown tool \(name)")
            }
            return ["content": [["type": "text", "text": text(output)]], "isError": false]
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private func syncTool(_ arguments: [String: Any]) throws -> Any {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        let payload = try DateParsing.makeDecoder().decode(SyncPayload.self, from: data)
        let result = try store.sync(payload, now: clock())
        return try jsonObject(result)
    }

    private func listTool(_ arguments: [String: Any]) throws -> Any {
        let includeCompleted = arguments["includeCompleted"] as? Bool ?? false
        let source = (arguments["source"] as? String)?.lowercased()
        let document = try store.read()
        let tasks = TaskSorting.sorted(document.tasks, by: .priority).filter { task in
            (includeCompleted || task.isOpen) && (source == nil || task.source.lowercased() == source)
        }
        return try jsonObject(tasks)
    }

    private func addTool(_ arguments: [String: Any]) throws -> Any {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw MCPToolError.missing("title")
        }
        let now = clock()
        let priority = (arguments["priority"] as? String).flatMap(TaskPriority.init(loose:)) ?? .medium
        let due = (arguments["dueAt"] as? String).flatMap { DateParsing.parse($0, now: now) }
        let url = (arguments["url"] as? String).flatMap(URL.init(string:))
        let task = try store.mutate(now: now) { document in
            TaskMutation.addManual(
                title: title,
                detail: arguments["detail"] as? String,
                source: arguments["source"] as? String ?? "manual",
                url: url,
                priority: priority,
                dueAt: due,
                id: arguments["id"] as? String,
                in: &document.tasks,
                now: now
            )
        }
        return try jsonObject(task)
    }

    private func completeTool(_ arguments: [String: Any]) throws -> Any {
        guard let id = arguments["id"] as? String else { throw MCPToolError.missing("id") }
        let now = clock()
        let found = try store.mutate(now: now) { document in
            TaskMutation.complete(id, in: &document.tasks, now: now)
        }
        guard found else { throw MCPToolError.notFound(id) }
        return ["completed": id]
    }

    private func snoozeTool(_ arguments: [String: Any]) throws -> Any {
        guard let id = arguments["id"] as? String else { throw MCPToolError.missing("id") }
        guard let raw = arguments["until"] as? String else { throw MCPToolError.missing("until") }
        let now = clock()
        guard let until = DateParsing.parse(raw, now: now) else { throw MCPToolError.badDate(raw) }
        let found = try store.mutate(now: now) { document in
            TaskMutation.snooze(id, until: until, in: &document.tasks, now: now)
        }
        guard found else { throw MCPToolError.notFound(id) }
        return ["snoozed": id, "until": DateParsing.iso(until)]
    }

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> Any {
        let data = try DateParsing.makeEncoder(pretty: false).encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func text(_ value: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
            let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: value)
        }
        return string
    }

    private func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private func success(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static let taskSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "id": ["type": "string", "description": "Stable key, for example linear:ENG-123 or slack:C0123456789/1700000000.000100. The same id updates the same task."],
            "title": ["type": "string"],
            "detail": ["type": "string"],
            "source": ["type": "string", "description": "slack, slack-todo, gmail, calendar, linear, pagerduty, signoz, github or any label"],
            "url": ["type": "string"],
            "priority": ["type": "string", "enum": ["urgent", "high", "medium", "low"]],
            "dueAt": ["type": "string", "description": "ISO 8601 with offset. A date-only value means 18:00 local time."]
        ],
        "required": ["id", "title", "source"]
    ]

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "pending_sync",
            "description": "Publish tasks to PendingBar. mode=snapshot resolves this origin's open tasks that are missing from the list, but only for sources named in checkedSources (omit it to resolve across all sources). mode=merge only adds and updates. Ids in resolved are resolved in either mode. Tasks the user marked done stay done.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "origin": ["type": "string", "description": "Who is syncing, for example daily-sweep. 'manual' is reserved."],
                    "mode": ["type": "string", "enum": ["snapshot", "merge"]],
                    "checkedSources": ["type": "array", "items": ["type": "string"]],
                    "tasks": ["type": "array", "items": taskSchema],
                    "resolved": ["type": "array", "items": ["type": "string"], "description": "Ids verified as resolved at their source. They are resolved even when their source is not in checkedSources, in either mode."]
                ],
                "required": ["origin"]
            ]
        ],
        [
            "name": "pending_list",
            "description": "List tasks, ordered by priority then due date.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "includeCompleted": ["type": "boolean"],
                    "source": ["type": "string"]
                ]
            ]
        ],
        [
            "name": "pending_add",
            "description": "Add one task by hand. It never gets resolved by a sync.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "detail": ["type": "string"],
                    "source": ["type": "string"],
                    "url": ["type": "string"],
                    "priority": ["type": "string", "enum": ["urgent", "high", "medium", "low"]],
                    "dueAt": ["type": "string", "description": "ISO 8601, a date, or a relative value such as 2h or 3d"],
                    "id": ["type": "string"]
                ],
                "required": ["title"]
            ]
        ],
        [
            "name": "pending_complete",
            "description": "Mark a task as done.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ]
        ],
        [
            "name": "pending_snooze",
            "description": "Hide a task and silence its reminders until a time.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "until": ["type": "string", "description": "ISO 8601 or relative such as 1h, 30m, 2d"]
                ],
                "required": ["id", "until"]
            ]
        ]
    ]
}

public enum MCPToolError: Error, LocalizedError {
    case missing(String)
    case notFound(String)
    case badDate(String)

    public var errorDescription: String? {
        switch self {
        case let .missing(field): "Missing argument '\(field)'."
        case let .notFound(id): "No task with id '\(id)'."
        case let .badDate(raw): "Could not read the date '\(raw)'."
        }
    }
}

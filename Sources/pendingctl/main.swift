import Foundation
import PendingKit

let usage = """
pendingctl - task store for PendingBar

USAGE
  pendingctl mcp                        run the MCP server on stdio
  pendingctl sync [FILE|-]              apply a sync payload (JSON) from a file or stdin
  pendingctl list [--all] [--json]      list open tasks (--all includes completed)
  pendingctl add TITLE [--due WHEN] [--priority P] [--url URL] [--source S] [--detail D]
  pendingctl done ID                    mark a task done
  pendingctl reopen ID                  reopen a task
  pendingctl snooze ID WHEN             snooze until WHEN (ISO 8601, a date, or 1h / 30m / 2d)
  pendingctl path                       print the store location

Store: $PENDINGBAR_HOME or ~/Library/Application Support/PendingBar
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func printJSON<Value: Encodable>(_ value: Value) throws {
    let data = try DateParsing.makeEncoder().encode(value)
    print(String(decoding: data, as: UTF8.self))
}

let store = TaskStore()
var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "help" : arguments.removeFirst()
let now = Date()

do {
    switch command {
    case "mcp":
        let handler = MCPHandler(store: store)
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = handler.handle(line: line) {
                FileHandle.standardOutput.write(Data((response + "\n").utf8))
            }
        }

    case "sync":
        let path = arguments.first ?? "-"
        let data: Data
        if path == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            data = try Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        let payload = try DateParsing.makeDecoder().decode(SyncPayload.self, from: data)
        let result = try store.sync(payload, now: now)
        try printJSON(result)

    case "list":
        let document = try store.read()
        let includeAll = arguments.contains("--all")
        let tasks = TaskSorting.sorted(document.tasks, by: .priority).filter { includeAll || $0.isOpen }
        if arguments.contains("--json") {
            try printJSON(tasks)
        } else if tasks.isEmpty {
            print("No tasks.")
        } else {
            for task in tasks {
                let due = task.dueAt.map { DateParsing.iso($0) } ?? "-"
                let state = task.isOpen ? (task.isSnoozed(at: now) ? "snoozed" : "open") : "done"
                print("[\(task.priority.rawValue)] \(task.title)  (\(task.source), due \(due), \(state))  id=\(task.id)")
            }
        }

    case "add":
        guard let title = arguments.first, !title.hasPrefix("--") else { fail("add needs a TITLE\n\n" + usage) }
        let due = option("--due", in: arguments).map { raw -> Date in
            guard let date = DateParsing.parse(raw, now: now) else { fail("Could not read --due '\(raw)'") }
            return date
        }
        let priority = option("--priority", in: arguments).map { raw -> TaskPriority in
            guard let value = TaskPriority(loose: raw) else { fail("Unknown --priority '\(raw)'") }
            return value
        } ?? .medium
        let task = try store.mutate(now: now) { document in
            TaskMutation.addManual(
                title: title,
                detail: option("--detail", in: arguments),
                source: option("--source", in: arguments) ?? "manual",
                url: option("--url", in: arguments).flatMap(URL.init(string:)),
                priority: priority,
                dueAt: due,
                in: &document.tasks,
                now: now
            )
        }
        try printJSON(task)

    case "done", "reopen":
        guard let id = arguments.first else { fail("\(command) needs an ID") }
        let found = try store.mutate(now: now) { document in
            if command == "done" {
                return TaskMutation.complete(id, in: &document.tasks, now: now)
            }
            return TaskMutation.reopen(id, in: &document.tasks, now: now)
        }
        guard found else { fail("No task with id '\(id)'") }
        print("\(command): \(id)")

    case "snooze":
        guard arguments.count >= 2 else { fail("snooze needs ID and WHEN") }
        guard let until = DateParsing.parse(arguments[1], now: now) else { fail("Could not read '\(arguments[1])'") }
        let found = try store.mutate(now: now) { document in
            TaskMutation.snooze(arguments[0], until: until, in: &document.tasks, now: now)
        }
        guard found else { fail("No task with id '\(arguments[0])'") }
        print("snoozed until \(DateParsing.iso(until)): \(arguments[0])")

    case "path":
        print(store.fileURL.path)

    default:
        print(usage)
    }
} catch {
    fail("error: \(error.localizedDescription)")
}

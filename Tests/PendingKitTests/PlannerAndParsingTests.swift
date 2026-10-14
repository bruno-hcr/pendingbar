import Foundation
@testable import PendingKit
import XCTest

final class ReminderPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    func testPlansOnlyFutureFireTimesInOrder() {
        let task = TaskItem(id: "a", title: "a", source: "x", dueAt: now.addingTimeInterval(90 * 60), firstSeenAt: now)

        let plans = ReminderPlanner.plan(tasks: [task], offsets: ReminderOffset.presets, now: now)

        XCTAssertEqual(plans.map(\.offset.minutes), [60, 20, 10, 5])
        XCTAssertEqual(plans.first?.fireAt, now.addingTimeInterval(30 * 60))
    }

    func testSkipsCompletedSnoozedAndUndatedTasks() {
        let due = now.addingTimeInterval(3 * 86400)
        let done = TaskItem(id: "done", title: "", source: "x", dueAt: due, firstSeenAt: now, completedAt: now, completionReason: .user)
        let undated = TaskItem(id: "undated", title: "", source: "x", firstSeenAt: now)
        let snoozed = TaskItem(id: "snoozed", title: "", source: "x", dueAt: due, firstSeenAt: now, snoozedUntil: due.addingTimeInterval(-30 * 60))

        let plans = ReminderPlanner.plan(tasks: [done, undated, snoozed], offsets: ReminderOffset.presets, now: now)

        XCTAssertEqual(plans.map(\.offset.minutes), [20, 10, 5])
        XCTAssertTrue(plans.allSatisfy { $0.taskID == "snoozed" })
    }

    func testRespectsTheSystemLimit() {
        let tasks = (0..<30).map { index in
            TaskItem(id: "t\(index)", title: "", source: "x", dueAt: now.addingTimeInterval(Double(3 + index) * 86400), firstSeenAt: now)
        }

        let plans = ReminderPlanner.plan(tasks: tasks, offsets: ReminderOffset.presets, now: now, limit: 60)

        XCTAssertEqual(plans.count, 60)
        XCTAssertEqual(plans, plans.sorted { $0.fireAt < $1.fireAt })
    }

    func testAtDueOffsetFiresAtTheDueTime() {
        let due = now.addingTimeInterval(600)
        let task = TaskItem(id: "a", title: "", source: "x", dueAt: due, firstSeenAt: now)

        let plans = ReminderPlanner.plan(tasks: [task], offsets: [.atDue, ReminderOffset(minutes: 5)], now: now)

        XCTAssertEqual(plans.map(\.fireAt), [due.addingTimeInterval(-300), due])
    }
}

final class DateParsingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()

    func testParsesISOWithOffsetAndFraction() {
        XCTAssertEqual(DateParsing.parse("2026-10-15T18:00:00-03:00")?.timeIntervalSince1970, 1_792_098_000)
        XCTAssertEqual(DateParsing.parse("2026-10-15T21:00:00.000Z")?.timeIntervalSince1970, 1_792_098_000)
    }

    func testDateOnlyMeansSixPMLocal() {
        let date = DateParsing.parse("2026-10-15", calendar: calendar)

        XCTAssertEqual(date?.timeIntervalSince1970, 1_792_098_000)
    }

    func testRelativeValues() {
        let now = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(DateParsing.parse("30m", now: now)?.timeIntervalSince1970, 2800)
        XCTAssertEqual(DateParsing.parse("2h", now: now)?.timeIntervalSince1970, 8200)
        XCTAssertEqual(DateParsing.parse("1d", now: now)?.timeIntervalSince1970, 87400)
        XCTAssertNil(DateParsing.parse("soon", now: now))
    }

    func testPriorityAcceptsLinearNumbersAndNames() {
        XCTAssertEqual(TaskPriority(loose: "1"), .urgent)
        XCTAssertEqual(TaskPriority(loose: "Critical"), .urgent)
        XCTAssertEqual(TaskPriority(loose: "warning"), .medium)
        XCTAssertEqual(TaskPriority(loose: "0"), .low)
        XCTAssertNil(TaskPriority(loose: "whenever"))
    }
}

final class SortingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private var tasks: [TaskItem] {
        [
            TaskItem(id: "low-soon", title: "b", source: "slack", priority: .low, dueAt: now.addingTimeInterval(60), firstSeenAt: now),
            TaskItem(id: "urgent-none", title: "a", source: "linear", priority: .urgent, firstSeenAt: now),
            TaskItem(id: "high-overdue", title: "c", source: "gmail", priority: .high, dueAt: now.addingTimeInterval(-60), firstSeenAt: now)
        ]
    }

    func testPriorityOrder() {
        XCTAssertEqual(TaskSorting.sorted(tasks, by: .priority).map(\.id), ["urgent-none", "high-overdue", "low-soon"])
    }

    func testDueOrderPutsUndatedLast() {
        XCTAssertEqual(TaskSorting.sorted(tasks, by: .dueDate).map(\.id), ["high-overdue", "low-soon", "urgent-none"])
    }

    func testSourceSections() {
        let sections = TaskSorting.sections(tasks, by: .source, now: now)

        XCTAssertEqual(sections.map(\.title), ["Email", "Linear", "Slack"])
    }

    func testDueSections() {
        let sections = TaskSorting.sections(tasks, by: .dueDate, now: now)

        XCTAssertEqual(sections.first?.title, "Overdue")
        XCTAssertEqual(sections.last?.title, "No due date")
    }
}

final class MCPHandlerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("pendingbar-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func call(_ handler: MCPHandler, _ json: String) throws -> [String: Any] {
        let line = try XCTUnwrap(handler.handle(line: json))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func testInitializeEchoesProtocolVersionAndNotificationsGetNoReply() throws {
        let handler = MCPHandler(store: TaskStore(directory: directory))

        let response = try call(handler, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNil(handler.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testListsFiveTools() throws {
        let handler = MCPHandler(store: TaskStore(directory: directory))

        let response = try call(handler, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)

        let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }.sorted(), ["pending_add", "pending_complete", "pending_list", "pending_snooze", "pending_sync"])
    }

    func testSyncThroughToolsCallWritesTheStore() throws {
        let store = TaskStore(directory: directory)
        let handler = MCPHandler(store: store)
        let request = """
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pending_sync","arguments":{"origin":"daily-sweep","mode":"snapshot","checkedSources":["linear"],"tasks":[{"id":"linear:ENG-123","title":"Finish ENG-123","source":"linear","priority":"high","dueAt":"2026-10-15"}]}}}
        """

        let response = try call(handler, request)

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let document = try store.read()
        XCTAssertEqual(document.tasks.map(\.id), ["linear:ENG-123"])
        XCTAssertEqual(document.lastSync["daily-sweep"]?.result.added, 1)
    }

    func testToolErrorsAreReportedInTheResult() throws {
        let handler = MCPHandler(store: TaskStore(directory: directory))

        let response = try call(handler, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"pending_complete","arguments":{"id":"nope"}}}"#)

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testUnknownMethodIsAJSONRPCError() throws {
        let handler = MCPHandler(store: TaskStore(directory: directory))

        let response = try call(handler, #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#)

        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32601)
    }
}

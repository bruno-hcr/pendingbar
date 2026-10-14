import Foundation
@testable import PendingKit
import XCTest

final class SyncEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func incoming(_ id: String, source: String = "linear", title: String? = nil, due: Date? = nil) -> IncomingTask {
        IncomingTask(id: id, title: title ?? id, source: source, priority: .high, dueAt: due)
    }

    func testFirstSyncAddsEveryTask() throws {
        let payload = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("a"), incoming("b")])

        let (tasks, result) = try SyncEngine.apply(payload, to: [], now: now)

        XCTAssertEqual(tasks.map(\.id), ["a", "b"])
        XCTAssertEqual(result.added, 2)
        XCTAssertTrue(tasks.allSatisfy { $0.origin == "daily-sweep" && $0.firstSeenAt == now })
    }

    func testSnapshotResolvesMissingTasksOfTheSameOriginOnly() throws {
        let manual = TaskItem(id: "manual:1", title: "mine", source: "manual", firstSeenAt: now)
        let other = TaskItem(id: "x", title: "other origin", source: "linear", origin: "other", firstSeenAt: now)
        let first = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("a"), incoming("b")])
        let (afterFirst, _) = try SyncEngine.apply(first, to: [manual, other], now: now)

        let second = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("a")])
        let later = now.addingTimeInterval(3600)
        let (afterSecond, result) = try SyncEngine.apply(second, to: afterFirst, now: later)

        let byID = Dictionary(uniqueKeysWithValues: afterSecond.map { ($0.id, $0) })
        XCTAssertEqual(result.resolved, 1)
        XCTAssertEqual(byID["b"]?.completionReason, .resolvedUpstream)
        XCTAssertEqual(byID["b"]?.completedAt, later)
        XCTAssertNil(byID["a"]?.completedAt)
        XCTAssertNil(byID["manual:1"]?.completedAt)
        XCTAssertNil(byID["x"]?.completedAt)
    }

    func testSnapshotNeverResolvesTasksOfAnUncheckedSource() throws {
        let first = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("slack:1", source: "slack-todo"), incoming("linear:1")])
        let (afterFirst, _) = try SyncEngine.apply(first, to: [], now: now)

        let second = SyncPayload(origin: "daily-sweep", mode: .snapshot, checkedSources: ["linear"], tasks: [])
        let (afterSecond, result) = try SyncEngine.apply(second, to: afterFirst, now: now)

        let byID = Dictionary(uniqueKeysWithValues: afterSecond.map { ($0.id, $0) })
        XCTAssertEqual(result.resolved, 1)
        XCTAssertNil(byID["slack:1"]?.completedAt)
        XCTAssertNotNil(byID["linear:1"]?.completedAt)
    }

    func testMergeModeNeverResolves() throws {
        let first = SyncPayload(origin: "daily-sweep", mode: .merge, tasks: [incoming("a")])
        let (afterFirst, _) = try SyncEngine.apply(first, to: [], now: now)

        let second = SyncPayload(origin: "daily-sweep", mode: .merge, tasks: [])
        let (afterSecond, result) = try SyncEngine.apply(second, to: afterFirst, now: now)

        XCTAssertEqual(result.resolved, 0)
        XCTAssertTrue(afterSecond.allSatisfy(\.isOpen))
    }

    func testTaskTheUserMarkedDoneStaysDone() throws {
        let first = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("a")])
        var (tasks, _) = try SyncEngine.apply(first, to: [], now: now)
        XCTAssertTrue(TaskMutation.complete("a", in: &tasks, now: now))

        let again = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("a", title: "renamed")])
        let (afterAgain, result) = try SyncEngine.apply(again, to: tasks, now: now)

        XCTAssertEqual(result.keptDoneByUser, 1)
        XCTAssertEqual(afterAgain.first?.completionReason, .user)
        XCTAssertEqual(afterAgain.first?.title, "a")
    }

    func testTaskResolvedUpstreamReopensWhenItComesBack() throws {
        let first = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("a")])
        let (afterFirst, _) = try SyncEngine.apply(first, to: [], now: now)
        let empty = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [])
        let (resolved, _) = try SyncEngine.apply(empty, to: afterFirst, now: now)
        XCTAssertNotNil(resolved.first?.completedAt)

        let back = SyncPayload(origin: "daily-sweep", mode: .snapshot, tasks: [incoming("a")])
        let (reopened, result) = try SyncEngine.apply(back, to: resolved, now: now.addingTimeInterval(60))

        XCTAssertEqual(result.reopened, 1)
        XCTAssertNil(reopened.first?.completedAt)
        XCTAssertEqual(reopened.first?.firstSeenAt, now)
    }

    func testUpdateKeepsFirstSeenAndCountsChanges() throws {
        let first = SyncPayload(origin: "daily-sweep", mode: .merge, tasks: [incoming("a")])
        let (afterFirst, _) = try SyncEngine.apply(first, to: [], now: now)
        let due = now.addingTimeInterval(7200)

        let second = SyncPayload(origin: "daily-sweep", mode: .merge, tasks: [incoming("a", due: due), incoming("a", due: due)])
        let (afterSecond, result) = try SyncEngine.apply(second, to: afterFirst, now: now.addingTimeInterval(10))

        XCTAssertEqual(afterSecond.count, 1)
        XCTAssertEqual(afterSecond.first?.dueAt, due)
        XCTAssertEqual(afterSecond.first?.firstSeenAt, now)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.unchanged, 1)
    }

    func testManualOriginIsRejected() {
        let payload = SyncPayload(origin: "manual", tasks: [incoming("a")])

        XCTAssertThrowsError(try SyncEngine.apply(payload, to: [], now: now))
    }

    func testPruneDropsOldCompletedTasksOnly() {
        let old = TaskItem(id: "old", title: "old", source: "x", firstSeenAt: now, completedAt: now.addingTimeInterval(-15 * 86400), completionReason: .user)
        let recent = TaskItem(id: "recent", title: "recent", source: "x", firstSeenAt: now, completedAt: now.addingTimeInterval(-86400), completionReason: .user)
        let open = TaskItem(id: "open", title: "open", source: "x", firstSeenAt: now.addingTimeInterval(-90 * 86400))

        let kept = SyncEngine.prune([old, recent, open], now: now)

        XCTAssertEqual(kept.map(\.id), ["recent", "open"])
    }
}

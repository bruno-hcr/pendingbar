import AppKit
import Combine
import Foundation
import PendingKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var lastSync: [String: SyncStamp] = [:]
    @Published private(set) var errorMessage: String?
    @Published private(set) var now = Date()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    let store: TaskStore
    let preferences: Preferences
    let scheduler: NotificationScheduler

    private var watcher: DirectoryWatcher?
    private var ticker: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var lastRescheduleAt = Date.distantPast

    init() {
        store = TaskStore()
        preferences = Preferences()
        scheduler = NotificationScheduler()
    }

    func start() {
        scheduler.onAction = { [weak self] taskID, action in
            self?.handleNotification(taskID: taskID, action: action)
        }
        scheduler.configure()
        reload()
        watcher = DirectoryWatcher(url: store.directory) { [weak self] in
            self?.reload()
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        preferences.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.now = Date()
                self?.reschedule()
            }
            .store(in: &cancellables)
    }

    var visibleTasks: [TaskItem] {
        tasks.filter { task in
            guard task.isOpen else {
                guard preferences.showCompleted, let completedAt = task.completedAt else { return false }
                return now.timeIntervalSince(completedAt) < 86400
            }
            return preferences.showSnoozed || !task.isSnoozed(at: now)
        }
    }

    var openTasks: [TaskItem] {
        tasks.filter { $0.isOpen && !$0.isSnoozed(at: now) }
    }

    var overdueCount: Int {
        openTasks.filter { $0.isOverdue(at: now) }.count
    }

    var dueTodayCount: Int {
        openTasks.filter { DueBucket.of($0, now: now) == .today }.count
    }

    var badgeCount: Int {
        overdueCount + dueTodayCount
    }

    var sources: [String] {
        Array(Set(openTasks.map { $0.source.lowercased() })).sorted()
    }

    var latestSync: (origin: String, stamp: SyncStamp)? {
        lastSync.max { $0.value.at < $1.value.at }.map { ($0.key, $0.value) }
    }

    func reload() {
        do {
            let document = try store.read()
            tasks = document.tasks
            lastSync = document.lastSync
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        now = Date()
        reschedule()
    }

    func reschedule() {
        lastRescheduleAt = Date()
        scheduler.reschedule(tasks: tasks, offsets: preferences.offsets, now: lastRescheduleAt)
    }

    func complete(_ task: TaskItem) {
        mutate { TaskMutation.complete(task.id, in: &$0, now: Date()) }
    }

    func reopen(_ task: TaskItem) {
        mutate { TaskMutation.reopen(task.id, in: &$0, now: Date()) }
    }

    func snooze(_ task: TaskItem, until: Date?) {
        mutate { TaskMutation.snooze(task.id, until: until, in: &$0, now: Date()) }
    }

    func delete(_ task: TaskItem) {
        mutate { TaskMutation.delete(task.id, in: &$0) }
    }

    func add(title: String, priority: TaskPriority, dueAt: Date?, url: URL?) {
        mutate { tasks in
            TaskMutation.addManual(title: title, url: url, priority: priority, dueAt: dueAt, in: &tasks, now: Date())
            return true
        }
    }

    func open(_ task: TaskItem) {
        guard let url = task.url else { return }
        NSWorkspace.shared.open(url)
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = DateParsing.makeDecoder()
            let payload: SyncPayload
            if let full = try? decoder.decode(SyncPayload.self, from: data) {
                payload = full
            } else {
                let items = try decoder.decode([IncomingTask].self, from: data)
                payload = SyncPayload(origin: "import", mode: .merge, tasks: items)
            }
            _ = try store.sync(payload)
            reload()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(store.directory)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func tick() {
        now = Date()
        if now.timeIntervalSince(lastRescheduleAt) > 30 * 60 {
            reschedule()
        }
    }

    private func mutate(_ body: (inout [TaskItem]) -> Bool) {
        do {
            try store.mutate { document in
                _ = body(&document.tasks)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleNotification(taskID: String, action: NotificationAction) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        switch action {
        case .done:
            complete(task)
        case .snoozeHour:
            snooze(task, until: Date().addingTimeInterval(3600))
        case .open:
            open(task)
        }
    }
}

final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    private var pending: DispatchWorkItem?

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem {
                MainActor.assumeIsolated { onChange() }
            }
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

import Foundation
import PendingKit

@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var sortOrder: TaskSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    @Published var enabledOffsetMinutes: Set<Int> {
        didSet { defaults.set(Array(enabledOffsetMinutes).sorted(), forKey: Keys.offsets) }
    }

    @Published var notifyAtDue: Bool {
        didSet { defaults.set(notifyAtDue, forKey: Keys.notifyAtDue) }
    }

    @Published var showSnoozed: Bool {
        didSet { defaults.set(showSnoozed, forKey: Keys.showSnoozed) }
    }

    @Published var showCompleted: Bool {
        didSet { defaults.set(showCompleted, forKey: Keys.showCompleted) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sortOrder = defaults.string(forKey: Keys.sortOrder).flatMap(TaskSortOrder.init(rawValue:)) ?? .priority
        if let stored = defaults.array(forKey: Keys.offsets) as? [Int] {
            enabledOffsetMinutes = Set(stored)
        } else {
            enabledOffsetMinutes = Set(ReminderOffset.presets.map(\.minutes))
        }
        notifyAtDue = defaults.object(forKey: Keys.notifyAtDue) as? Bool ?? true
        showSnoozed = defaults.bool(forKey: Keys.showSnoozed)
        showCompleted = defaults.bool(forKey: Keys.showCompleted)
    }

    var offsets: [ReminderOffset] {
        var result = ReminderOffset.presets.filter { enabledOffsetMinutes.contains($0.minutes) }
        if notifyAtDue {
            result.append(.atDue)
        }
        return result
    }

    func isEnabled(_ offset: ReminderOffset) -> Bool {
        enabledOffsetMinutes.contains(offset.minutes)
    }

    func setEnabled(_ offset: ReminderOffset, _ enabled: Bool) {
        if enabled {
            enabledOffsetMinutes.insert(offset.minutes)
        } else {
            enabledOffsetMinutes.remove(offset.minutes)
        }
    }

    private enum Keys {
        static let sortOrder = "sortOrder"
        static let offsets = "reminderOffsetMinutes"
        static let notifyAtDue = "notifyAtDue"
        static let showSnoozed = "showSnoozed"
        static let showCompleted = "showCompleted"
    }
}

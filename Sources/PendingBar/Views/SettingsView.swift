import AppKit
import PendingKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    static let windowID = "settings"

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var scheduler: NotificationScheduler

    var body: some View {
        Form {
            Section("Reminders") {
                ForEach(ReminderOffset.presets) { offset in
                    Toggle(offset.label, isOn: Binding(
                        get: { preferences.isEnabled(offset) },
                        set: { preferences.setEnabled(offset, $0) }
                    ))
                }
                Toggle("At due time", isOn: $preferences.notifyAtDue)
                LabeledContent("Status") {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Send a test notification") { scheduler.sendTest() }
                    if scheduler.authorization == .denied {
                        Button("Open Notification Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                Text("Only tasks with a due date get reminders. A date without a time means 18:00.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("List") {
                Picker("Sort by", selection: $preferences.sortOrder) {
                    ForEach(TaskSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                Toggle("Show snoozed tasks", isOn: $preferences.showSnoozed)
                Toggle("Show tasks done in the last 24h", isOn: $preferences.showCompleted)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section("Integration") {
                LabeledContent("Store") {
                    Text(model.store.fileURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("MCP server") {
                    Text("claude mcp add --scope user pendingbar -- \(pendingctlPath) mcp")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("CLI") {
                    Text("pendingctl sync payload.json")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                ForEach(model.lastSync.sorted(by: { $0.value.at > $1.value.at }), id: \.key) { origin, stamp in
                    LabeledContent("Last sync: \(origin)") {
                        Text("\(stamp.at.formatted(date: .abbreviated, time: .shortened)) · +\(stamp.result.added) ~\(stamp.result.updated) -\(stamp.result.resolved)")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Open data folder") { model.openDataFolder() }
                    Button("Import JSON…") { model.importJSON() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task { await scheduler.refreshAuthorization() }
    }

    private var pendingctlPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/pendingctl").path
    }

    private var statusText: String {
        let permission: String
        switch scheduler.authorization {
        case .authorized, .provisional, .ephemeral:
            permission = "Allowed"
        case .denied:
            permission = "Blocked in System Settings"
        case .notDetermined:
            permission = "Not asked yet"
        @unknown default:
            permission = "Unknown"
        }
        var text = "\(permission) · \(scheduler.scheduledCount) scheduled"
        if let next = scheduler.nextFireAt {
            text += " · next \(next.formatted(date: .abbreviated, time: .shortened))"
        }
        return text
    }
}

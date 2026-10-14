import PendingKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.openWindow) private var openWindow

    @State private var sourceFilter: String?
    @State private var query = ""
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isAdding {
                AddTaskForm(isPresented: $isAdding)
                Divider()
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.08))
            }
            content
            Divider()
            footer
        }
        .frame(width: 400, height: 560)
    }

    private var filteredTasks: [TaskItem] {
        model.visibleTasks.filter { task in
            if let sourceFilter, task.source.lowercased() != sourceFilter {
                return false
            }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return true }
            return task.title.localizedCaseInsensitiveContains(trimmed)
                || (task.detail ?? "").localizedCaseInsensitiveContains(trimmed)
                || task.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pending")
                    .font(.system(size: 15, weight: .semibold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                sortMenu
                filterMenu
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let open = model.openTasks.count
        var parts = ["\(open) open"]
        if model.overdueCount > 0 {
            parts.append("\(model.overdueCount) overdue")
        }
        if model.dueTodayCount > 0 {
            parts.append("\(model.dueTodayCount) today")
        }
        return parts.joined(separator: " · ")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $preferences.sortOrder) {
                ForEach(TaskSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(preferences.sortOrder.label, systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var filterMenu: some View {
        Menu {
            Button("All apps") { sourceFilter = nil }
            Divider()
            ForEach(model.sources, id: \.self) { source in
                let count = model.openTasks.filter { $0.source.lowercased() == source }.count
                Button("\(SourceCatalog.displayName(for: source)) (\(count))") { sourceFilter = source }
            }
        } label: {
            Label(sourceFilter.map(SourceCatalog.displayName(for:)) ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        let sections = TaskSorting.sections(filteredTasks.filter(\.isOpen), by: preferences.sortOrder, now: model.now)
        let completed = filteredTasks.filter { !$0.isOpen }
        if sections.isEmpty && completed.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text(model.tasks.isEmpty ? "No tasks yet" : "Nothing pending")
                    .font(.headline)
                Text(model.tasks.isEmpty ? "Add one below, or sync from your agent." : "Everything here is done or snoozed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                TaskListBody(sections: sections, completed: completed)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isAdding.toggle() }
            } label: {
                Label("Add", systemImage: isAdding ? "minus" : "plus")
            }
            .buttonStyle(.borderless)

            Text(syncText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: SettingsView.windowID)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Menu {
                Button("Import JSON…") { model.importJSON() }
                Button("Open data folder") { model.openDataFolder() }
                Button("Reload") { model.reload() }
                Divider()
                Toggle("Show snoozed", isOn: $preferences.showSnoozed)
                Toggle("Show done (24h)", isOn: $preferences.showCompleted)
                Divider()
                Button("Quit PendingBar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var syncText: String {
        guard let latest = model.latestSync else { return "Never synced" }
        let result = latest.stamp.result
        let time = latest.stamp.at.formatted(date: .omitted, time: .shortened)
        var text = "Synced \(time) · \(latest.origin)"
        if result.added + result.resolved > 0 {
            text += " · +\(result.added) / -\(result.resolved)"
        }
        return text
    }
}

struct TaskListBody: View {
    let sections: [TaskSection]
    let completed: [TaskItem]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.tasks) { task in
                        TaskRow(task: task)
                        Divider().padding(.leading, 26)
                    }
                } header: {
                    SectionHeader(title: section.title, count: section.tasks.count)
                }
            }
            if !completed.isEmpty {
                Section {
                    ForEach(completed) { task in
                        TaskRow(task: task)
                        Divider().padding(.leading, 26)
                    }
                } header: {
                    SectionHeader(title: "Done in the last 24h", count: completed.count)
                }
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

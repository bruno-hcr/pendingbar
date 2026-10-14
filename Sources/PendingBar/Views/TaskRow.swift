import AppKit
import PendingKit
import SwiftUI

struct TaskRow: View {
    let task: TaskItem

    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(task.priority.color.opacity(task.isOpen ? 1 : 0.35))
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isOpen ? .primary : .secondary)
                    .strikethrough(!task.isOpen)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                metadata
                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            if isHovering {
                actions
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.open(task) }
        .contextMenu { contextMenu }
        .help(task.url?.absoluteString ?? task.id)
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: SourceCatalog.symbol(for: task.source))
                Text(SourceCatalog.displayName(for: task.source))
            }
            .foregroundStyle(.secondary)

            if let dueAt = task.dueAt, task.isOpen {
                Text(DueText.describe(dueAt, now: model.now))
                    .foregroundStyle(DueText.color(dueAt, now: model.now))
            }

            let days = Int(model.now.timeIntervalSince(task.firstSeenAt) / 86400)
            if task.isOpen, days >= 3 {
                Text("\(days)d on list")
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
            }

            if task.isSnoozed(at: model.now), let until = task.snoozedUntil {
                Label(until.formatted(date: .abbreviated, time: .shortened), systemImage: "moon.zzz")
                    .foregroundStyle(.secondary)
            }

            if task.completionReason == .resolvedUpstream {
                Text("resolved upstream")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if task.isOpen {
                Button {
                    model.complete(task)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .help("Mark done")

                Menu {
                    snoozeItems
                } label: {
                    Image(systemName: "clock")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Snooze")
            } else {
                Button {
                    model.reopen(task)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .help("Reopen")
            }

            if task.url != nil {
                Button {
                    model.open(task)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 14))
    }

    @ViewBuilder
    private var snoozeItems: some View {
        ForEach(SnoozeChoice.allCases) { choice in
            Button(choice.label) {
                model.snooze(task, until: choice.date(from: Date()))
            }
        }
        if task.snoozedUntil != nil {
            Divider()
            Button("Clear snooze") { model.snooze(task, until: nil) }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if task.isOpen {
            Button("Mark done") { model.complete(task) }
            Menu("Snooze") { snoozeItems }
        } else {
            Button("Reopen") { model.reopen(task) }
        }
        if let url = task.url {
            Button("Open link") { model.open(task) }
            Button("Copy link") { copy(url.absoluteString) }
        }
        Button("Copy id") { copy(task.id) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(task) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

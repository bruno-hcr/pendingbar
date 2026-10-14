import PendingKit
import SwiftUI

struct AddTaskForm: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var model: AppModel
    @FocusState private var titleFocused: Bool

    @State private var title = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasDue = false
    @State private var dueAt = AddTaskForm.defaultDue()
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What needs doing?", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(add)

            Picker("Priority", selection: $priority) {
                ForEach(TaskPriority.allCases, id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Toggle("Due", isOn: $hasDue)
                    .toggleStyle(.checkbox)
                if hasDue {
                    DatePicker("", selection: $dueAt)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                Spacer()
            }

            TextField("Link (optional)", text: $link)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .onAppear { titleFocused = true }
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let url = URL(string: link.trimmingCharacters(in: .whitespaces)).flatMap { $0.scheme == nil ? nil : $0 }
        model.add(title: trimmed, priority: priority, dueAt: hasDue ? dueAt : nil, url: url)
        isPresented = false
    }

    private static func defaultDue() -> Date {
        let calendar = Calendar.current
        let inAnHour = Date().addingTimeInterval(3600)
        let minute = calendar.component(.minute, from: inAnHour)
        return calendar.date(byAdding: .minute, value: (60 - minute) % 60, to: inAnHour) ?? inAnHour
    }
}

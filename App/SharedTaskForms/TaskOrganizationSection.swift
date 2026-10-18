import SwiftUI
import TskCore

struct TaskOrganizationSection: View {
    @Binding var draft: TaskDraft
    @Binding var tagInput: String
    @Binding var isChoosingPriority: Bool
    let tagError: String?
    let focus: FocusState<TaskEditorField?>.Binding
    let addTag: () -> Void

    var body: some View {
        Section("Organization") {
            LabeledContent("Project") {
                TextField("None", text: $draft.project)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("task-project")
                    .focused(focus, equals: .project)
            }
            Button { isChoosingPriority = true } label: {
                HStack { Text("Priority"); Spacer(); Text(priorityTitle) }
            }
            .accessibilityLabel("Priority").accessibilityValue(priorityTitle)
            .accessibilityIdentifier("task-priority")
            .popover(isPresented: $isChoosingPriority) {
                VStack(alignment: .leading) {
                    Button("None") { choosePriority("") }
                    Button("High") { choosePriority("H") }
                    Button("Medium") { choosePriority("M") }
                    Button("Low") { choosePriority("L") }
                    if !["", "H", "M", "L"].contains(draft.priority) {
                        Button("Unsupported: \(draft.priority)") { choosePriority(draft.priority) }
                    }
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }
        }
        Section("Tags") {
            ForEach(draft.tags.map { UTF8String($0) }) { identity in
                let tag = identity.rawValue
                HStack {
                    Text(tag)
                    Spacer()
                    Button("Remove \(tag)", systemImage: "minus.circle", role: .destructive) {
                        draft.removeTag(tag)
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("remove-tag-\(tag)")
                }
            }
            HStack {
                TextField("Add tag", text: $tagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .accessibilityIdentifier("task-tag-input")
                    .focused(focus, equals: .tag)
                Button("Add", action: addTag)
                    .buttonStyle(.borderless)
                    .disabled(tagInput.isEmpty)
                    .accessibilityIdentifier("add-tag")
            }
            if let tagError {
                Text(tagError).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("tag-error")
            }
        }
    }

    private var priorityTitle: String {
        switch draft.priority {
        case "": "None"
        case "H": "High"
        case "M": "Medium"
        case "L": "Low"
        default: "Unsupported: \(draft.priority)"
        }
    }

    private func choosePriority(_ value: String) {
        guard isChoosingPriority else { return }
        draft.priority = value
        isChoosingPriority = false
    }
}

struct TaskOrganizationSummary: View {
    let task: TaskRecord

    var body: some View {
        Section("Organization") {
            LabeledContent("Project", value: task.project.isEmpty ? "None" : task.project)
            LabeledContent("Priority", value: priorityName)
            if !task.tags.isEmpty { LabeledContent("Tags", value: task.tags.joined(separator: ", ")) }
        }
    }

    private var priorityName: String {
        switch task.priority {
        case "": "None"
        case "H": "High"
        case "M": "Medium"
        case "L": "Low"
        default: task.priority
        }
    }
}

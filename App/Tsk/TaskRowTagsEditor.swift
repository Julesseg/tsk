import SwiftUI
import TskCore

struct TaskRowTagsEditor: View {
    @Binding var draft: TaskRowDraft
    let availableTags: [String]
    @Binding var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Add tag", text: $draft.tagInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(addTag)
                .accessibilityIdentifier("row-tag-input")
            Button("Add tag", systemImage: "plus", action: addTag)
                .disabled(draft.tagInput.isEmpty)
                .accessibilityIdentifier("row-add-tag")
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("row-tag-error")
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ForEach(choices) { identity in
                let tag = identity.rawValue
                let selected = draft.taskDraft.tags.contains { UTF8String($0) == identity }
                Button {
                    if selected {
                        draft.taskDraft.removeTag(tag)
                    } else {
                        do { try draft.taskDraft.addTag(tag); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tag).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(tag)
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityHint(selected ? "Remove tag" : "Add tag")
                .accessibilityIdentifier("row-tag-" + tag)
            }
        }
        .onChange(of: UTF8String(draft.tagInput)) { _, _ in error = nil }
    }

    private var choices: [UTF8String] {
        Set((availableTags + draft.taskDraft.tags).map { UTF8String($0) }).sorted()
    }

    private func addTag() {
        do { try draft.addTagInput(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

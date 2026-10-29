import SwiftUI
import TskCore

struct TaskRowTagsEditor: View {
    @Binding var draft: TaskRowDraft
    let availableTags: [String]
    @Binding var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find or create a tag", text: $draft.tagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .accessibilityIdentifier("row-tag-input")
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.45), in: .capsule)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("row-tag-error")
                    .accessibilityAddTraits(.updatesFrequently)
            }
            TaskRowTagLayout(spacing: 7) {
                ForEach(choices) { identity in
                    let tag = identity.rawValue
                    let selected = draft.taskDraft.tags.contains { UTF8String($0) == identity }
                    Button {
                        if selected {
                            draft.taskDraft.removeTag(tag)
                            draft.tagInput = ""
                            error = nil
                        } else {
                            do {
                                try draft.taskDraft.addTag(tag)
                                draft.tagInput = ""
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if selected { Image(systemName: "checkmark").fontWeight(.semibold) }
                            Text(tag)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 11)
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(selected ? Color.blue : Color.primary)
                        .background(selected ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.09), in: .capsule)
                        .contentShape(Capsule())
                    }
                    .accessibilityLabel(tag)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityHint(selected ? "Remove tag" : "Add tag")
                    .accessibilityIdentifier("row-tag-" + tag)
                }
                if !draft.tagInput.isEmpty && !allChoices.contains(UTF8String(draft.tagInput)) {
                    Button("Create “\(draft.tagInput)”", systemImage: "plus", action: addTag)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("row-add-tag")
                }
            }
        }
        .onChange(of: UTF8String(draft.tagInput)) { _, _ in error = nil }
    }

    private var allChoices: [UTF8String] {
        Set((availableTags + draft.taskDraft.tags).map { UTF8String($0) }).sorted()
    }

    private var choices: [UTF8String] {
        allChoices.filter { draft.tagInput.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(draft.tagInput) }
    }

    private func addTag() {
        do { try draft.addTagInput(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

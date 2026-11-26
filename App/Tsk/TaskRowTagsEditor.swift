import SwiftUI
import TskCore

struct TaskRowTagsEditor: View {
    @Binding var draft: TaskRowDraft
    let availableTags: [String]
    @Binding var error: String?
    @State private var removedTags: Set<UTF8String> = []

    var body: some View {
        let active = draft.taskDraft.tags.map { UTF8String($0) }
        let inactive = Set(availableTags.map { UTF8String($0) }).union(removedTags).subtracting(active)
        let query = draft.tagInput
        VStack(alignment: .leading, spacing: 12) {
            if !active.isEmpty {
                TaskRowTagLayout(spacing: 7) {
                    ForEach(active) { tag in
                        TaskPickerTag(name: tag.rawValue, active: true) {
                            removedTags.insert(tag)
                            draft.taskDraft.removeTag(tag.rawValue)
                            draft.tagInput = ""
                            error = nil
                        }
                        .accessibilityIdentifier("row-tag-" + tag.rawValue)
                    }
                }
            }
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
                ForEach(inactive.sorted().filter { query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query) }) { tag in
                    TaskPickerTag(name: tag.rawValue, active: false) {
                        draft.tagInput = tag.rawValue
                        addTag()
                    }
                    .accessibilityIdentifier("row-tag-" + tag.rawValue)
                }
                if !query.isEmpty && !active.contains(UTF8String(query)) && !inactive.contains(UTF8String(query)) {
                    Button("Create “\(query)”", systemImage: "plus", action: addTag)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("row-add-tag")
                }
            }
        }
        .onChange(of: UTF8String(draft.tagInput)) { _, _ in error = nil }
    }

    private func addTag() {
        do { try draft.addTagInput(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct TaskPickerTag: View {
    let name: String
    let active: Bool
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if active { Image(systemName: "checkmark").fontWeight(.semibold) }
                Text(name)
                if let detail { Text(detail).font(.caption) }
            }
            .font(.subheadline)
            .padding(.horizontal, 11)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(active ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.09), in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel(name)
        .accessibilityValue(detail ?? (active ? "Selected" : "Not selected"))
        .accessibilityHint(active ? "Remove tag" : "Add tag")
    }
}

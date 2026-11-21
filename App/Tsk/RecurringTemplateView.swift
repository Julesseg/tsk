import SwiftUI
import TskCore

struct RecurringTemplateView: View {
    let store: TaskStore
    let templateID: UUID
    @State private var editor: Editor?
    @State private var successorID: UUID?

    var body: some View {
        Group {
            if let template = store.allTasks.first(where: { $0.id == templateID }) {
                Form {
                    Text(template.description)
                        .accessibilityIdentifier("series-template-description")
                    TaskRecurrenceSection(task: template, store: store, transition: { editor = .transition })
                    if let successorID {
                        Section("Separate successor created") {
                            NavigationLink("View new recurring template") {
                                RecurringTemplateView(store: store, templateID: successorID)
                            }
                            .accessibilityIdentifier("view-transition-successor")
                        }
                    }
                    if let error = store.error {
                        Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("task-action-error") }
                    }
                }
                .accessibilityIdentifier("series-template-form")
                .toolbar {
                    if template.status == "recurring" {
                        Button("Edit series metadata") { editor = .metadata }
                            .disabled(store.isSaving)
                            .accessibilityIdentifier("edit-series-metadata")
                    }
                }
                .sheet(item: $editor) { editor in
                    switch editor {
                    case .metadata:
                        TaskSeriesMetadataEditor(store: store, template: template)
                    case .transition:
                        TaskSeriesTransitionEditor(store: store, template: template, onSave: { successorID = $0.id })
                    }
                }
            } else {
                ContentUnavailableView("Template unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.inline)
    }

    private enum Editor: String, Identifiable {
        case metadata, transition

        var id: Self { self }
    }
}

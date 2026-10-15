import SwiftUI
import TskCore

private enum SeriesOffsetMode: String, CaseIterable { case preserve = "Keep existing offsets", clear = "Clear", set = "Choose first date" }

struct TaskSeriesTransitionEditor: View {
    let store: TaskStore
    let template: TaskRecord
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var effective: Date
    @State private var firstDue: Date
    @State private var rule: String
    @State private var timeZone = TimeZone.current.identifier
    @State private var plannedMode = SeriesOffsetMode.preserve
    @State private var waitMode = SeriesOffsetMode.preserve
    @State private var planned: Date
    @State private var wait: Date
    @State private var hasUntil: Bool
    @State private var until: Date
    @State private var preview: TaskSeriesTransitionPreview?
    @State private var error: String?
    @State private var isPreviewing = false
    @FocusState private var typing: String?

    init(store: TaskStore, template: TaskRecord, onSave: @escaping (TaskRecord) -> Void) {
        self.store = store; self.template = template; self.onSave = onSave
        let first = store.allTasks.filter { UUID(uuidString: $0.attributes["parent"] ?? "") == template.id && $0.status == "pending" }.compactMap(\.deadline).filter { $0 >= store.currentDate }.min() ?? store.currentDate.addingTimeInterval(86400)
        _effective = State(initialValue: store.currentDate)
        _firstDue = State(initialValue: first)
        _rule = State(initialValue: template.attributes["recur"] ?? "weekly")
        _planned = State(initialValue: first.addingTimeInterval((template.plannedDate?.timeIntervalSince1970 ?? first.timeIntervalSince1970) - (template.deadline?.timeIntervalSince1970 ?? first.timeIntervalSince1970)))
        _wait = State(initialValue: first.addingTimeInterval((template.waitUntil?.timeIntervalSince1970 ?? first.timeIntervalSince1970) - (template.deadline?.timeIntervalSince1970 ?? first.timeIntervalSince1970)))
        _hasUntil = State(initialValue: template.attributes["until"] != nil)
        _until = State(initialValue: template.attributes["until"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)) ?? first.addingTimeInterval(31536000))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Separate successor template") {
                    Text("This retires the old template now and creates a separate recurring template. Completed history and excluded overdue work keep the old template. Existing affected future tasks keep their IDs and move to the new template.")
                    Text("No new occurrences are generated here. The designated Taskwarrior client creates later occurrences after synchronization and a report.").font(.footnote).foregroundStyle(.secondary)
                }
                Group {
                    Section("Effective date and first due") {
                        DatePicker("Apply from", selection: $effective, displayedComponents: [.date, .hourAndMinute]).accessibilityIdentifier("transition-effective")
                        Text("Only unfinished tasks due on or after this time and still in the future are moved. Preview shows the exact cutoff. The old generator must already cover earlier positions.").font(.footnote)
                        DatePicker("New first due", selection: $firstDue, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, generatorZone).accessibilityIdentifier("transition-first-due")
                    }
                    Section("Generator time zone and cadence") {
                        TextField("Generator time zone", text: $timeZone).textInputAutocapitalization(.never).autocorrectionDisabled().focused($typing, equals: "zone").accessibilityIdentifier("transition-zone")
                        Menu("Common time zones") {
                            ForEach(Array(Set([TimeZone.current.identifier, "UTC", "Europe/Paris", "America/New_York", "Asia/Tokyo"])).sorted(), id: \.self) { zone in Button(zone) { timeZone = zone } }
                        }
                        Text("Use the same time zone as the designated Taskwarrior generator, for both old and new series. Calendar stepping depends on it; changing the generator's zone later changes later dates.").font(.footnote)
                        Menu("Choose a frequency") {
                            ForEach(["daily", "weekdays", "weekly", "monthly", "quarterly", "yearly", "biannual"], id: \.self) { value in Button(value.capitalized) { rule = value } }
                        }
                        TextField("Taskwarrior recurrence", text: $rule).textInputAutocapitalization(.never).autocorrectionDisabled().focused($typing, equals: "rule").accessibilityIdentifier("transition-rule")
                        Text("Named calendar periods and fixed durations differ. For example, biannual and 2years differ at leap day; P2M resets the clock to midnight after its first date.").font(.footnote)
                    }
                    Section("Planned and waiting dates") {
                        Picker("Planned day", selection: $plannedMode) { ForEach(SeriesOffsetMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("transition-planned-mode")
                        if plannedMode == .set { DatePicker("First planned date", selection: $planned, displayedComponents: [.date, .hourAndMinute]).environment(\.timeZone, generatorZone).accessibilityIdentifier("transition-planned-date") }
                        Picker("Wait until", selection: $waitMode) { ForEach(SeriesOffsetMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("transition-wait-mode")
                        if waitMode == .set { DatePicker("First wait date", selection: $wait, displayedComponents: [.date, .hourAndMinute]).environment(\.timeZone, generatorZone).accessibilityIdentifier("transition-wait-date") }
                        Text("Keep preserves each task's existing offset from its due date. Choosing a first date applies that new offset to all moved occurrences and the new template.").font(.footnote)
                    }
                    Section("Until") {
                        Toggle("Set Until", isOn: $hasUntil).accessibilityIdentifier("transition-has-until")
                        if hasUntil { DatePicker("Until date", selection: $until, displayedComponents: [.date, .hourAndMinute]).environment(\.timeZone, generatorZone).accessibilityIdentifier("transition-until") }
                        Text("Until must cover every retained future occurrence. Taskwarrior 3.5 can still generate its first occurrence beyond Until and retire an ended template while waiting tasks remain. Retained tasks stay available.").font(.footnote)
                    }
                }
                .disabled(preview != nil || isPreviewing || store.isSaving)
                if let preview { review(preview) }
            }
            .accessibilityIdentifier("series-transition-form")
            .navigationTitle("Change cadence or schedule")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if let error { Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("transition-error") }
            }
            .safeAreaInset(edge: .bottom) {
                if typing != nil { HStack { Spacer(); Button("Done") { typing = nil }.accessibilityIdentifier("dismiss-transition-keyboard") }.padding().background(.regularMaterial) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    if let preview { Button("Retire and create") { save(preview) }.disabled(store.isSaving).accessibilityIdentifier("save-series-transition") }
                    else { Button("Preview", action: buildPreview).disabled(store.isSaving || isPreviewing).accessibilityIdentifier("preview-series-transition") }
                }
            }
            .interactiveDismissDisabled(store.isSaving)
            .focusedSceneValue(\.taskEditor, store.isSaving || isPreviewing ? nil : TaskEditorActions(save: { if let preview { save(preview) } else { buildPreview() } }))
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    private var generatorZone: TimeZone { TimeZone(identifier: timeZone) ?? .current }

    @ViewBuilder private func review(_ preview: TaskSeriesTransitionPreview) -> some View {
        Section("Review explicit transition") {
            Text("\(preview.affected.count) existing future \(preview.affected.count == 1 ? "task moves" : "tasks move")").accessibilityIdentifier("transition-preview-count")
            Text("Effective cutoff: \(date(preview.effectiveDate, zone: generatorZone))")
            Text("Retire old template now").font(.headline)
            Text(preview.original.description)
            Text(preview.original.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
            Text("Completed history and excluded unfinished tasks stay linked here.").font(.footnote)
            Text("Create separate template").font(.headline)
            Text(preview.successor.id.uuidString).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("transition-successor-id")
            Text("\(preview.successor.attributes["recur"] ?? "") · \(preview.generatorTimeZone)")
            Text("First due: \(date(preview.successor.deadline!, zone: generatorZone))")
            Text("Next unfilled generator position: \(date(preview.nextGeneratorDue, zone: generatorZone))").font(.footnote)
            ForEach(Array(zip(preview.affected, preview.moved)), id: \.0.id) { old, moved in
                VStack(alignment: .leading, spacing: 5) {
                    Text(old.description)
                    Text(old.id.uuidString).font(.caption.monospaced())
                    Text("Due: \(date(old.deadline!, zone: generatorZone)) → \(date(moved.deadline!, zone: generatorZone))")
                    Text("Planned: \(optionalDate(old.plannedDate)) → \(optionalDate(moved.plannedDate))").font(.caption)
                    Text("Wait: \(optionalDate(old.waitUntil)) → \(optionalDate(moved.waitUntil))").font(.caption)
                }
                .accessibilityIdentifier("transition-preview-\(old.id.uuidString)")
            }
            Button("Back to editing") { self.preview = nil; error = nil }.accessibilityIdentifier("edit-transition-preview")
            if error != nil { Button("Preview again", action: buildPreview).accessibilityIdentifier("refresh-transition-preview") }
        }
    }

    private func date(_ value: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium; formatter.timeStyle = .short; formatter.timeZone = zone
        return formatter.string(from: value)
    }
    private func optionalDate(_ value: Date?) -> String { value.map { date($0, zone: generatorZone) } ?? "None" }
    private func offset(_ mode: SeriesOffsetMode, value: Date) -> TaskSeriesOffsetChange {
        switch mode {
        case .preserve: .preserve
        case .clear: .clear
        case .set: .set(Int64((value.timeIntervalSince1970 - firstDue.timeIntervalSince1970).rounded(.towardZero)))
        }
    }
    private func buildPreview() {
        guard !isPreviewing else { return }
        typing = nil; isPreviewing = true
        let draft = TaskSeriesTransitionDraft(effectiveDate: effective, firstDue: firstDue, recurrence: rule, generatorTimeZone: timeZone, planned: offset(plannedMode, value: planned), wait: offset(waitMode, value: wait), until: hasUntil ? until : nil)
        Task {
            defer { isPreviewing = false }
            do { preview = try await store.manager.previewSeriesTransition(id: template.id, draft: draft); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save(_ preview: TaskSeriesTransitionPreview) {
        Task {
            if let saved = await store.perform({ try await $0.applySeriesTransition(preview) }) { onSave(saved); dismiss() }
            else { error = store.error }
        }
    }
}

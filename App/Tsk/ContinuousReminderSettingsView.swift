import SwiftUI
import TskCore

struct ContinuousReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let controller: ContinuousReminderController
    @State private var lists: [ReminderList] = []
    @State private var projects: [String: String] = [:]
    @State private var error: String?
    @State private var fixtureReport: String?
    @State private var loading = false
    @State private var fixtureChanged = false
    @FocusState private var editingProject: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("One designated device") {
                    Text("Keep continuous import enabled on only one device. It is disabled by default elsewhere. Sources are removed only after each valid task is saved locally.")
                    Text("An interrupted move, failed removal, or explicit retry can leave a saved task and its source together. Retrying can create duplicates; no per-reminder tracking is retained.").font(.footnote)
                    Text(controller.status?.active == true ? "Enabled on this device" : "Disabled on this device").accessibilityIdentifier("continuous-reminders-status")
                    if controller.status?.configuredOnAnotherDevice == true { Text("These settings designate another device. Moving is disabled here. Disable the other device before enabling this one.") }
                    if controller.status?.active == true && controller.status?.paused == true {
                        Text("Automatic scans are held while another window moves reminders, or after an interrupted or failed move. If no move is running, review the source before explicitly retrying.").accessibilityIdentifier("continuous-reminders-paused")
                    }
                    Button("Allow Reminders access / Refresh lists") { Task { await loadLists() } }.accessibilityIdentifier("reminders-access")
                }
                ReminderListMappingSection(lists: lists, projects: $projects, focused: $editingProject)
                Section {
                    Button("Enable and move on this device") { Task { await enable() } }
                        .disabled(projects.isEmpty).accessibilityIdentifier("continuous-reminders-enable")
                    Button("Disable on this device") { Task { await disable() } }
                        .accessibilityIdentifier("continuous-reminders-disable")
                    Button("Scan / Retry moving now") { Task { editingProject = false; await controller.scan(retry: true) } }
                        .disabled(controller.status?.active != true).accessibilityIdentifier("continuous-reminders-retry")
                    Text("Windows share one import attempt. Pauses survive reopening the app; Scan / Retry or re-enabling explicitly resumes moving. Selected-list changes and app opening can trigger scans. iOS background opportunities are best effort; reminders may wait until you reopen tsk.").font(.footnote)
                    if let schedulingError = SynchronizationAppDelegate.schedulingError { Text(schedulingError).font(.footnote) }
                }
                if let result = controller.result {
                    Section("Current attempt") {
                        Text("Saved \(result.imported.count); removed \(result.removedCount); skipped \(result.skipped.count); failed \(result.failures.count).")
                            .accessibilityIdentifier("continuous-reminders-result")
                        ForEach(result.imported) { Text($0.description) }
                        ForEach((result.skipped + result.failures).indices, id: \.self) { index in
                            let item = (result.skipped + result.failures)[index]
                            VStack(alignment: .leading) { Text(item.title).font(.headline); Text(item.reason ?? "Not moved").font(.footnote) }
                        }
                    }
                }
                if let fixtureReport {
                    ScrollView { Text(fixtureReport).font(.caption.monospaced()) }.frame(height: 160)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Real EventKit move evidence")
                        .accessibilityValue(fixtureReport).accessibilityIdentifier("continuous-reminders-fixture-report")
                }
                #if DEBUG
                if ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" {
                Button("Add isolated capture") { Task { await changeFixture(edit: false) } }.accessibilityIdentifier("continuous-reminders-add-fixture")
                Button("Read isolated move fixture") { Task { await verifyFixture() } }.accessibilityIdentifier("continuous-reminders-verify-fixture")
                }
                #endif
            }
            .accessibilityIdentifier("continuous-reminders-form")
            .disabled(loading || controller.isRunning)
            .overlay { if loading || controller.isRunning { ProgressView(controller.isRunning ? "Waiting for other windows or moving reminders…" : "Loading Reminders…").accessibilityIdentifier("continuous-reminders-progress").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if controller.isRunning { Button("Stop moving") { controller.cancel() }.padding().background(.bar).disabled(false).accessibilityIdentifier("continuous-reminders-stop") }
                    if let message = error ?? controller.error { Text(message).font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("continuous-reminders-error") }
                    #if DEBUG
                    if controller.fixtureWaiting {
                        Button("Edit fixture source before removal") { Task { await changeFixture(edit: true) } }.disabled(false).accessibilityIdentifier("continuous-reminders-edit-fixture")
                        if fixtureChanged { Text("Fixture source updated").accessibilityIdentifier("continuous-reminders-fixture-changed") }
                        Button("Resume fixture removal") { controller.resumeFixture() }.disabled(false).padding().background(.bar).accessibilityIdentifier("continuous-reminders-resume-fixture")
                    }
                    #endif
                }
            }
            .safeAreaInset(edge: .bottom) {
                if editingProject { HStack { Spacer(); Button("Done") { editingProject = false }.accessibilityIdentifier("dismiss-reminders-keyboard") }.padding().background(.bar) }
            }
            .navigationTitle("Move from Reminders")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(controller.isRunning) } }
        }
        .task {
            await controller.load()
            projects = (controller.status?.configuration?.mappings ?? []).reduce(into: [:]) { $0[$1.listID] = $1.project }
            do { lists = try await controller.source.lists() } catch { self.error = error.localizedDescription }
        }
        .modifier(TaskWorkspacePanel(store: controller.store))
    }

    private func loadLists() async {
        loading = true; editingProject = false
        defer { loading = false }
        do {
            try await controller.source.requestAccess()
            #if DEBUG
            if fixtureReport == nil { fixtureReport = try await prepareReminderFixture(source: controller.source) }
            #endif
            lists = try await controller.source.lists(); error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func enable() async {
        loading = true; editingProject = false
        defer { loading = false }
        do {
            try await controller.enable(mappings: projects.map { ReminderListMapping(listID: $0.key, project: $0.value) }.sorted { $0.listID < $1.listID })
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func disable() async {
        do { try await controller.disable(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    #if DEBUG
    private func changeFixture(edit: Bool) async {
        do { try await changeContinuousReminderFixture(source: controller.source, edit: edit); fixtureChanged = edit; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func verifyFixture() async {
        do { fixtureReport = try await verifyContinuousReminderFixture(source: controller.source); error = nil }
        catch { self.error = error.localizedDescription }
    }
    #endif
}

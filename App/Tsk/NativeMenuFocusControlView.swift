#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import TskCore

enum NativeMenuFocusControlGate {
    enum Mode: String { case bare, hosted = "keyboard-host" }

    static func mode(_ environment: [String: String]) -> Mode? {
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              environment["TSK_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)) != nil,
              let token = environment["TSK_TEST_NATIVE_MENU_FOCUS_CONTROL"].flatMap(UUID.init(uuidString:)),
              let replica = environment["TSK_TEST_REPLICA_NAME"].flatMap(UUID.init(uuidString:)),
              token == replica else { return nil }
        return Mode(rawValue: environment["TSK_TEST_NATIVE_MENU_FOCUS_MODE"] ?? "bare")
    }
}

struct NativeMenuFocusControlView: View {
    @State private var title = "Prepare the release with the product team"
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("What needs to be done?", text: $title, axis: .vertical)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($titleFocused)
                .accessibilityIdentifier("task-description")
            NativeMenuFocusControlEditor(titleFocused: $titleFocused)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-menu-focus-control")
    }
}

private struct NativeMenuFocusControlEditor: View {
    @FocusState.Binding var titleFocused: Bool
    @FocusState private var focusedNote: UTF8String?
    @State private var note = ""

    var body: some View {
        NativeMenuFocusControlContent(titleFocused: $titleFocused, focusedNote: $focusedNote, note: $note)
    }
}

private struct NativeMenuFocusControlContent: View {
    @FocusState.Binding var titleFocused: Bool
    @FocusState.Binding var focusedNote: UTF8String?
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Notes", text: $note, axis: .vertical)
                .focused($focusedNote, equals: UTF8String("new"))
                .textFieldStyle(.plain)
                .font(.subheadline)
                .lineLimit(1...5)
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("row-note-input")
            NativeMenuFocusControlPill {
                let beforeTitle = titleFocused
                let beforeNote = focusedNote?.rawValue ?? "nil"
                titleFocused = false
                focusedNote = nil
                TaskMenuFocusDiagnostics.record("focus.request", details: [
                    "fixture": "minimal", "parameter": "project", "titleBefore": String(beforeTitle), "noteBefore": beforeNote,
                    "fixtureMode": NativeMenuFocusControlGate.mode(ProcessInfo.processInfo.environment)?.rawValue ?? "unavailable",
                    "titleRequested": "false", "noteRequested": "nil", "titleReadback": String(titleFocused),
                    "noteReadback": focusedNote?.rawValue ?? "nil", "readbackAdvisory": "true"
                ])
            }
            Button("Hide Keyboard") { titleFocused = false; focusedNote = nil }
                .accessibilityIdentifier("dismiss-row-keyboard")
        }
    }
}

private struct NativeMenuFocusControlPill: View {
    let unfocus: () -> Void
    @State private var project = UTF8String("Release")
    @State private var projectInput = "Release"
    @State private var parameter: TaskRowParameter?
    @Namespace private var presentationNamespace

    var body: some View {
        Menu {
            Picker("Project", selection: $project) {
                Text("No project").tag(UTF8String(""))
                Text("Release").tag(UTF8String("Release"))
            }
            Button("New project…", systemImage: "folder.badge.plus") {
                unfocus()
                projectInput = project.rawValue
                parameter = .project
            }
            .accessibilityIdentifier("row-new-project")
        } label: {
            TaskRowParameterLabel(parameter: .project, value: project.rawValue.isEmpty ? nil : project.rawValue)
                .background {
                    TaskMenuActivation(action: unfocus)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(TaskRowParameterButtonStyle())
        .matchedTransitionSource(id: TaskRowParameter.project.id, in: presentationNamespace)
        .popover(isPresented: Binding(
            get: { parameter == .project },
            set: { if !$0 && parameter == .project { parameter = nil } }
        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack {
                TextField("Project", text: $projectInput)
                    .accessibilityIdentifier("row-project-input")
                Button("Done") { project = UTF8String(projectInput); parameter = nil }
                    .accessibilityIdentifier("close-row-parameter")
            }
            .padding()
            .frame(width: 340)
            .navigationTransition(.zoom(sourceID: TaskRowParameter.project.id, in: presentationNamespace))
            .presentationCompactAdaptation(.popover)
        }
        .frame(minWidth: 44, minHeight: 44, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityLabel("Project")
        .accessibilityValue(project.rawValue.isEmpty ? "Not set" : project.rawValue)
        .accessibilityIdentifier("row-project")
    }
}
#endif

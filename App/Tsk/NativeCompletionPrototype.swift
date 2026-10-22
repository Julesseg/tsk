#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import TskCore

private actor PrototypeReplica: TaskReplica {
    func tasks() async throws -> [TaskRecord] { [] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { TaskRecord(id: id, attributes: attributes) }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { TaskRecord(id: id, attributes: [:]) }
}

struct NativeCompletionPrototype: View {
    @State private var rows = Self.fixture
    @State private var checked: UUID?
    @State private var faded = false
    @State private var phase = "Ready"
    @State private var variant = ProcessInfo.processInfo.environment["TSK_NATIVE_COMPLETION_VARIANT"] ?? "A"
    @State private var store = TaskStore(manager: TaskManager(replica: PrototypeReplica()), directory: FileManager.default.temporaryDirectory)
    private let target = Self.fixture[1].id
    private var name: String { variant == "A" ? "Stock List removal" : variant == "B" ? "Fade + List removal" : "Fade, immediate gap" }
    private static let fixture: [TaskRecord] = [
        TaskRecord(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!, attributes: ["description": "Send the revised proposal", "status": "pending", "project": "Studio"]),
        TaskRecord(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!, attributes: ["description": "Prepare the release with the product team and review accessibility findings", "status": "pending", "project": "Release", "due": String(Int(Date().timeIntervalSince1970))]),
        TaskRecord(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!, attributes: ["description": "Book a table for Friday", "status": "pending"]),
        TaskRecord(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!, attributes: ["description": "Review the final illustrations", "status": "pending", "project": "Studio"]),
        TaskRecord(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000005")!, attributes: ["description": "Pick up groceries", "status": "pending"])
    ]
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                NavigationStack {
                    List {
                        ForEach(rows) { task in
                            HStack(alignment: task.project.isEmpty && task.deadline == nil ? .center : .top, spacing: 4) {
                                Button { Task { await complete() } } label: {
                                    Image(systemName: checked == task.id ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(.secondary)
                                        .contentTransition(.symbolEffect(.replace, options: .speed(3)))
                                        .animation(.default, value: checked)
                                        .frame(minWidth: 44, minHeight: 44)
                                }.buttonStyle(.borderless)
                                TaskListLabel(task: task, store: store, isCompleted: checked == task.id)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .opacity(task.id == target && faded ? 0 : 1)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .environment(\.defaultMinListRowHeight, 0)
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .navigationTitle("Today")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Image(systemName: "gearshape") } }
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 8) {
                            Text("PROTOTYPE · \(variant) · \(name)").font(.caption.weight(.semibold))
                            Text(phase).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("A") { reset("A") }; Button("B") { reset("B") }; Button("C") { reset("C") }
                                Spacer()
                                Button("Replay") { reset(variant); Task { await complete() } }
                            }.buttonStyle(.bordered)
                        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).padding()
                    }
                }
            }
            Tab("Upcoming", systemImage: "calendar") { Text("Prototype") }
            Tab("Projects", systemImage: "folder") { Text("Prototype") }
            Tab("All", systemImage: "checklist") { Text("Prototype") }
        }
        .task {
            if ProcessInfo.processInfo.environment["TSK_NATIVE_COMPLETION_AUTOPLAY"] == "1" {
                try? await Task.sleep(for: .seconds(3))
                await complete()
            }
        }
    }
    private func reset(_ value: String) { variant = value; rows = Self.fixture; checked = nil; faded = false; phase = "Ready" }
    private func complete() async {
        guard checked == nil else { return }
        checked = target; phase = "Checked · one-second hold after tick settles"
        try? await Task.sleep(for: .milliseconds(1400))
        if variant != "A" {
            phase = "Native opacity · 200 ms"
            withAnimation(.easeOut(duration: 0.2)) { faded = true }
            try? await Task.sleep(for: .milliseconds(220))
        }
        phase = variant == "C" ? "Immediate gap closure" : "Native List removal · default animation"
        if variant == "C" {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { rows.removeAll { $0.id == target } }
        } else {
            withAnimation(.default) { rows.removeAll { $0.id == target } }
        }
        try? await Task.sleep(for: .milliseconds(500))
        phase = "Finished · \(rows.count) tasks remaining"
    }
}
#endif

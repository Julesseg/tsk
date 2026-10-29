import SwiftUI

@main
struct TaskOrganizationPrototypeApp: App {
    var body: some Scene {
        WindowGroup { TaskOrganizationPrototype() }
    }
}

struct TaskOrganizationPrototype: View {
    private let variant = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--variant=") }?.components(separatedBy: "=").last ?? "A"
    @State private var presented = false
    @State private var query = ""
    @State private var selected: Set<String> = ["review", "release"]
    @State private var tags = ["accessibility", "design", "follow-up", "meeting", "release", "review", "waiting", "writing"]

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { tasks }
            Tab("Upcoming", systemImage: "calendar") { Text("Upcoming") }
            Tab("Projects", systemImage: "folder") { Text("Projects") }
            Tab("All", systemImage: "checklist") { tasks }
        }
        .tint(.blue)
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            presented = true
        }
    }

    private var tasks: some View {
        NavigationStack {
            List {
                task("Send the agenda for tomorrow", expanded: false)
                    .opacity(0.35)
                task("Prepare the release with the product team", expanded: true)
                task("Review accessibility findings", expanded: false)
                    .opacity(0.35)
                task("Book the workshop space", expanded: false)
                    .opacity(0.35)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("New task", systemImage: "plus") { }
                }
            }
        }
    }

    private func task(_ title: String, expanded: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle").font(.title3).foregroundStyle(.blue.opacity(0.6))
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                if expanded {
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            Button("Release", systemImage: "folder") { }
                                .buttonStyle(.glass)
                            Button(action: { presented = true }) {
                                Label(selected.isEmpty ? "Tags" : selected.sorted().joined(separator: ", "), systemImage: "tag")
                            }
                            .buttonStyle(.glass)
                            .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                picker
                                    .frame(width: 320)
                                    .presentationCompactAdaptation(.popover)
                            }
                            Button("Medium", systemImage: "exclamationmark") { }
                                .buttonStyle(.glass)
                        }
                        .font(.caption)
                    }
                    .scrollIndicators(.hidden)
                    Button("Task information", systemImage: "info.circle") { }
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, expanded ? 10 : 2)
        .listRowSeparator(.hidden)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tags", systemImage: "tag").font(.headline)
                Spacer()
                Button("Done") { presented = false }
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find or create a tag", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(create)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.45), in: .capsule)
            ScrollView {
                Group {
                    switch variant {
                    case "B": chipChoices
                    case "C": groupedChoices
                    default: rowChoices
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: variant == "B" ? 178 : 260)
        }
        .padding(16)
    }

    private var filtered: [String] {
        tags.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }.sorted()
    }

    private var rowChoices: some View {
        VStack(spacing: 0) {
            ForEach(filtered, id: \.self) { tag in
                Button { toggle(tag) } label: {
                    HStack {
                        Text(tag).foregroundStyle(.primary)
                        Spacer()
                        if selected.contains(tag) { Image(systemName: "checkmark").fontWeight(.semibold) }
                    }
                    .frame(minHeight: 43)
                    .contentShape(Rectangle())
                }
                if tag != filtered.last { Divider() }
            }
            createChoice
        }
        .font(.subheadline)
        .buttonStyle(.plain)
    }

    private var chipChoices: some View {
        PrototypeTagFlow(spacing: 7) {
            ForEach(filtered, id: \.self) { tag in
                Button { toggle(tag) } label: {
                    HStack(spacing: 5) {
                        if selected.contains(tag) { Image(systemName: "checkmark").fontWeight(.semibold) }
                        Text(tag)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected.contains(tag) ? Color.blue : Color.primary)
                    .background(selected.contains(tag) ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.09), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            createChoice
        }
    }

    private var groupedChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !selected.isEmpty {
                Text("Selected").font(.caption).foregroundStyle(.secondary)
                PrototypeTagFlow(spacing: 6) {
                    ForEach(selected.sorted(), id: \.self) { tag in
                        Button { selected.remove(tag) } label: {
                            HStack(spacing: 7) {
                                Text(tag)
                                Image(systemName: "xmark").font(.caption2.weight(.semibold))
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.blue.opacity(0.1), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
                Divider()
            }
            Text("Available tags").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(filtered.filter { !selected.contains($0) }, id: \.self) { tag in
                    Button { selected.insert(tag) } label: {
                        HStack {
                            Text(tag).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus").font(.caption.weight(.medium))
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                createChoice
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder private var createChoice: some View {
        if !query.isEmpty && !tags.contains(query) {
            Button("Create “\(query)”", systemImage: "plus", action: create)
                .frame(minHeight: 44)
                .foregroundStyle(.blue)
        }
    }

    private func toggle(_ tag: String) {
        if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
    }

    private func create() {
        guard !query.isEmpty, !query.contains(where: \.isWhitespace) else { return }
        if !tags.contains(query) { tags.append(query) }
        selected.insert(query)
        query = ""
    }
}

struct PrototypeTagFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(width: proposal.width ?? 300, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = positions(width: bounds.width, subviews: subviews)
        for (index, point) in layout.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func positions(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (points, CGSize(width: width, height: y + rowHeight))
    }
}

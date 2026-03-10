import SwiftUI

/// Tag database table view — displays tags in a sortable table with type, scope, description.
struct TagTableView: View {
    @EnvironmentObject var projectManager: ProjectManager

    @State private var sortOrder: [KeyPathComparator<Tag>] = [
        .init(\.name, order: .forward)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tag")
                    .foregroundColor(.purple)
                Text("\(projectManager.selectedTagScope) Tags")
                    .font(.headline)
                Spacer()
                Text("\(projectManager.selectedTags.count) tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if projectManager.selectedTags.isEmpty {
                VStack {
                    Spacer()
                    Text("No tags in this scope")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                // Tag table
                Table(projectManager.selectedTags, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { tag in
                        Text(tag.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Type") { tag in
                        Text(tag.dataType.displayName)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(typeColor(tag.dataType).opacity(0.1))
                            .cornerRadius(3)
                    }
                    .width(min: 60, ideal: 90)

                    TableColumn("Scope") { tag in
                        Text(tag.scope.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Description") { tag in
                        Text(tag.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 200)

                    TableColumn("Value") { tag in
                        Text(tag.initialValue.isEmpty ? "—" : tag.initialValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 50, ideal: 80)

                    TableColumn("Access") { tag in
                        Text(tag.externalAccess.rawValue)
                            .font(.caption2)
                            .foregroundColor(.tertiaryLabel)
                    }
                    .width(min: 60, ideal: 80)
                }
                .onChange(of: sortOrder) { newOrder in
                    // Sort is handled by Table automatically for value-keyed columns
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func typeColor(_ type: DataType) -> Color {
        switch type {
        case .bool_: return .blue
        case .sint, .int_, .dint, .lint: return .green
        case .real: return .orange
        case .timer: return .purple
        case .counter: return .red
        case .stringType: return .teal
        case .array: return .brown
        case .udt: return .indigo
        }
    }
}

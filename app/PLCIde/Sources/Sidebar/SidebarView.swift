import SwiftUI

/// Project navigator sidebar — tree view of tasks, programs, routines, tags.
struct SidebarView: View {
    // Phase 1: populated from plc_core project data
    @State private var expandedSections: Set<String> = ["controller", "tasks", "tags"]

    var body: some View {
        List {
            // Controller section
            DisclosureGroup(isExpanded: binding(for: "controller")) {
                Label("1769-L33ER", systemImage: "cpu")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } label: {
                Label("Controller", systemImage: "server.rack")
                    .fontWeight(.semibold)
            }

            // Tasks / Programs / Routines
            DisclosureGroup(isExpanded: binding(for: "tasks")) {
                DisclosureGroup {
                    DisclosureGroup {
                        Label("MainRoutine", systemImage: "list.bullet.rectangle")
                    } label: {
                        Label("MainProgram", systemImage: "doc.text")
                    }
                } label: {
                    Label("MainTask (Continuous)", systemImage: "play.circle")
                }
            } label: {
                Label("Tasks", systemImage: "clock.arrow.circlepath")
                    .fontWeight(.semibold)
            }

            // Tags
            DisclosureGroup(isExpanded: binding(for: "tags")) {
                Label("Controller Tags", systemImage: "tag")
                Label("Program Tags", systemImage: "tag")
            } label: {
                Label("Tags", systemImage: "number")
                    .fontWeight(.semibold)
            }

            // I/O Configuration (future)
            DisclosureGroup {
                Text("Phase 4+")
                    .font(.caption)
                    .foregroundColor(.tertiaryLabel)
            } label: {
                Label("I/O Configuration", systemImage: "cable.connector.horizontal")
                    .fontWeight(.semibold)
            }
        }
        .listStyle(.sidebar)
    }

    private func binding(for section: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }
}

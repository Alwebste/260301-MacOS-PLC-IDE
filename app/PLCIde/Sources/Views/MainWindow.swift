import SwiftUI

/// Main application window layout.
///
/// ┌──────────┬─────────────────────────┬──────────┐
/// │ Sidebar  │  Rung Display / Tags    │Inspector │
/// │          │  (content area)         │          │
/// │ Project  │                         │ Tag Props│
/// │ Navigator│                         │ Summary  │
/// ├──────────┴─────────────────────────┴──────────┤
/// │              Output / Errors Panel             │
/// └────────────────────────────────────────────────┘
struct MainWindow: View {
    @EnvironmentObject var projectManager: ProjectManager

    @State private var showInspector: Bool = true

    var body: some View {
        if projectManager.hasProject {
            projectView
        } else {
            welcomeView
        }
    }

    // MARK: - Welcome Screen

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("PLC IDE")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Allen-Bradley ControlLogix / CompactLogix")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button("New Project") {
                    projectManager.createNewProject()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Open Project...") {
                    projectManager.openProject()
                }
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Project Editor

    private var projectView: some View {
        VSplitView {
            HSplitView {
                // Left sidebar: Project Navigator
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 400)

                // Center: Content area (rungs or tags depending on selection)
                contentView
                    .frame(minWidth: 400)

                // Right inspector: Properties
                if showInspector {
                    InspectorView()
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                }
            }

            // Bottom: Output panel
            OutputPanelView()
                .frame(minHeight: 100, idealHeight: 150, maxHeight: 300)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Project summary badge
                if let summary = projectManager.summary {
                    Text("\(summary.rungCount) rungs | \(summary.tagCount) tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    projectManager.runValidation()
                } label: {
                    Image(systemName: "checkmark.shield")
                }
                .help("Run Validation")

                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch projectManager.selection {
        case .controllerTags, .programTags:
            TagTableView()
        case .routine:
            RungListView()
        default:
            // Default: show rungs if a routine is selected, otherwise project overview
            if !projectManager.selectedRoutineRungs.isEmpty {
                RungListView()
            } else {
                projectOverview
            }
        }
    }

    private var projectOverview: some View {
        VStack(spacing: 16) {
            if let summary = projectManager.summary {
                GroupBox("Project Overview") {
                    VStack(alignment: .leading, spacing: 8) {
                        overviewRow("Name", summary.name)
                        overviewRow("Controller", "\(summary.controllerFamily) — \(summary.catalogNumber)")
                        overviewRow("Tasks", "\(summary.taskCount)")
                        overviewRow("Programs", "\(summary.programCount)")
                        overviewRow("Routines", "\(summary.routineCount)")
                        overviewRow("Rungs", "\(summary.rungCount)")
                        overviewRow("Tags", "\(summary.tagCount)")
                    }
                    .padding(8)
                }
                .frame(maxWidth: 400)

                Text("Select a routine in the sidebar to view its ladder logic.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func overviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .foregroundColor(.secondary)
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

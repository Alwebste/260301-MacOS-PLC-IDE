import SwiftUI

/// Main application window layout.
///
/// ┌──────────┬─────────────────────────┬──────────┐
/// │ Sidebar  │  Ladder Canvas / Tags   │Inspector │
/// │          │  (content area)         │  or      │
/// │ Project  │                         │ Palette  │
/// │ Navigator│                         │          │
/// ├──────────┴─────────────────────────┴──────────┤
/// │              Output / Errors Panel             │
/// └────────────────────────────────────────────────┘
struct MainWindow: View {
    @EnvironmentObject var projectManager: ProjectManager

    @State private var showInspector: Bool = true
    @State private var showPalette: Bool = false
    @State private var showSimulator: Bool = false
    @State private var selectedRungIndex: Int? = nil

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

                // Center: Content area
                if showSimulator {
                    SimulatorView()
                        .frame(minWidth: 500)
                } else {
                    contentView
                        .frame(minWidth: 400)
                }

                // Right panel: Inspector or Instruction Palette
                if showPalette {
                    InstructionPaletteView()
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                } else if showInspector {
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

                Divider()

                // View mode toggle
                Button {
                    showSimulator.toggle()
                } label: {
                    Image(systemName: showSimulator ? "play.circle.fill" : "play.circle")
                }
                .help(showSimulator ? "Exit Simulator" : "Open Simulator")

                Button {
                    showPalette.toggle()
                    if showPalette { showInspector = false }
                } label: {
                    Image(systemName: showPalette ? "square.grid.2x2.fill" : "square.grid.2x2")
                }
                .help("Toggle Instruction Palette")

                Button {
                    projectManager.runValidation()
                } label: {
                    Image(systemName: "checkmark.shield")
                }
                .help("Run Validation")

                Button {
                    showInspector.toggle()
                    if showInspector { showPalette = false }
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
            ladderView
        default:
            if !projectManager.selectedRoutineRungs.isEmpty {
                ladderView
            } else {
                projectOverview
            }
        }
    }

    /// The main ladder view — uses Core Graphics canvas for graphical rendering,
    /// with a text-based fallback toggle
    private var ladderView: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                if case .routine(let progName, let routName) = projectManager.selection {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(.orange)
                    Text("\(progName) / \(routName)")
                        .font(.headline)
                }
                Spacer()
                Text("\(projectManager.selectedRoutineRungs.count) rungs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Core Graphics canvas
            LadderCanvasView(
                rungs: projectManager.selectedRoutineRungs,
                energizedRungs: [],
                onRungClicked: { index in
                    selectedRungIndex = index
                },
                onInstructionClicked: { rungIndex, instructionId in
                    selectedRungIndex = rungIndex
                }
            )
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

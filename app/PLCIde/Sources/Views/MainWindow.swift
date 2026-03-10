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
    @EnvironmentObject var connectionManager: ConnectionManager

    @State private var showInspector: Bool = true
    @State private var showPalette: Bool = false
    @State private var showSimulator: Bool = false
    @State private var showOnline: Bool = false
    @State private var selectedRungIndex: Int? = nil

    var body: some View {
        Group {
            if projectManager.hasProject {
                projectView
            } else {
                welcomeView
            }
        }
        .sheet(isPresented: $projectManager.showImportPreview) {
            ImportPreviewSheet()
                .environmentObject(projectManager)
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

                Button("Open Project (.aip)") {
                    projectManager.openProject()
                }
                .controlSize(.large)

                Divider()
                    .frame(width: 200)

                Button("Import L5X...") {
                    projectManager.importL5X()
                }
                .controlSize(.regular)

                Button("Import L5K...") {
                    projectManager.importL5K()
                }
                .controlSize(.regular)
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
                if showOnline {
                    HSplitView {
                        contentView
                            .frame(minWidth: 300)
                        LiveTagWatchView()
                            .frame(minWidth: 250, idealWidth: 320, maxWidth: 500)
                    }
                    .frame(minWidth: 500)
                } else if showSimulator {
                    SimulatorView()
                        .frame(minWidth: 500)
                } else {
                    contentView
                        .frame(minWidth: 400)
                }

                // Right panel: Inspector, Palette, or Connection
                if showOnline && showInspector {
                    ConnectionPanelView()
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                } else if showPalette {
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
                // Connection status
                if showOnline {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(connectionManager.connectionState.isConnected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(connectionManager.connectionState.isConnected ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundColor(connectionManager.connectionState.isConnected ? .green : .secondary)
                    }
                }

                // Project summary badge
                if let summary = projectManager.summary {
                    Text("\(summary.rungCount) rungs | \(summary.tagCount) tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Online mode toggle
                Button {
                    showOnline.toggle()
                    if showOnline { showSimulator = false }
                } label: {
                    Image(systemName: showOnline ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right")
                }
                .help(showOnline ? "Go Offline" : "Go Online (Connect to PLC)")

                // Simulator toggle
                Button {
                    showSimulator.toggle()
                    if showSimulator { showOnline = false }
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

    /// The main ladder view — uses Core Graphics canvas for graphical rendering
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
                energizedRungs: liveEnergizedRungs,
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

                if project.importedFrom != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .foregroundColor(.blue)
                        Text("Imported from Studio 5000")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Select a routine in the sidebar to view its ladder logic.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Compute energized rungs from live tag data when online.
    private var liveEnergizedRungs: Set<UInt32> {
        guard showOnline, connectionManager.connectionState.isConnected, connectionManager.isPolling else {
            return []
        }
        // Build a lookup of live BOOL tag values
        let liveValues = Dictionary(
            connectionManager.liveTagValues.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        // Evaluate each rung's output coils
        var energized: Set<UInt32> = []
        for rung in projectManager.selectedRoutineRungs {
            if evaluateRungLive(rung.element, values: liveValues) {
                energized.insert(rung.number)
            }
        }
        return energized
    }

    /// Simple live rung evaluation based on tag values.
    private func evaluateRungLive(_ element: RungElement, values: [String: String]) -> Bool {
        switch element {
        case .instruction(let inst):
            switch inst.instructionType {
            case .xic:
                let tag = inst.operands.first?.displayString ?? ""
                return values[tag] == "1" || values[tag] == "TRUE"
            case .xio:
                let tag = inst.operands.first?.displayString ?? ""
                return values[tag] != "1" && values[tag] != "TRUE"
            case .ote, .otl, .otu:
                return true // output instructions pass through
            default:
                return true
            }
        case .series(let elements):
            var power = true
            for el in elements {
                power = power && evaluateRungLive(el, values: values)
            }
            return power
        case .parallel(let branches):
            return branches.contains { evaluateRungLive($0, values: values) }
        }
    }

    private var project: PlcProject {
        projectManager.project ?? PlcProject(
            formatVersion: 1, id: "", name: "", description: "",
            controller: Controller(name: "", family: .compactLogix, catalogNumber: "", firmwareVersion: "", description: ""),
            tasks: [], tagDatabase: TagDatabase(tags: []), importedFrom: nil
        )
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

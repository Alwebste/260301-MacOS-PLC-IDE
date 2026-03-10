import SwiftUI

/// Main application window layout.
///
/// ┌──────────┬─────────────────────────┬──────────┐
/// │ Sidebar  │     Ladder Canvas       │Inspector │
/// │          │  (AppKit/Core Graphics) │          │
/// │ Project  │                         │ Tag Props│
/// │ Navigator│                         │ Instr    │
/// │          │                         │ Details  │
/// │          │                         │          │
/// ├──────────┴─────────────────────────┴──────────┤
/// │              Output / Errors Panel             │
/// └────────────────────────────────────────────────┘
struct MainWindow: View {
    @EnvironmentObject var projectManager: ProjectManager

    @State private var sidebarWidth: CGFloat = 250
    @State private var inspectorWidth: CGFloat = 280
    @State private var outputHeight: CGFloat = 150
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

                Button("Import L5K/L5X...") {
                    projectManager.importL5K()
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
                    .frame(minWidth: 200, idealWidth: sidebarWidth, maxWidth: 400)

                // Center: Ladder Canvas (will be AppKit NSView in Phase 2)
                LadderCanvasPlaceholder()
                    .frame(minWidth: 400)

                // Right inspector: Properties
                if showInspector {
                    InspectorView()
                        .frame(minWidth: 220, idealWidth: inspectorWidth, maxWidth: 400)
                }
            }

            // Bottom: Output panel
            OutputPanelView()
                .frame(minHeight: 100, idealHeight: outputHeight, maxHeight: 300)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
    }
}

/// Placeholder for the ladder canvas — will be replaced with AppKit NSViewRepresentable.
struct LadderCanvasPlaceholder: View {
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            VStack(spacing: 16) {
                Image(systemName: "rectangle.split.3x3")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Ladder Editor Canvas")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Phase 2: AppKit + Core Graphics rendering")
                    .font(.caption)
                    .foregroundColor(.tertiaryLabel)
            }
        }
    }
}

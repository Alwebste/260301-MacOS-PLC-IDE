import SwiftUI
import Combine

/// Manages the current project state. Bridges between Swift UI and the Rust core engine.
///
/// In Phase 1+, this will call into plc_core via UniFFI to create/load/save projects.
/// For now, it uses placeholder logic to validate the app shell.
class ProjectManager: ObservableObject {
    @Published var projectName: String = ""
    @Published var hasProject: Bool = false
    @Published var projectJSON: String = ""

    // MARK: - File Operations (Phase 1: replace with UniFFI calls)

    func createNewProject() {
        // Phase 1: let project = plc_core.create_project(name, family)
        projectName = "Untitled Project"
        hasProject = true
        print("[ProjectManager] Created new project")
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "plcproj")!]
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadProject(from: url)
        }
    }

    func saveProject() {
        guard hasProject else { return }
        // Phase 1: let json = plc_core.save_project_to_json(project)
        print("[ProjectManager] Saved project: \(projectName)")
    }

    func importL5K() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5K")!]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            print("[ProjectManager] Import L5K from: \(url.path)")
            // Phase 3: call plc_parser via UniFFI
        }
    }

    func importL5X() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5X")!]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            print("[ProjectManager] Import L5X from: \(url.path)")
        }
    }

    func exportL5K() {
        print("[ProjectManager] Export L5K — Phase 3")
    }

    func exportL5X() {
        print("[ProjectManager] Export L5X — Phase 3")
    }

    // MARK: - Internal

    private func loadProject(from url: URL) {
        do {
            let json = try String(contentsOf: url, encoding: .utf8)
            // Phase 1: let project = plc_core.load_project_from_json(json)
            projectJSON = json
            projectName = url.deletingPathExtension().lastPathComponent
            hasProject = true
            print("[ProjectManager] Loaded project from: \(url.path)")
        } catch {
            print("[ProjectManager] Failed to load: \(error)")
        }
    }
}

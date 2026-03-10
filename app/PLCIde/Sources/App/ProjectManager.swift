import SwiftUI
import Combine

/// Selection state for the project navigator
enum SidebarSelection: Hashable {
    case controller
    case task(name: String)
    case program(name: String)
    case routine(programName: String, routineName: String)
    case controllerTags
    case programTags(programName: String)
}

/// Manages the current project state. Bridges between Swift UI and the Rust core engine.
///
/// Phase 1: loads .plcproj JSON files into Swift model types.
/// Phase 3+: calls plc_core/plc_parser via UniFFI for import/export.
class ProjectManager: ObservableObject {
    @Published var project: PlcProject?
    @Published var hasProject: Bool = false
    @Published var isDirty: Bool = false
    @Published var projectFileURL: URL?

    // Navigation / selection state
    @Published var selection: SidebarSelection? = nil
    @Published var selectedRoutineRungs: [Rung] = []
    @Published var selectedTags: [Tag] = []
    @Published var selectedTagScope: String = "Controller"

    // Validation
    @Published var validationIssues: [ValidationIssue] = []
    @Published var outputMessages: [String] = []

    // MARK: - Computed

    var projectName: String {
        project?.name ?? "No Project"
    }

    var summary: ProjectSummary? {
        project?.summary
    }

    // MARK: - File Operations

    func createNewProject() {
        let proj = DemoProject.create()
        loadProjectData(proj)
        outputMessages.append("[Project] Created new project: \(proj.name)")
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "plcproj")!]
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadProjectFile(from: url)
        }
    }

    func saveProject() {
        guard let project = project else { return }

        let url: URL
        if let existing = projectFileURL {
            url = existing
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "plcproj")!]
            panel.nameFieldStringValue = "\(project.name).plcproj"
            guard panel.runModal() == .OK, let saveURL = panel.url else { return }
            url = saveURL
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(project)
            try data.write(to: url)
            projectFileURL = url
            isDirty = false
            outputMessages.append("[Project] Saved to: \(url.path)")
        } catch {
            outputMessages.append("[Error] Failed to save: \(error.localizedDescription)")
        }
    }

    func importL5K() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5K")!]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.outputMessages.append("[Import] L5K import planned for Phase 3: \(url.lastPathComponent)")
        }
    }

    func importL5X() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5X")!]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.outputMessages.append("[Import] L5X import planned for Phase 3: \(url.lastPathComponent)")
        }
    }

    func exportL5K() {
        outputMessages.append("[Export] L5K export planned for Phase 3")
    }

    func exportL5X() {
        outputMessages.append("[Export] L5X export planned for Phase 3")
    }

    // MARK: - Navigation

    func selectRoutine(programName: String, routineName: String) {
        selection = .routine(programName: programName, routineName: routineName)
        if let routine = project?.findRoutine(programName: programName, routineName: routineName) {
            selectedRoutineRungs = routine.rungs
        } else {
            selectedRoutineRungs = []
        }
    }

    func selectControllerTags() {
        selection = .controllerTags
        selectedTags = project?.controllerTags ?? []
        selectedTagScope = "Controller"
    }

    func selectProgramTags(programName: String) {
        selection = .programTags(programName: programName)
        selectedTags = project?.programTags(for: programName) ?? []
        selectedTagScope = programName
    }

    // MARK: - Validation

    func runValidation() {
        guard let project = project else { return }

        var issues: [ValidationIssue] = []
        let tagNames = Set(project.tagDatabase.tags.map { $0.name })

        for task in project.tasks {
            for program in task.programs {
                for routine in program.routines {
                    for rung in routine.rungs {
                        validateElement(rung.element, tagNames: tagNames,
                                       programName: program.name,
                                       routineName: routine.name,
                                       rungNumber: rung.number,
                                       issues: &issues)
                    }
                }
            }
        }

        validationIssues = issues
        let errorCount = issues.filter { if case .error = $0.severity { return true }; return false }.count
        let warnCount = issues.filter { if case .warning = $0.severity { return true }; return false }.count
        outputMessages.append("[Validation] \(errorCount) error(s), \(warnCount) warning(s)")
    }

    // MARK: - Internal

    private func loadProjectFile(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let proj = try decoder.decode(PlcProject.self, from: data)
            loadProjectData(proj)
            projectFileURL = url
            outputMessages.append("[Project] Opened: \(url.lastPathComponent)")
        } catch {
            outputMessages.append("[Error] Failed to open: \(error.localizedDescription)")
        }
    }

    private func loadProjectData(_ proj: PlcProject) {
        project = proj
        hasProject = true
        isDirty = false
        validationIssues = []

        // Auto-select first routine if available
        if let firstTask = proj.tasks.first,
           let firstProgram = firstTask.programs.first,
           let firstRoutine = firstProgram.routines.first {
            selectRoutine(programName: firstProgram.name, routineName: firstRoutine.name)
        }

        runValidation()
    }

    private func validateElement(_ element: RungElement, tagNames: Set<String>,
                                  programName: String, routineName: String,
                                  rungNumber: UInt32, issues: inout [ValidationIssue]) {
        switch element {
        case .instruction(let inst):
            for operand in inst.operands {
                if case .tagRef(let name) = operand {
                    let baseName = name.split(separator: "[").first.map(String.init) ?? name
                    let baseName2 = baseName.split(separator: ".").first.map(String.init) ?? baseName
                    if !tagNames.contains(baseName2) {
                        issues.append(ValidationIssue(
                            severity: .error,
                            message: "Tag '\(name)' not found in tag database",
                            rungNumber: rungNumber,
                            routineName: routineName,
                            programName: programName
                        ))
                    }
                }
            }
        case .series(let elements):
            for el in elements {
                validateElement(el, tagNames: tagNames, programName: programName,
                              routineName: routineName, rungNumber: rungNumber, issues: &issues)
            }
        case .parallel(let branches):
            for branch in branches {
                validateElement(branch, tagNames: tagNames, programName: programName,
                              routineName: routineName, rungNumber: rungNumber, issues: &issues)
            }
        }
    }
}

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
/// Native format: .aip (Allen-Bradley IDE Project)
/// Import/Export: .L5K (ASCII) and .L5X (XML) for Studio 5000 interop.
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

    // Import state
    @Published var showImportPreview: Bool = false
    @Published var importPreview: ImportPreview?
    @Published var pendingImportContent: String?

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
        panel.allowedContentTypes = [
            .init(filenameExtension: "aip")!,
            .init(filenameExtension: "plcproj")!,
        ]
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
            panel.allowedContentTypes = [.init(filenameExtension: "aip")!]
            panel.nameFieldStringValue = "\(project.name).aip"
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

    // MARK: - L5K/L5X Import

    func importL5K() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5K")!]
        panel.canChooseDirectories = false
        panel.message = "Select an L5K file exported from Studio 5000"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.outputMessages.append("[Import] L5K full-file parsing coming soon. Use L5X for now: \(url.lastPathComponent)")
        }
    }

    func importL5X() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5X")!]
        panel.canChooseDirectories = false
        panel.message = "Select an L5X file exported from Studio 5000"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.performL5XImport(from: url)
        }
    }

    private func performL5XImport(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)

            // Generate preview
            let preview = L5XImporter.preview(content)
            importPreview = preview
            pendingImportContent = content

            if let preview = preview {
                // Show preview sheet
                showImportPreview = true
                outputMessages.append("[Import] Preview: \(preview.controllerName) — \(preview.programNames.count) programs, \(preview.rungCount) rungs, \(preview.tagCount) tags")
            } else {
                // Direct import if preview fails
                confirmImport()
            }
        } catch {
            outputMessages.append("[Error] Failed to read L5X file: \(error.localizedDescription)")
        }
    }

    func confirmImport() {
        guard let content = pendingImportContent else { return }

        if let proj = L5XImporter.parse(content) {
            loadProjectData(proj)
            isDirty = true
            let summary = proj.summary
            outputMessages.append("[Import] L5X imported: \(summary.name) — \(summary.rungCount) rungs, \(summary.tagCount) tags")
        } else {
            outputMessages.append("[Import] Failed to parse L5X file")
        }

        showImportPreview = false
        pendingImportContent = nil
        importPreview = nil
    }

    func cancelImport() {
        showImportPreview = false
        pendingImportContent = nil
        importPreview = nil
    }

    // MARK: - L5K/L5X Export

    func exportL5K() {
        guard let project = project else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5K")!]
        panel.nameFieldStringValue = "\(project.name).L5K"
        panel.message = "Export project as L5K (ASCII) for Studio 5000"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let l5k = L5KExporter.export(project)
        do {
            try l5k.write(to: url, atomically: true, encoding: .utf8)
            outputMessages.append("[Export] L5K exported: \(url.lastPathComponent)")
        } catch {
            outputMessages.append("[Error] Failed to write L5K: \(error.localizedDescription)")
        }
    }

    func exportL5X() {
        guard let project = project else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "L5X")!]
        panel.nameFieldStringValue = "\(project.name).L5X"
        panel.message = "Export project as L5X (XML) for Studio 5000"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let l5x = L5XExporter.export(project)
        do {
            try l5x.write(to: url, atomically: true, encoding: .utf8)
            outputMessages.append("[Export] L5X exported: \(url.lastPathComponent)")
        } catch {
            outputMessages.append("[Error] Failed to write L5X: \(error.localizedDescription)")
        }
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

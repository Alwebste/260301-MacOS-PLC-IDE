import SwiftUI

/// Right-side inspector panel — shows properties of the current selection.
struct InspectorView: View {
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch projectManager.selection {
                    case .controller:
                        controllerInspector
                    case .routine(let progName, let routName):
                        routineInspector(programName: progName, routineName: routName)
                    case .controllerTags, .programTags:
                        tagSummaryInspector
                    default:
                        projectSummaryInspector
                    }

                    Spacer()
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Inspector Panels

    @ViewBuilder
    private var controllerInspector: some View {
        if let project = projectManager.project {
            GroupBox("Controller") {
                VStack(alignment: .leading, spacing: 8) {
                    PropertyRow(label: "Name", value: project.controller.name)
                    PropertyRow(label: "Family", value: project.controller.family.displayName)
                    PropertyRow(label: "Catalog", value: project.controller.catalogNumber)
                    PropertyRow(label: "Firmware", value: project.controller.firmwareVersion)
                }
                .padding(4)
            }
        }
    }

    private func routineInspector(programName: String, routineName: String) -> some View {
        Group {
            if let routine = projectManager.project?.findRoutine(
                programName: programName, routineName: routineName) {
                GroupBox("Routine") {
                    VStack(alignment: .leading, spacing: 8) {
                        PropertyRow(label: "Name", value: routine.name)
                        PropertyRow(label: "Program", value: programName)
                        PropertyRow(label: "Rungs", value: "\(routine.rungs.count)")
                        if !routine.description.isEmpty {
                            PropertyRow(label: "Desc", value: routine.description)
                        }
                    }
                    .padding(4)
                }

                GroupBox("Instruction Summary") {
                    VStack(alignment: .leading, spacing: 4) {
                        let counts = instructionCounts(routine.rungs)
                        ForEach(Array(counts.sorted(by: { $0.key < $1.key })), id: \.key) { mnemonic, count in
                            HStack {
                                Text(mnemonic)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
    }

    @ViewBuilder
    private var tagSummaryInspector: some View {
        GroupBox("Tag Summary") {
            VStack(alignment: .leading, spacing: 8) {
                PropertyRow(label: "Scope", value: projectManager.selectedTagScope)
                PropertyRow(label: "Count", value: "\(projectManager.selectedTags.count)")

                // Type breakdown
                let typeCounts = projectManager.selectedTags
                    .reduce(into: [String: Int]()) { counts, tag in
                        counts[tag.dataType.displayName, default: 0] += 1
                    }
                if !typeCounts.isEmpty {
                    Divider()
                    Text("Types")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(typeCounts.sorted(by: { $0.key < $1.key })), id: \.key) { type, count in
                        HStack {
                            Text(type)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var projectSummaryInspector: some View {
        if let summary = projectManager.summary {
            GroupBox("Project") {
                VStack(alignment: .leading, spacing: 8) {
                    PropertyRow(label: "Name", value: summary.name)
                    PropertyRow(label: "Family", value: summary.controllerFamily)
                    PropertyRow(label: "Tasks", value: "\(summary.taskCount)")
                    PropertyRow(label: "Programs", value: "\(summary.programCount)")
                    PropertyRow(label: "Routines", value: "\(summary.routineCount)")
                    PropertyRow(label: "Rungs", value: "\(summary.rungCount)")
                    PropertyRow(label: "Tags", value: "\(summary.tagCount)")
                }
                .padding(4)
            }

            let issues = projectManager.validationIssues
            if !issues.isEmpty {
                GroupBox("Validation") {
                    VStack(alignment: .leading, spacing: 4) {
                        let errors = issues.filter { if case .error = $0.severity { return true }; return false }
                        let warnings = issues.filter { if case .warning = $0.severity { return true }; return false }
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("\(errors.count) error(s)")
                                .font(.caption)
                        }
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text("\(warnings.count) warning(s)")
                                .font(.caption)
                        }
                    }
                    .padding(4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func instructionCounts(_ rungs: [Rung]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for rung in rungs {
            countInstructions(rung.element, counts: &counts)
        }
        return counts
    }

    private func countInstructions(_ element: RungElement, counts: inout [String: Int]) {
        switch element {
        case .instruction(let inst):
            counts[inst.instructionType.mnemonic, default: 0] += 1
        case .series(let elements):
            for el in elements { countInstructions(el, counts: &counts) }
        case .parallel(let branches):
            for branch in branches { countInstructions(branch, counts: &counts) }
        }
    }
}

struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
    }
}

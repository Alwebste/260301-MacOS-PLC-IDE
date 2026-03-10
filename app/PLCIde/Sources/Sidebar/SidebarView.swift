import SwiftUI

/// Project navigator sidebar — data-driven tree view of tasks, programs, routines, tags.
struct SidebarView: View {
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        List(selection: $projectManager.selection) {
            if let project = projectManager.project {
                // Controller section
                Section("Controller") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.controller.name)
                            if !project.controller.catalogNumber.isEmpty {
                                Text(project.controller.catalogNumber)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "cpu")
                            .foregroundColor(.accentColor)
                    }
                    .tag(SidebarSelection.controller)
                }

                // Tasks / Programs / Routines
                Section("Tasks") {
                    ForEach(project.tasks, id: \.id) { task in
                        DisclosureGroup {
                            ForEach(task.programs, id: \.id) { program in
                                DisclosureGroup {
                                    ForEach(program.routines, id: \.id) { routine in
                                        Label {
                                            HStack {
                                                Text(routine.name)
                                                Spacer()
                                                Text("\(routine.rungs.count) rungs")
                                                    .font(.caption2)
                                                    .foregroundColor(.tertiaryLabel)
                                            }
                                        } icon: {
                                            Image(systemName: "list.bullet.rectangle")
                                                .foregroundColor(.orange)
                                        }
                                        .tag(SidebarSelection.routine(
                                            programName: program.name,
                                            routineName: routine.name))
                                    }
                                } label: {
                                    Label(program.name, systemImage: "doc.text")
                                        .foregroundColor(.primary)
                                }
                            }
                        } label: {
                            Label {
                                HStack {
                                    Text(task.name)
                                    Text("(\(task.taskType.displayName))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "play.circle")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                // Tags
                Section("Tags") {
                    Label {
                        HStack {
                            Text("Controller Tags")
                            Spacer()
                            Text("\(project.controllerTags.count)")
                                .font(.caption2)
                                .foregroundColor(.tertiaryLabel)
                        }
                    } icon: {
                        Image(systemName: "tag")
                            .foregroundColor(.purple)
                    }
                    .tag(SidebarSelection.controllerTags)

                    ForEach(project.programNames, id: \.self) { programName in
                        Label {
                            HStack {
                                Text("\(programName) Tags")
                                Spacer()
                                Text("\(project.programTags(for: programName).count)")
                                    .font(.caption2)
                                    .foregroundColor(.tertiaryLabel)
                            }
                        } icon: {
                            Image(systemName: "tag")
                                .foregroundColor(.teal)
                        }
                        .tag(SidebarSelection.programTags(programName: programName))
                    }
                }

                // I/O Configuration (future)
                Section("I/O") {
                    Text("Phase 4+")
                        .font(.caption)
                        .foregroundColor(.tertiaryLabel)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: projectManager.selection) { newSelection in
            handleSelectionChange(newSelection)
        }
    }

    private func handleSelectionChange(_ selection: SidebarSelection?) {
        guard let selection = selection else { return }
        switch selection {
        case .routine(let programName, let routineName):
            projectManager.selectRoutine(programName: programName, routineName: routineName)
        case .controllerTags:
            projectManager.selectControllerTags()
        case .programTags(let programName):
            projectManager.selectProgramTags(programName: programName)
        default:
            break
        }
    }
}

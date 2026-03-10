import SwiftUI

@main
struct PLCIdeApp: App {
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var aiAssistant = AIAssistant()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(projectManager)
                .environmentObject(connectionManager)
                .environmentObject(aiAssistant)
                .frame(minWidth: 1200, minHeight: 800)
                .onAppear {
                    connectionManager.setOutputHandler { msg in
                        projectManager.outputMessages.append(msg)
                    }
                    aiAssistant.setOutputHandler { msg in
                        projectManager.outputMessages.append(msg)
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            FileCommands(projectManager: projectManager)
        }
    }
}

/// Custom file menu commands
struct FileCommands: Commands {
    @ObservedObject var projectManager: ProjectManager

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project...") {
                projectManager.createNewProject()
            }
            .keyboardShortcut("n")

            Button("Open Project...") {
                projectManager.openProject()
            }
            .keyboardShortcut("o")

            Button("Save Project") {
                projectManager.saveProject()
            }
            .keyboardShortcut("s")
            .disabled(!projectManager.hasProject)

            Divider()

            Button("Import L5K...") {
                projectManager.importL5K()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Import L5X...") {
                projectManager.importL5X()
            }

            Divider()

            Button("Export L5K...") {
                projectManager.exportL5K()
            }
            .disabled(!projectManager.hasProject)

            Button("Export L5X...") {
                projectManager.exportL5X()
            }
            .disabled(!projectManager.hasProject)
        }
    }
}

import SwiftUI

/// Sheet shown after selecting an L5X file — displays project summary before import.
struct ImportPreviewSheet: View {
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Import L5X Project")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Divider()

            if let preview = projectManager.importPreview {
                // Project info
                GroupBox("Project Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("Controller", preview.controllerName)
                        infoRow("Processor", preview.processorType)
                        infoRow("Programs", "\(preview.programNames.count)")
                        infoRow("Routines", "\(preview.routineCount)")
                        infoRow("Rungs", "\(preview.rungCount)")
                        infoRow("Tags", "\(preview.tagCount)")
                    }
                    .padding(4)
                }

                // Program list
                if !preview.programNames.isEmpty {
                    GroupBox("Programs") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(preview.programNames, id: \.self) { name in
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.blue)
                                    Text(name)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                // Warnings
                if !preview.warnings.isEmpty {
                    GroupBox("Warnings") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(preview.warnings, id: \.self) { warning in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.yellow)
                                    Text(warning)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    projectManager.cancelImport()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Import") {
                    projectManager.confirmImport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}

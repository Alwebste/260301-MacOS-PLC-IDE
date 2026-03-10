import SwiftUI

/// Bottom panel — shows validation errors, warnings, and output log messages.
struct OutputPanelView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var selectedTab: OutputTab = .errors

    enum OutputTab: String, CaseIterable {
        case errors = "Errors"
        case warnings = "Warnings"
        case output = "Output"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(OutputTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            tabIcon(for: tab)
                            Text(tab.rawValue)
                                .font(.caption)
                            // Badge count
                            let count = badgeCount(for: tab)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(badgeColor(for: tab))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                // Clear button
                Button {
                    projectManager.outputMessages.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help("Clear output")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    switch selectedTab {
                    case .errors:
                        let errors = projectManager.validationIssues.filter {
                            if case .error = $0.severity { return true }; return false
                        }
                        if errors.isEmpty {
                            emptyMessage("No errors")
                        } else {
                            ForEach(errors) { issue in
                                IssueRow(issue: issue)
                            }
                        }

                    case .warnings:
                        let warnings = projectManager.validationIssues.filter {
                            if case .warning = $0.severity { return true }; return false
                        }
                        if warnings.isEmpty {
                            emptyMessage("No warnings")
                        } else {
                            ForEach(warnings) { issue in
                                IssueRow(issue: issue)
                            }
                        }

                    case .output:
                        if projectManager.outputMessages.isEmpty {
                            emptyMessage("No output")
                        } else {
                            ForEach(Array(projectManager.outputMessages.enumerated()), id: \.offset) { _, msg in
                                Text(msg)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(8)
    }

    @ViewBuilder
    private func tabIcon(for tab: OutputTab) -> some View {
        switch tab {
        case .errors:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .warnings:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
        case .output:
            Image(systemName: "text.alignleft")
                .foregroundColor(.secondary)
        }
    }

    private func badgeCount(for tab: OutputTab) -> Int {
        switch tab {
        case .errors:
            return projectManager.validationIssues.filter {
                if case .error = $0.severity { return true }; return false
            }.count
        case .warnings:
            return projectManager.validationIssues.filter {
                if case .warning = $0.severity { return true }; return false
            }.count
        case .output:
            return 0
        }
    }

    private func badgeColor(for tab: OutputTab) -> Color {
        switch tab {
        case .errors: return .red
        case .warnings: return .orange
        case .output: return .gray
        }
    }
}

/// A single validation issue row
struct IssueRow: View {
    let issue: ValidationIssue

    var body: some View {
        HStack(spacing: 6) {
            issueIcon
                .font(.caption)

            Text(issue.message)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Text("\(issue.programName)/\(issue.routineName)")
                .font(.caption2)
                .foregroundColor(.tertiaryLabel)

            if let rungNum = issue.rungNumber {
                Text("Rung \(rungNum)")
                    .font(.caption2)
                    .foregroundColor(.tertiaryLabel)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var issueIcon: some View {
        switch issue.severity {
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
        }
    }
}

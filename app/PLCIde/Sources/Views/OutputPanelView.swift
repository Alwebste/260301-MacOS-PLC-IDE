import SwiftUI

/// Bottom panel — shows errors, warnings, validation output, and log messages.
struct OutputPanelView: View {
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Placeholder — Phase 1: populated from plc_core.validate_project()
                    Text("No issues.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
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
}

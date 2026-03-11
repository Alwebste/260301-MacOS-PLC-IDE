// CommManagerRootView.swift
// PLCCommManager - PLC Communications Manager
// Root view for the Communications tab — inner tab bar with driver list, network browser, paths, diagnostics

import SwiftUI

/// Root view for the Communications tab — contains an inner navigation for comms subsections
struct CommManagerRootView: View {
    @EnvironmentObject var commStore: CommManagerStore
    @State private var selectedSection: CommSection = .drivers

    enum CommSection: String, CaseIterable, Identifiable {
        case drivers = "Comm Drivers"
        case networkBrowser = "Network Browser"
        case connectionPaths = "Connection Paths"
        case diagnostics = "Diagnostics"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .drivers: return "externaldrive.connected.to.line.below"
            case .networkBrowser: return "network"
            case .connectionPaths: return "point.topleft.down.to.point.bottomright.curvepath"
            case .diagnostics: return "waveform.path.ecg"
            }
        }

        var description: String {
            switch self {
            case .drivers: return "Configure and manage communication drivers"
            case .networkBrowser: return "Discover PLCs and devices on the network"
            case .connectionPaths: return "Define and manage communication paths to PLCs"
            case .diagnostics: return "Monitor communication health and view logs"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Inner section tab bar
            sectionTabBar
            Divider()

            // Section content
            sectionContent
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sectionTabBar: some View {
        HStack(spacing: 2) {
            ForEach(CommSection.allCases) { section in
                sectionButton(section)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func sectionButton(_ section: CommSection) -> some View {
        Button(action: { selectedSection = section }) {
            HStack(spacing: 4) {
                Image(systemName: section.icon)
                    .font(.system(size: 11))
                Text(section.rawValue)
                    .font(.system(size: 12, weight: selectedSection == section ? .semibold : .regular))

                if section == .diagnostics {
                    let errorCount = commStore.diagnosticEvents.filter { $0.severity == .error || $0.severity == .critical }.count
                    if errorCount > 0 {
                        Text("\(errorCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedSection == section ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .foregroundColor(selectedSection == section ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .drivers:
            DriverListView()
        case .networkBrowser:
            NetworkBrowserView()
        case .connectionPaths:
            ConnectionPathsView()
        case .diagnostics:
            DiagnosticsView()
        }
    }
}

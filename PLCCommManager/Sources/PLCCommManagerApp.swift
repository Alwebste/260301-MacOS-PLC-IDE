// PLCCommManagerApp.swift
// PLCCommManager - PLC Communications Manager
// Main application entry point with top tab bar navigation

import SwiftUI

@main
struct PLCCommManagerApp: App {
    @StateObject private var commStore = CommManagerStore()

    var body: some Scene {
        WindowGroup {
            MainTabBarView()
                .environmentObject(commStore)
                .frame(minWidth: 1200, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 850)
    }
}

// MARK: - Top Tab Bar Navigation

/// Top-level tab bar for the entire IDE — Communications is one of the primary tabs
struct MainTabBarView: View {
    @EnvironmentObject var commStore: CommManagerStore
    @State private var selectedTab: TopTab = .communications

    enum TopTab: String, CaseIterable, Identifiable {
        case project = "Project"
        case ladderEditor = "Ladder Editor"
        case tagBrowser = "Tags"
        case communications = "Communications"
        case simulation = "Simulation"
        case aiAssistant = "AI Assistant"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .project: return "folder.fill"
            case .ladderEditor: return "square.grid.3x3"
            case .tagBrowser: return "tag.fill"
            case .communications: return "network"
            case .simulation: return "play.circle.fill"
            case .aiAssistant: return "brain"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Tab Bar
            topTabBar

            Divider()

            // Content area based on selected tab
            tabContent
        }
    }

    private var topTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TopTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()

            // Global connection status indicator
            connectionStatusBadge
                .padding(.trailing, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tabButton(_ tab: TopTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))

                // Show active connection count badge on Communications tab
                if tab == .communications && commStore.activeConnectionCount > 0 {
                    Text("\(commStore.activeConnectionCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
            .foregroundColor(selectedTab == tab ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(selectedTab == tab ? .accentColor : .clear),
            alignment: .bottom
        )
    }

    private var connectionStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(commStore.hasAnyConnection ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(commStore.hasAnyConnection ? "\(commStore.activeConnectionCount) Online" : "Offline")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .project:
            PlaceholderTabView(tabName: "Project Navigator", icon: "folder.fill",
                               description: "Project file management, controller settings, and program organization.")
        case .ladderEditor:
            PlaceholderTabView(tabName: "Ladder Logic Editor", icon: "square.grid.3x3",
                               description: "Visual ladder logic editor with drag-and-drop instructions.")
        case .tagBrowser:
            PlaceholderTabView(tabName: "Tag Browser", icon: "tag.fill",
                               description: "Tag database with search, filtering, and real-time monitoring.")
        case .communications:
            CommManagerRootView()
        case .simulation:
            PlaceholderTabView(tabName: "Simulation", icon: "play.circle.fill",
                               description: "Local scan simulator with step-through and continuous modes.")
        case .aiAssistant:
            PlaceholderTabView(tabName: "AI Assistant", icon: "brain",
                               description: "AI-assisted ladder generation, rung explanation, and optimization.")
        }
    }
}

// MARK: - Placeholder for future tabs

struct PlaceholderTabView: View {
    let tabName: String
    let icon: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(tabName)
                .font(.title2.weight(.semibold))
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Text("Coming in a future phase")
                .font(.caption)
                .foregroundColor(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

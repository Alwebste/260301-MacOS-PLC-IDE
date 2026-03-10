import SwiftUI

/// Live tag watch window — polls tag values from a connected PLC.
/// Shows real-time values, allows writing, and supports forcing.
struct LiveTagWatchView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var projectManager: ProjectManager

    @State private var newTagName: String = ""
    @State private var filterText: String = ""
    @State private var editingTag: String? = nil
    @State private var editValue: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(connectionManager.isPolling ? .green : .secondary)
                Text("Live Tags")
                    .font(.headline)
                Spacer()

                // Poll controls
                if connectionManager.connectionState.isConnected {
                    Picker("", selection: $connectionManager.pollIntervalMs) {
                        Text("100ms").tag(100)
                        Text("250ms").tag(250)
                        Text("500ms").tag(500)
                        Text("1s").tag(1000)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Button {
                        if connectionManager.isPolling {
                            connectionManager.stopPolling()
                        } else {
                            connectionManager.startPolling()
                        }
                    } label: {
                        Image(systemName: connectionManager.isPolling ? "pause.fill" : "play.fill")
                    }
                    .help(connectionManager.isPolling ? "Stop polling" : "Start polling")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Add tag bar
            HStack(spacing: 4) {
                TextField("Tag name...", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit { addTag() }

                Button("Add") { addTag() }
                    .disabled(newTagName.isEmpty)

                Button {
                    connectionManager.addProjectTags(from: projectManager.project)
                } label: {
                    Image(systemName: "plus.rectangle.on.folder")
                }
                .help("Add all controller tags")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Filter
            if connectionManager.watchedTags.count > 5 {
                TextField("Filter...", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }

            Divider()

            // Tag table
            if connectionManager.liveTagValues.isEmpty && connectionManager.watchedTags.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No tags watched")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Add tag names above or load from project")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("Tag Name")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Value")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(width: 80, alignment: .trailing)
                    Text("Type")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(width: 50, alignment: .center)
                    // Action column
                    Color.clear.frame(width: 50)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(nsColor: .separatorColor).opacity(0.3))

                List {
                    ForEach(filteredValues, id: \.name) { tag in
                        tagRow(tag)
                    }
                    .onDelete { indices in
                        let filtered = filteredValues
                        for index in indices {
                            connectionManager.removeWatchTag(filtered[index].name)
                        }
                    }

                    // Tags without values yet (not polled)
                    ForEach(unpolledTags, id: \.self) { tagName in
                        HStack {
                            Text(tagName)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("—")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)
                            Text("?")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .center)
                            Button {
                                connectionManager.removeWatchTag(tagName)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 50)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .listStyle(.plain)
            }

            // Status bar
            HStack {
                Text("\(connectionManager.watchedTags.count) tags")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if connectionManager.isPolling {
                    Text("polling")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                Spacer()
                if connectionManager.lastResponseTimeMs > 0 {
                    Text(String(format: "%.1f ms", connectionManager.lastResponseTimeMs))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tagRow(_ tag: LiveTagValue) -> some View {
        HStack(spacing: 0) {
            // Force indicator + name
            HStack(spacing: 4) {
                if tag.forced {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                Text(tag.name)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Value (editable on click)
            if editingTag == tag.name {
                TextField("", text: $editValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 80)
                    .onSubmit {
                        connectionManager.writeTag(name: tag.name, value: editValue)
                        editingTag = nil
                    }
            } else {
                Text(tag.value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(tag.forced ? .orange : .primary)
                    .frame(width: 80, alignment: .trailing)
                    .onTapGesture {
                        editingTag = tag.name
                        editValue = tag.value
                    }
            }

            // Type
            Text(tag.dataType)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .center)

            // Actions
            HStack(spacing: 2) {
                if tag.forced {
                    Button {
                        connectionManager.removeForce(name: tag.name)
                    } label: {
                        Image(systemName: "lock.open")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        connectionManager.forceTag(name: tag.name, value: tag.value)
                    } label: {
                        Image(systemName: "lock")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Force tag value")
                }

                Button {
                    connectionManager.removeWatchTag(tag.name)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 50)
        }
        .padding(.vertical, 1)
    }

    private var filteredValues: [LiveTagValue] {
        if filterText.isEmpty {
            return connectionManager.liveTagValues
        }
        let q = filterText.lowercased()
        return connectionManager.liveTagValues.filter { $0.name.lowercased().contains(q) }
    }

    private var unpolledTags: [String] {
        let polled = Set(connectionManager.liveTagValues.map(\.name))
        return connectionManager.watchedTags.filter { !polled.contains($0) }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        connectionManager.addWatchTag(trimmed)
        newTagName = ""
    }
}

import SwiftUI

/// AI Assistant panel — chat interface for generating, explaining, and optimizing ladder logic.
///
/// Features:
/// - Natural language → ladder generation with preview
/// - Explain selected rungs in plain English
/// - Suggest improvements for existing logic
/// - Free-form chat about PLC programming
struct AIPanelView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var aiAssistant: AIAssistant

    @State private var inputText: String = ""
    @State private var selectedMode: AIMode = .generate

    enum AIMode: String, CaseIterable {
        case generate = "Generate"
        case explain = "Explain"
        case suggest = "Suggest"
        case chat = "Chat"

        var icon: String {
            switch self {
            case .generate: return "wand.and.stars"
            case .explain: return "text.bubble"
            case .suggest: return "lightbulb"
            case .chat: return "ellipsis.message"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                Text("AI Assistant")
                    .font(.headline)
                Spacer()

                if !aiAssistant.apiKeyConfigured {
                    Label("Offline", systemImage: "bolt.slash")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Label("API Connected", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Button {
                    aiAssistant.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Mode selector
            Picker("", selection: $selectedMode) {
                ForEach(AIMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Mode-specific header
            modeHeader

            Divider()

            // API key setup prompt
            if !aiAssistant.apiKeyConfigured {
                HStack(spacing: 8) {
                    Image(systemName: "key")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API key not configured")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Using offline pattern library. Configure your Anthropic API key for full AI capabilities.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
                .padding(.horizontal, 8)
            }

            // Chat history
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(aiAssistant.messages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }

                        if aiAssistant.isProcessing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: aiAssistant.messages.count) { _ in
                    if let lastMsg = aiAssistant.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 6) {
                TextField(placeholderText, text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(inputText.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || aiAssistant.isProcessing)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(8)

            // Quick action buttons
            quickActions
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Mode Header

    @ViewBuilder
    private var modeHeader: some View {
        switch selectedMode {
        case .generate:
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Describe the logic you want in plain English")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

        case .explain:
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Select rungs in the ladder editor, then click Explain")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

        case .suggest:
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("AI will review the current routine for improvements")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

        case .chat:
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Ask anything about PLC programming")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickButton("Motor Control", "gearshape") {
                    inputText = "Create a three-wire motor start/stop circuit with overload protection"
                    sendMessage()
                }
                quickButton("Timer Delay", "timer") {
                    inputText = "Add a 5-second on-delay timer to activate an output"
                    sendMessage()
                }
                quickButton("Counter", "number") {
                    inputText = "Create a parts counter that stops at 100"
                    sendMessage()
                }
                quickButton("Explain Rungs", "text.bubble") {
                    explainSelectedRungs()
                }
                quickButton("Review Logic", "checkmark.shield") {
                    suggestImprovements()
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private func quickButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(aiAssistant.isProcessing)
    }

    // MARK: - Chat Bubble

    private func chatBubble(_ message: AIChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            // Role label
            HStack {
                if message.role == .user {
                    Spacer()
                    Text("You")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text("AI Assistant")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // Content
            Text(message.content)
                .font(.system(.caption, design: .default))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(message.role == .user
                              ? Color.accentColor.opacity(0.15)
                              : Color(nsColor: .windowBackgroundColor))
                )
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            // Generated rungs preview
            if let rungs = message.generatedRungs, !rungs.isEmpty {
                generatedRungsPreview(rungs)
            }

            // Suggestions
            if let suggestions = message.suggestions, !suggestions.isEmpty {
                suggestionsView(suggestions)
            }
        }
    }

    // MARK: - Generated Rungs Preview

    private func generatedRungsPreview(_ rungs: [Rung]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundColor(.purple)
                Text("Generated \(rungs.count) rung(s)")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()

                // Accept button
                Button("Accept") {
                    acceptGeneratedRungs(rungs)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Copy") {
                    let text = rungs.map { $0.element.neutralText }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
            }

            // Rung list
            ForEach(rungs) { rung in
                VStack(alignment: .leading, spacing: 2) {
                    if !rung.comment.isEmpty {
                        Text("// \(rung.comment)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    Text(rung.element.neutralText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            }

            // AI draft warning
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("AI-generated draft — review before use")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Suggestions View

    private func suggestionsView(_ suggestions: [AISuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(suggestions) { suggestion in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: suggestion.category.icon)
                        .font(.caption)
                        .foregroundColor(suggestion.category == .safety ? .red : .blue)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.caption)
                            .fontWeight(.medium)
                        if !suggestion.description.isEmpty {
                            Text(suggestion.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    // MARK: - Actions

    private var placeholderText: String {
        switch selectedMode {
        case .generate: return "Describe the ladder logic you want..."
        case .explain: return "Ask about the selected rungs..."
        case .suggest: return "What should I look for?"
        case .chat: return "Ask about PLC programming..."
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        switch selectedMode {
        case .generate:
            let tags = projectManager.project?.tagDatabase.tags ?? []
            var ctx: String? = nil
            if case .routine(let prog, let rout) = projectManager.selection {
                ctx = "Program: \(prog), Routine: \(rout), Existing rungs: \(projectManager.selectedRoutineRungs.count)"
            }
            aiAssistant.generateLadder(prompt: text, existingTags: tags, routineContext: ctx)

        case .explain:
            if !projectManager.selectedRoutineRungs.isEmpty {
                let progName = currentProgramName
                let routName = currentRoutineName
                aiAssistant.explainRungs(projectManager.selectedRoutineRungs, programName: progName, routineName: routName)
            } else {
                aiAssistant.chat(message: "Explain: \(text)", context: projectContext)
            }

        case .suggest:
            suggestImprovements()

        case .chat:
            aiAssistant.chat(message: text, context: projectContext)
        }
    }

    private func explainSelectedRungs() {
        guard !projectManager.selectedRoutineRungs.isEmpty else {
            aiAssistant.chat(message: "No rungs selected. Please select a routine in the sidebar first.", context: nil)
            return
        }
        selectedMode = .explain
        aiAssistant.explainRungs(
            projectManager.selectedRoutineRungs,
            programName: currentProgramName,
            routineName: currentRoutineName
        )
    }

    private func suggestImprovements() {
        guard !projectManager.selectedRoutineRungs.isEmpty else {
            aiAssistant.chat(message: "No routine selected. Please select a routine in the sidebar first.", context: nil)
            return
        }
        selectedMode = .suggest
        aiAssistant.suggestImprovements(
            for: projectManager.selectedRoutineRungs,
            tags: projectManager.project?.tagDatabase.tags ?? [],
            programName: currentProgramName
        )
    }

    private func acceptGeneratedRungs(_ rungs: [Rung]) {
        // Add to output log
        projectManager.outputMessages.append("[AI] Accepted \(rungs.count) AI-generated rung(s)")
        // In a full implementation, this would insert rungs into the current routine
        projectManager.outputMessages.append("[AI] Rungs copied to clipboard — paste into ladder editor")

        let text = rungs.map { rung in
            var line = ""
            if !rung.comment.isEmpty { line += "// \(rung.comment)\n" }
            line += rung.element.neutralText
            return line
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var currentProgramName: String {
        if case .routine(let prog, _) = projectManager.selection { return prog }
        return "MainProgram"
    }

    private var currentRoutineName: String {
        if case .routine(_, let rout) = projectManager.selection { return rout }
        return "MainRoutine"
    }

    private var projectContext: String? {
        guard let proj = projectManager.project else { return nil }
        let s = proj.summary
        return "Project: \(s.name), Controller: \(s.controllerFamily) \(s.catalogNumber), \(s.rungCount) rungs, \(s.tagCount) tags"
    }
}

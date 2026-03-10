import SwiftUI

/// Application Settings window — accessible via Cmd+, (standard macOS preferences).
struct SettingsView: View {
    @EnvironmentObject var aiAssistant: AIAssistant

    @State private var apiKeyInput: String = ""
    @State private var showKey: Bool = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var testStatus: TestStatus = .idle

    enum SaveStatus {
        case idle, saved, failed
    }

    enum TestStatus {
        case idle, testing, success, failed(String)
    }

    var body: some View {
        TabView {
            aiSettingsTab
                .tabItem {
                    Label("AI Assistant", systemImage: "brain")
                }
        }
        .frame(width: 520, height: 380)
        .onAppear {
            // Show masked placeholder if key exists
            if aiAssistant.apiKeyConfigured {
                apiKeyInput = "sk-ant-••••••••••••••••"
            }
        }
    }

    // MARK: - AI Settings Tab

    private var aiSettingsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // Status
                    HStack {
                        Image(systemName: aiAssistant.apiKeyConfigured ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(aiAssistant.apiKeyConfigured ? .green : .red)
                        Text(aiAssistant.apiKeyConfigured ? "API Key Configured" : "API Key Not Set")
                            .fontWeight(.medium)
                    }

                    // API Key input
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anthropic API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if showKey {
                                TextField("sk-ant-...", text: $apiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("sk-ant-...", text: $apiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(showKey ? "Hide Key" : "Show Key")
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button("Save to Keychain") {
                            saveApiKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyInput.isEmpty || apiKeyInput.hasPrefix("sk-ant-••"))

                        Button("Test Connection") {
                            testConnection()
                        }
                        .disabled(!aiAssistant.apiKeyConfigured)

                        Button("Clear Key") {
                            clearApiKey()
                        }
                        .foregroundColor(.red)

                        Spacer()

                        // Status indicator
                        switch saveStatus {
                        case .saved:
                            Label("Saved", systemImage: "checkmark")
                                .foregroundColor(.green)
                                .font(.caption)
                        case .failed:
                            Label("Save Failed", systemImage: "xmark")
                                .foregroundColor(.red)
                                .font(.caption)
                        case .idle:
                            EmptyView()
                        }
                    }

                    // Test status
                    switch testStatus {
                    case .testing:
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing connection...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    case .failed(let error):
                        Label("Connection failed: \(error)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.red)
                    case .idle:
                        EmptyView()
                    }
                }
            } header: {
                Text("API Configuration")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The AI Assistant uses the Anthropic Claude API to generate, explain, and optimize ladder logic.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Without an API key, the assistant uses a built-in pattern library for common PLC patterns (motor control, timers, counters).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Get an API key at")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link("console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                            .font(.caption)
                    }
                }
            } header: {
                Text("About")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your API key is stored in the macOS Keychain, encrypted at rest.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("It is never sent anywhere except the Anthropic API endpoint.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("You can also set ANTHROPIC_API_KEY as an environment variable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Security")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Actions

    private func saveApiKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("sk-ant-••") else { return }

        if KeychainHelper.save(key: key) {
            aiAssistant.setApiKey(key)
            apiKeyInput = "sk-ant-••••••••••••••••"
            saveStatus = .saved
        } else {
            saveStatus = .failed
        }

        // Reset status after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .idle
        }
    }

    private func clearApiKey() {
        KeychainHelper.delete()
        aiAssistant.setApiKey("")
        apiKeyInput = ""
        saveStatus = .idle
        testStatus = .idle
    }

    private func testConnection() {
        testStatus = .testing

        // Make a minimal API call to verify the key works
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(aiAssistant.apiKeyForTesting, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "test"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    testStatus = .failed(error.localizedDescription)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        testStatus = .success
                    } else if httpResponse.statusCode == 401 {
                        testStatus = .failed("Invalid API key")
                    } else {
                        testStatus = .failed("HTTP \(httpResponse.statusCode)")
                    }
                }
            }
        }.resume()
    }
}

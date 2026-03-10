import Foundation
import Combine

/// AI-generated ladder logic result.
struct AIGeneratedRungs {
    let rungs: [Rung]
    let explanation: String
    let warnings: [String]
    let confidence: Double // 0.0–1.0
}

/// AI explanation of existing logic.
struct AIExplanation {
    let summary: String
    let details: [String]
    let safetyNotes: [String]
}

/// AI suggestion for improving logic.
struct AISuggestion: Identifiable {
    let id = UUID().uuidString
    let category: SuggestionCategory
    let title: String
    let description: String
    let suggestedRungs: [Rung]?

    enum SuggestionCategory {
        case safety
        case performance
        case bestPractice
        case simplification

        var icon: String {
            switch self {
            case .safety: return "exclamationmark.shield"
            case .performance: return "gauge.with.dots.needle.67percent"
            case .bestPractice: return "checkmark.seal"
            case .simplification: return "scissors"
            }
        }

        var displayName: String {
            switch self {
            case .safety: return "Safety"
            case .performance: return "Performance"
            case .bestPractice: return "Best Practice"
            case .simplification: return "Simplification"
            }
        }
    }
}

/// Chat message in the AI conversation.
struct AIChatMessage: Identifiable {
    let id = UUID().uuidString
    let role: Role
    let content: String
    let timestamp: Date
    var generatedRungs: [Rung]?
    var explanation: AIExplanation?
    var suggestions: [AISuggestion]?

    enum Role {
        case user
        case assistant
        case system
    }
}

/// AI Assistant service — handles prompt engineering, LLM calls, and response parsing.
///
/// Uses the Anthropic Claude API for ladder logic generation, explanation, and optimization.
/// All AI outputs are drafts that require engineer review before use.
class AIAssistant: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var isProcessing: Bool = false
    @Published var apiKeyConfigured: Bool = false

    private var apiKey: String = ""
    private var outputHandler: ((String) -> Void)?

    init() {
        // Check for API key in environment or keychain
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            apiKey = key
            apiKeyConfigured = true
        }
    }

    func setOutputHandler(_ handler: @escaping (String) -> Void) {
        outputHandler = handler
    }

    func setApiKey(_ key: String) {
        apiKey = key
        apiKeyConfigured = !key.isEmpty
    }

    // MARK: - Generate Ladder from Natural Language

    func generateLadder(prompt: String, existingTags: [Tag], routineContext: String?) {
        let userMsg = AIChatMessage(role: .user, content: prompt, timestamp: Date())
        messages.append(userMsg)
        isProcessing = true
        outputHandler?("[AI] Generating ladder logic: \"\(prompt)\"")

        let systemPrompt = buildGenerationSystemPrompt(existingTags: existingTags, routineContext: routineContext)
        let userContent = "Generate ladder logic for the following requirement:\n\n\(prompt)\n\nRespond with a JSON object containing:\n- \"rungs\": array of rung objects\n- \"explanation\": brief description of the generated logic\n- \"warnings\": array of safety/practice warnings\n- \"tags_needed\": array of new tags needed (name, type, description)"

        callLLM(system: systemPrompt, user: userContent) { [weak self] response in
            guard let self = self else { return }

            if let result = self.parseGenerationResponse(response) {
                let assistantMsg = AIChatMessage(
                    role: .assistant,
                    content: result.explanation,
                    timestamp: Date(),
                    generatedRungs: result.rungs
                )
                DispatchQueue.main.async {
                    self.messages.append(assistantMsg)
                    self.isProcessing = false
                    self.outputHandler?("[AI] Generated \(result.rungs.count) rungs")
                    if !result.warnings.isEmpty {
                        for w in result.warnings {
                            self.outputHandler?("[AI Warning] \(w)")
                        }
                    }
                }
            } else {
                let errorMsg = AIChatMessage(
                    role: .assistant,
                    content: "I generated the following logic:\n\n\(response)\n\nNote: Auto-parsing is not yet available. You can manually add these rungs.",
                    timestamp: Date()
                )
                DispatchQueue.main.async {
                    self.messages.append(errorMsg)
                    self.isProcessing = false
                }
            }
        }
    }

    // MARK: - Explain Rung

    func explainRungs(_ rungs: [Rung], programName: String, routineName: String) {
        let rungText = rungs.map { rung in
            var text = "Rung \(rung.number)"
            if !rung.comment.isEmpty { text += " // \(rung.comment)" }
            text += ": \(rung.element.neutralText)"
            return text
        }.joined(separator: "\n")

        let userMsg = AIChatMessage(
            role: .user,
            content: "Explain the following ladder logic in \(programName)/\(routineName):\n\n\(rungText)",
            timestamp: Date()
        )
        messages.append(userMsg)
        isProcessing = true
        outputHandler?("[AI] Explaining \(rungs.count) rung(s)")

        let systemPrompt = buildExplainSystemPrompt()
        let userContent = "Explain the following Allen-Bradley ladder logic rungs. Provide:\n1. A plain-English summary of what the logic does\n2. Detailed explanation of each rung\n3. Any safety considerations\n\nLadder logic:\n\(rungText)"

        callLLM(system: systemPrompt, user: userContent) { [weak self] response in
            guard let self = self else { return }

            let explanation = AIExplanation(
                summary: response,
                details: [],
                safetyNotes: []
            )

            let assistantMsg = AIChatMessage(
                role: .assistant,
                content: response,
                timestamp: Date(),
                explanation: explanation
            )

            DispatchQueue.main.async {
                self.messages.append(assistantMsg)
                self.isProcessing = false
            }
        }
    }

    // MARK: - Suggest Improvements

    func suggestImprovements(for rungs: [Rung], tags: [Tag], programName: String) {
        let _ = rungs.map { "Rung \($0.number): \($0.element.neutralText)" }

        let userMsg = AIChatMessage(
            role: .user,
            content: "Suggest improvements for \(rungs.count) rungs in \(programName)",
            timestamp: Date()
        )
        messages.append(userMsg)
        isProcessing = true
        outputHandler?("[AI] Analyzing \(rungs.count) rungs for improvements")

        let systemPrompt = buildSuggestSystemPrompt()
        let rungLines = rungs.map { rung in
            "Rung \(rung.number): \(rung.element.neutralText)"
        }.joined(separator: "\n")
        let tagLines = tags.prefix(50).map { "\($0.name): \($0.dataType.displayName)" }.joined(separator: "\n")

        let userContent = """
        Review the following Allen-Bradley ladder logic and suggest improvements.

        Rungs:
        \(rungLines)

        Available tags:
        \(tagLines)

        Provide suggestions in these categories:
        1. Safety: missing interlocks, race conditions, unsafe patterns
        2. Performance: unnecessary instructions, redundant logic
        3. Best Practice: naming conventions, documentation, structure
        4. Simplification: logic that can be simplified
        """

        callLLM(system: systemPrompt, user: userContent) { [weak self] response in
            guard let self = self else { return }

            let suggestions = self.parseSuggestions(response)

            let assistantMsg = AIChatMessage(
                role: .assistant,
                content: response,
                timestamp: Date(),
                suggestions: suggestions
            )

            DispatchQueue.main.async {
                self.messages.append(assistantMsg)
                self.isProcessing = false
                self.outputHandler?("[AI] Found \(suggestions.count) suggestion(s)")
            }
        }
    }

    // MARK: - Free Chat

    func chat(message: String, context: String?) {
        let userMsg = AIChatMessage(role: .user, content: message, timestamp: Date())
        messages.append(userMsg)
        isProcessing = true

        let systemPrompt = buildChatSystemPrompt(context: context)

        callLLM(system: systemPrompt, user: message) { [weak self] response in
            guard let self = self else { return }
            let assistantMsg = AIChatMessage(role: .assistant, content: response, timestamp: Date())
            DispatchQueue.main.async {
                self.messages.append(assistantMsg)
                self.isProcessing = false
            }
        }
    }

    func clearHistory() {
        messages.removeAll()
    }

    // MARK: - LLM API Call

    private func callLLM(system: String, user: String, completion: @escaping (String) -> Void) {
        guard apiKeyConfigured else {
            // Fallback: use built-in pattern library for common requests
            let fallback = generateFallbackResponse(system: system, user: user)
            completion(fallback)
            return
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion("Error: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstBlock = content.first,
                  let text = firstBlock["text"] as? String else {
                completion("Error: Failed to parse API response")
                return
            }

            completion(text)
        }.resume()
    }

    // MARK: - Prompt Engineering

    private func buildGenerationSystemPrompt(existingTags: [Tag], routineContext: String?) -> String {
        var prompt = """
        You are an expert Allen-Bradley PLC programmer specializing in ControlLogix and CompactLogix ladder logic.

        IMPORTANT RULES:
        - Generate valid ladder logic using standard AB instructions
        - Use proper tag naming conventions (PascalCase with underscores for word separation)
        - Always include safety considerations in your response
        - Output rungs in the internal text format: XIC(tag) OTE(tag), [branch1,branch2] for parallel

        AVAILABLE INSTRUCTIONS:
        Input: XIC (examine if closed), XIO (examine if open), ONS (one-shot)
        Output: OTE (output energize), OTL (output latch), OTU (output unlatch)
        Timer: TON (timer on delay), TOF (timer off delay), RTO (retentive timer on)
        Counter: CTU (count up), CTD (count down), RES (reset)
        Compare: EQU, NEQ, LES, LEQ, GRT, GEQ
        Math: ADD, SUB, MUL, DIV, MOD, NEG, MOV, COP
        Program: JMP, LBL, JSR, RET, SBR

        RUNG FORMAT:
        - Series: instruction1 instruction2 (space-separated)
        - Parallel branches: [branch1,branch2] where each branch is a series
        - Example: XIC(Start_PB) XIO(Stop_PB) OTE(Motor_Run)
        - Example with branch: [XIC(Start_PB),XIC(Motor_Run)] XIO(Stop_PB) OTE(Motor_Run)

        COMMON PATTERNS:
        - Three-wire motor control: [XIC(Start_PB),XIC(Motor_Run)] XIO(Stop_PB) XIO(Motor_OL) OTE(Motor_Run)
        - Timer delay: XIC(condition) TON(Timer1,5000,0) | XIC(Timer1.DN) OTE(output)
        - Counter: XIC(sensor) CTU(Counter1,10,0) | XIC(Counter1.DN) OTE(done) | XIC(reset) RES(Counter1)

        RESPONSE FORMAT (JSON):
        {
          "rungs": [
            {
              "comment": "Start/stop motor with seal-in and overload protection",
              "expression": "[XIC(Start_PB),XIC(Motor_Run)] XIO(Stop_PB) XIO(Motor_OL) OTE(Motor_Run)"
            }
          ],
          "explanation": "This implements three-wire motor control...",
          "warnings": ["Add emergency stop interlock for safety"],
          "tags_needed": [
            {"name": "Start_PB", "type": "BOOL", "description": "Start pushbutton input"},
            {"name": "Motor_Run", "type": "BOOL", "description": "Motor run output coil"}
          ]
        }
        """

        if !existingTags.isEmpty {
            let tagList = existingTags.prefix(100).map { "\($0.name): \($0.dataType.displayName)" }.joined(separator: "\n")
            prompt += "\n\nEXISTING TAGS IN PROJECT:\n\(tagList)\n\nPrefer using existing tags when appropriate."
        }

        if let ctx = routineContext {
            prompt += "\n\nCURRENT ROUTINE CONTEXT:\n\(ctx)"
        }

        return prompt
    }

    private func buildExplainSystemPrompt() -> String {
        """
        You are an expert Allen-Bradley PLC programmer. Explain ladder logic in clear, plain English that a controls engineer would understand.

        When explaining:
        1. Start with a one-line summary of what the logic does
        2. Explain each rung's purpose and behavior
        3. Describe the scan-cycle behavior (how the logic evaluates each scan)
        4. Note any timing considerations (timers, one-shots)
        5. Highlight safety-relevant aspects
        6. Use industry terminology (seal-in circuit, interlock, permissive, etc.)

        INSTRUCTION REFERENCE:
        - XIC(tag): Examine if Closed — passes power if tag is TRUE (1)
        - XIO(tag): Examine if Open — passes power if tag is FALSE (0)
        - OTE(tag): Output Energize — sets tag TRUE when rung is true, FALSE when false
        - OTL(tag): Output Latch — sets tag TRUE when rung is true, stays latched
        - OTU(tag): Output Unlatch — sets tag FALSE when rung is true
        - TON(timer,preset,accum): Timer On Delay — timer.DN goes TRUE after preset ms
        - CTU(counter,preset,accum): Count Up — increments on false-to-true transition

        Be concise but thorough. Use bullet points for clarity.
        """
    }

    private func buildSuggestSystemPrompt() -> String {
        """
        You are a senior Allen-Bradley PLC programming consultant reviewing ladder logic for improvements.

        Review categories:
        1. SAFETY: Missing interlocks, race conditions, unsafe state transitions, missing E-stop logic
        2. PERFORMANCE: Redundant instructions, unnecessary evaluations, branch optimization
        3. BEST PRACTICE: Naming conventions, documentation, rung comments, tag descriptions
        4. SIMPLIFICATION: Logic that can be reduced, combined, or restructured

        For each suggestion:
        - State the category
        - Describe the issue clearly
        - Explain why it matters
        - Provide the corrected/improved rung expression if applicable

        Prioritize safety suggestions first. Be specific and actionable.
        """
    }

    private func buildChatSystemPrompt(context: String?) -> String {
        var prompt = """
        You are an AI assistant embedded in a macOS PLC IDE for Allen-Bradley ControlLogix/CompactLogix.
        You help controls engineers with ladder logic programming, debugging, and best practices.

        You can help with:
        - Ladder logic concepts and instruction usage
        - Tag naming conventions and data types
        - Common control patterns (motor control, sequencing, interlocks)
        - Troubleshooting PLC behavior
        - EtherNet/IP communication questions
        - Studio 5000 / RSLogix 5000 interoperability

        Be concise and practical. Use industry terminology.
        """

        if let ctx = context {
            prompt += "\n\nCurrent project context:\n\(ctx)"
        }

        return prompt
    }

    // MARK: - Response Parsing

    private func parseGenerationResponse(_ response: String) -> AIGeneratedRungs? {
        // Try to extract JSON from the response
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            return nil
        }

        let jsonStr = String(response[jsonStart...jsonEnd])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let rungArray = json["rungs"] as? [[String: Any]] else {
            return nil
        }

        var rungs: [Rung] = []
        for (i, rungDict) in rungArray.enumerated() {
            let comment = rungDict["comment"] as? String ?? ""
            let expression = rungDict["expression"] as? String ?? ""

            // Parse the rung expression into a RungElement using the L5K rung parser
            let element = RungExpressionParser.parse(expression)

            let rung = Rung(
                id: UUID().uuidString,
                number: UInt32(i),
                element: element,
                comment: comment,
                editable: true
            )
            rungs.append(rung)
        }

        let explanation = json["explanation"] as? String ?? "Generated \(rungs.count) rungs."
        let warnings = json["warnings"] as? [String] ?? []

        return AIGeneratedRungs(
            rungs: rungs,
            explanation: explanation,
            warnings: warnings,
            confidence: 0.85
        )
    }

    private func parseSuggestions(_ response: String) -> [AISuggestion] {
        // Parse suggestions from free-text response into structured form
        var suggestions: [AISuggestion] = []

        let lines = response.components(separatedBy: "\n")
        var currentCategory: AISuggestion.SuggestionCategory = .bestPractice
        var currentTitle = ""
        var currentDescription = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if upper.contains("SAFETY") && (upper.hasPrefix("#") || upper.hasPrefix("**") || upper.hasPrefix("1.")) {
                flushSuggestion(&suggestions, currentCategory, currentTitle, currentDescription)
                currentCategory = .safety
                currentTitle = ""
                currentDescription = ""
            } else if upper.contains("PERFORMANCE") && (upper.hasPrefix("#") || upper.hasPrefix("**") || upper.hasPrefix("2.")) {
                flushSuggestion(&suggestions, currentCategory, currentTitle, currentDescription)
                currentCategory = .performance
                currentTitle = ""
                currentDescription = ""
            } else if upper.contains("BEST PRACTICE") && (upper.hasPrefix("#") || upper.hasPrefix("**") || upper.hasPrefix("3.")) {
                flushSuggestion(&suggestions, currentCategory, currentTitle, currentDescription)
                currentCategory = .bestPractice
                currentTitle = ""
                currentDescription = ""
            } else if upper.contains("SIMPLIFICATION") && (upper.hasPrefix("#") || upper.hasPrefix("**") || upper.hasPrefix("4.")) {
                flushSuggestion(&suggestions, currentCategory, currentTitle, currentDescription)
                currentCategory = .simplification
                currentTitle = ""
                currentDescription = ""
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                flushSuggestion(&suggestions, currentCategory, currentTitle, currentDescription)
                currentTitle = String(trimmed.dropFirst(2))
                currentDescription = ""
            } else if !trimmed.isEmpty {
                if currentTitle.isEmpty {
                    currentTitle = trimmed
                } else {
                    currentDescription += (currentDescription.isEmpty ? "" : " ") + trimmed
                }
            }
        }
        flushSuggestion(&suggestions, currentCategory, currentTitle, currentDescription)

        return suggestions
    }

    private func flushSuggestion(_ suggestions: inout [AISuggestion], _ category: AISuggestion.SuggestionCategory, _ title: String, _ description: String) {
        guard !title.isEmpty else { return }
        suggestions.append(AISuggestion(
            category: category,
            title: title,
            description: description,
            suggestedRungs: nil
        ))
    }

    // MARK: - Fallback Pattern Library (no API key needed)

    private func generateFallbackResponse(system: String, user: String) -> String {
        let lower = user.lowercased()

        // Generate ladder logic
        if lower.contains("motor") && (lower.contains("start") || lower.contains("control")) {
            return """
            {
              "rungs": [
                {
                  "comment": "Motor start/stop with seal-in circuit and overload protection",
                  "expression": "[XIC(Start_PB),XIC(Motor_Run)] XIO(Stop_PB) XIO(Motor_OL) OTE(Motor_Run)"
                },
                {
                  "comment": "Motor running indicator",
                  "expression": "XIC(Motor_Run) OTE(Motor_Running_PL)"
                }
              ],
              "explanation": "Three-wire motor control circuit with seal-in. The Start pushbutton or the Motor_Run seal-in contact passes power through the normally-closed Stop button and overload contact to energize the motor output. A pilot light indicates motor running status.",
              "warnings": ["Add emergency stop (E-Stop) interlock before the OTE", "Verify Motor_OL is wired as normally-closed (NC) for fail-safe operation", "Consider adding a motor starter auxiliary contact for feedback"],
              "tags_needed": [
                {"name": "Start_PB", "type": "BOOL", "description": "Start pushbutton input (NO)"},
                {"name": "Stop_PB", "type": "BOOL", "description": "Stop pushbutton input (NC, wired NO in PLC)"},
                {"name": "Motor_OL", "type": "BOOL", "description": "Motor overload relay contact (NC)"},
                {"name": "Motor_Run", "type": "BOOL", "description": "Motor contactor output"},
                {"name": "Motor_Running_PL", "type": "BOOL", "description": "Motor running pilot light"}
              ]
            }
            """
        }

        if lower.contains("timer") || lower.contains("delay") {
            return """
            {
              "rungs": [
                {
                  "comment": "Start delay timer when condition is true",
                  "expression": "XIC(Start_Condition) TON(Delay_Timer,5000,0)"
                },
                {
                  "comment": "Activate output after timer completes",
                  "expression": "XIC(Delay_Timer.DN) OTE(Delayed_Output)"
                }
              ],
              "explanation": "Timer On Delay (TON) pattern. When Start_Condition is true, the timer begins accumulating. After 5000ms (5 seconds), the timer's .DN (Done) bit is set, energizing the Delayed_Output.",
              "warnings": ["Adjust the preset value (5000ms) to match your process requirements", "TON resets when the input goes false — use RTO if you need retentive timing"],
              "tags_needed": [
                {"name": "Start_Condition", "type": "BOOL", "description": "Condition that starts the timer"},
                {"name": "Delay_Timer", "type": "TIMER", "description": "5-second on-delay timer"},
                {"name": "Delayed_Output", "type": "BOOL", "description": "Output activated after delay"}
              ]
            }
            """
        }

        if lower.contains("counter") || lower.contains("count") {
            return """
            {
              "rungs": [
                {
                  "comment": "Count parts passing sensor",
                  "expression": "XIC(Part_Sensor) CTU(Part_Counter,100,0)"
                },
                {
                  "comment": "Batch complete when count reaches preset",
                  "expression": "XIC(Part_Counter.DN) OTE(Batch_Complete)"
                },
                {
                  "comment": "Reset counter on operator acknowledgment",
                  "expression": "XIC(Reset_PB) RES(Part_Counter)"
                }
              ],
              "explanation": "Count Up (CTU) pattern for batch counting. Each false-to-true transition of Part_Sensor increments the counter. When the accumulated value reaches the preset (100), the .DN bit is set. The operator can reset the counter with Reset_PB.",
              "warnings": ["CTU counts on rising edge only — ensure sensor signal is clean (debounced)", "Consider adding a missed-part detection timer"],
              "tags_needed": [
                {"name": "Part_Sensor", "type": "BOOL", "description": "Part detection sensor input"},
                {"name": "Part_Counter", "type": "COUNTER", "description": "Batch part counter (preset=100)"},
                {"name": "Batch_Complete", "type": "BOOL", "description": "Batch complete indicator"},
                {"name": "Reset_PB", "type": "BOOL", "description": "Counter reset pushbutton"}
              ]
            }
            """
        }

        if lower.contains("conveyor") || lower.contains("sequence") {
            return """
            {
              "rungs": [
                {
                  "comment": "Step 1: Start conveyor when start button pressed and system ready",
                  "expression": "XIC(Start_PB) XIC(System_Ready) XIO(E_Stop) OTL(Conv_Run)"
                },
                {
                  "comment": "Step 2: Stop conveyor on stop button or E-Stop",
                  "expression": "[XIC(Stop_PB),XIC(E_Stop)] OTU(Conv_Run)"
                },
                {
                  "comment": "Jam detection: stop if product sensor stays active too long",
                  "expression": "XIC(Product_Sensor) XIC(Conv_Run) TON(Jam_Timer,10000,0)"
                },
                {
                  "comment": "Set jam fault and stop conveyor",
                  "expression": "XIC(Jam_Timer.DN) OTL(Jam_Fault) OTU(Conv_Run)"
                },
                {
                  "comment": "Clear jam fault after operator reset",
                  "expression": "XIC(Fault_Reset_PB) XIO(Product_Sensor) OTU(Jam_Fault)"
                }
              ],
              "explanation": "Conveyor control with jam detection. The conveyor starts when the start button is pressed with system ready and no E-Stop. A jam detection timer monitors the product sensor — if a product is detected for more than 10 seconds continuously, a jam fault is raised and the conveyor stops. The operator can reset the fault once the jam is cleared.",
              "warnings": ["E-Stop should be hardwired in addition to software interlock", "Add motor overload protection", "Consider adding a speed feedback sensor for conveyor monitoring"],
              "tags_needed": [
                {"name": "Start_PB", "type": "BOOL", "description": "Conveyor start pushbutton"},
                {"name": "Stop_PB", "type": "BOOL", "description": "Conveyor stop pushbutton"},
                {"name": "E_Stop", "type": "BOOL", "description": "Emergency stop (NC contact)"},
                {"name": "System_Ready", "type": "BOOL", "description": "System ready permissive"},
                {"name": "Conv_Run", "type": "BOOL", "description": "Conveyor run output"},
                {"name": "Product_Sensor", "type": "BOOL", "description": "Product presence sensor"},
                {"name": "Jam_Timer", "type": "TIMER", "description": "Jam detection timer (10s)"},
                {"name": "Jam_Fault", "type": "BOOL", "description": "Jam fault latch"},
                {"name": "Fault_Reset_PB", "type": "BOOL", "description": "Fault reset pushbutton"}
              ]
            }
            """
        }

        // Explain mode
        if lower.contains("explain") || system.contains("Explain ladder logic") {
            return analyzeRungsFromText(user)
        }

        // Suggest mode
        if lower.contains("suggest") || lower.contains("improve") || system.contains("reviewing ladder logic") {
            return generateSuggestionsFromText(user)
        }

        // General chat fallback
        return """
        I can help you with Allen-Bradley ladder logic programming. Try asking me to:

        - **Generate logic**: "Create a motor start/stop circuit"
        - **Generate timers**: "Add a 5-second delay before activating the output"
        - **Generate counters**: "Count parts and stop at 100"
        - **Conveyor control**: "Create conveyor control with jam detection"

        You can also select rungs in the ladder editor and ask me to explain them or suggest improvements.

        For full AI capabilities, configure your Anthropic API key in Settings.
        """
    }

    private func analyzeRungsFromText(_ text: String) -> String {
        // Basic pattern-matching explanation
        var explanation = ""

        if text.contains("XIC") && text.contains("OTE") {
            explanation += "This logic uses Examine If Closed (XIC) contacts to check input conditions and Output Energize (OTE) coils to control outputs.\n\n"
        }

        if text.contains("OTL") || text.contains("OTU") {
            explanation += "The logic uses latch (OTL) and unlatch (OTU) instructions, which maintain their state even when the rung goes false. This is common in start/stop circuits.\n\n"
        }

        if text.contains("TON") {
            explanation += "A Timer On Delay (TON) is used. The timer accumulates when its rung is true and resets when false. The .DN bit sets when accumulator reaches the preset.\n\n"
        }

        if text.contains("CTU") {
            explanation += "A Count Up (CTU) instruction increments on each false-to-true transition of the rung. The .DN bit sets when the accumulator reaches the preset value.\n\n"
        }

        if text.contains("[") && text.contains(",") {
            explanation += "Parallel branches (OR logic) are used — the output is energized if ANY branch has power flow.\n\n"
        }

        if explanation.isEmpty {
            explanation = "This ladder logic evaluates conditions from left to right, with power flowing through contacts (XIC/XIO) to output instructions (OTE/OTL/OTU). Each rung is evaluated every scan cycle.\n\n"
        }

        explanation += "**Safety Note:** Always verify logic behavior in simulation before deploying to hardware."
        return explanation
    }

    private func generateSuggestionsFromText(_ text: String) -> String {
        var suggestions = "## Suggestions\n\n"

        if text.contains("OTE") && !text.contains("XIO(E_Stop)") && !text.contains("XIO(EStop)") {
            suggestions += "### Safety\n- **Add emergency stop interlock**: Output coils controlling motors or actuators should include an E-Stop contact (XIO) for safety compliance.\n\n"
        }

        if text.contains("OTL") && !text.contains("OTU") {
            suggestions += "### Safety\n- **Missing unlatch**: OTL (latch) instructions found without corresponding OTU (unlatch). Ensure every latched output has a defined unlatch condition.\n\n"
        }

        if !text.contains("//") && !text.contains("comment") {
            suggestions += "### Best Practice\n- **Add rung comments**: Document the purpose of each rung for maintenance and troubleshooting.\n\n"
        }

        suggestions += "### Best Practice\n- **Tag naming**: Use descriptive names following PascalCase_With_Underscores convention (e.g., Motor1_Run, Conv_Speed_SP).\n"

        return suggestions
    }
}

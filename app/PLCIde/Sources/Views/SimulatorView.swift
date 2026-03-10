import SwiftUI

/// Local ladder logic simulator UI.
/// Runs the project's ladder logic offline with a virtual I/O table.
struct SimulatorView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @StateObject private var simState = SimulatorState()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "play.circle")
                    .foregroundColor(simState.isRunning ? .green : .secondary)
                Text("Simulator")
                    .font(.headline)

                Spacer()

                // Scan rate
                Picker("Rate", selection: $simState.scanRateMs) {
                    Text("10ms").tag(10)
                    Text("50ms").tag(50)
                    Text("100ms").tag(100)
                    Text("500ms").tag(500)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                // Controls
                Button {
                    if simState.isRunning {
                        simState.stop()
                    } else {
                        simState.start(project: projectManager.project,
                                      programName: currentProgramName,
                                      routineName: currentRoutineName)
                    }
                } label: {
                    Image(systemName: simState.isRunning ? "stop.fill" : "play.fill")
                }
                .help(simState.isRunning ? "Stop simulation" : "Start simulation")

                Button {
                    simState.stepOnce(project: projectManager.project,
                                     programName: currentProgramName,
                                     routineName: currentRoutineName)
                } label: {
                    Image(systemName: "forward.frame.fill")
                }
                .help("Step one scan")
                .disabled(simState.isRunning)

                Button {
                    simState.reset(project: projectManager.project)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset all tags")

                Text("Scan: \(simState.scanCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HSplitView {
                // Left: Ladder canvas with energized highlights
                if !projectManager.selectedRoutineRungs.isEmpty {
                    LadderCanvasView(
                        rungs: projectManager.selectedRoutineRungs,
                        energizedRungs: simState.energizedRungs
                    )
                } else {
                    Text("Select a routine to simulate")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                }

                // Right: Watch window (tag values)
                WatchWindowView(simState: simState)
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
            }
        }
    }

    private var currentProgramName: String {
        if case .routine(let prog, _) = projectManager.selection {
            return prog
        }
        return ""
    }

    private var currentRoutineName: String {
        if case .routine(_, let routine) = projectManager.selection {
            return routine
        }
        return ""
    }
}

/// Watch window — displays tag values during simulation
struct WatchWindowView: View {
    @ObservedObject var simState: SimulatorState

    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Watch")
                    .font(.headline)
                Spacer()
                Text("\(filteredTags.count) tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Filter
            TextField("Filter tags...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            Divider()

            // Tag value list
            List {
                ForEach(filteredTags, id: \.name) { tag in
                    HStack {
                        // Editable toggle for BOOL tags
                        if case .boolValue(let val) = tag.displayValue {
                            Toggle("", isOn: Binding(
                                get: { val },
                                set: { newVal in
                                    simState.forceTag(name: tag.name, boolValue: newVal)
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                        }

                        Text(tag.name)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Spacer()

                        Text(tag.valueString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(tag.changed ? .orange : .secondary)
                    }
                    .padding(.vertical, 1)
                }
            }
            .listStyle(.plain)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filteredTags: [WatchTag] {
        if filterText.isEmpty {
            return simState.watchTags
        }
        let query = filterText.lowercased()
        return simState.watchTags.filter {
            $0.name.lowercased().contains(query)
        }
    }
}

/// Display-friendly tag for the watch window
struct WatchTag: Identifiable {
    var id: String { name }
    let name: String
    let valueString: String
    let displayValue: DisplayValue
    let changed: Bool

    enum DisplayValue {
        case boolValue(Bool)
        case intValue(Int64)
        case realValue(Double)
    }
}

/// Simulator state manager — drives the simulation loop
class SimulatorState: ObservableObject {
    @Published var isRunning = false
    @Published var scanCount: Int = 0
    @Published var scanRateMs: Int = 100
    @Published var energizedRungs: Set<UInt32> = []
    @Published var watchTags: [WatchTag] = []

    private var tagValues: [String: TagValueWrapper] = [:]
    private var prevTagValues: [String: TagValueWrapper] = [:]
    private var timer: Timer?

    struct TagValueWrapper {
        var boolVal: Bool = false
        var intVal: Int64 = 0
        var realVal: Double = 0
        var isBool: Bool = true
    }

    func start(project: PlcProject?, programName: String, routineName: String) {
        guard project != nil else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: Double(scanRateMs) / 1000.0, repeats: true) { [weak self] _ in
            self?.stepOnce(project: project, programName: programName, routineName: routineName)
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset(project: PlcProject?) {
        stop()
        scanCount = 0
        energizedRungs = []
        tagValues.removeAll()
        prevTagValues.removeAll()

        // Initialize tags from project
        guard let project = project else { return }
        for tag in project.tagDatabase.tags {
            let name = tag.name
            switch tag.dataType {
            case .bool_:
                tagValues[name] = TagValueWrapper(boolVal: false, isBool: true)
            case .timer:
                tagValues["\(name).EN"] = TagValueWrapper(boolVal: false, isBool: true)
                tagValues["\(name).TT"] = TagValueWrapper(boolVal: false, isBool: true)
                tagValues["\(name).DN"] = TagValueWrapper(boolVal: false, isBool: true)
                tagValues["\(name).PRE"] = TagValueWrapper(intVal: 0, isBool: false)
                tagValues["\(name).ACC"] = TagValueWrapper(intVal: 0, isBool: false)
                tagValues[name] = TagValueWrapper(intVal: 0, isBool: false)
            case .counter:
                tagValues["\(name).CU"] = TagValueWrapper(boolVal: false, isBool: true)
                tagValues["\(name).DN"] = TagValueWrapper(boolVal: false, isBool: true)
                tagValues["\(name).PRE"] = TagValueWrapper(intVal: 0, isBool: false)
                tagValues["\(name).ACC"] = TagValueWrapper(intVal: 0, isBool: false)
                tagValues[name] = TagValueWrapper(intVal: 0, isBool: false)
            default:
                tagValues[name] = TagValueWrapper(intVal: 0, isBool: false)
            }
        }
        updateWatchTags()
    }

    func stepOnce(project: PlcProject?, programName: String, routineName: String) {
        guard let project = project else { return }
        guard let routine = project.findRoutine(programName: programName, routineName: routineName) else { return }

        prevTagValues = tagValues

        // Simple scan: evaluate each rung
        var energized: Set<UInt32> = []
        for rung in routine.rungs {
            let power = evaluateElement(rung.element, powerIn: true)
            if power {
                energized.insert(rung.number)
            }
        }

        scanCount += 1
        energizedRungs = energized
        updateWatchTags()
    }

    func forceTag(name: String, boolValue: Bool) {
        tagValues[name] = TagValueWrapper(boolVal: boolValue, isBool: true)
        updateWatchTags()
    }

    // MARK: - Evaluation (simplified client-side simulator)

    private func evaluateElement(_ element: RungElement, powerIn: Bool) -> Bool {
        switch element {
        case .instruction(let inst):
            return evaluateInstruction(inst, powerIn: powerIn)
        case .series(let elements):
            var power = powerIn
            for el in elements {
                power = evaluateElement(el, powerIn: power)
            }
            return power
        case .parallel(let branches):
            var anyPower = false
            for branch in branches {
                if evaluateElement(branch, powerIn: powerIn) {
                    anyPower = true
                }
            }
            return anyPower
        }
    }

    private func evaluateInstruction(_ inst: Instruction, powerIn: Bool) -> Bool {
        let it = inst.instructionType

        switch it {
        case .xic:
            guard powerIn else { return false }
            let tag = inst.operands.first?.displayString ?? ""
            return getTagBool(tag)
        case .xio:
            guard powerIn else { return false }
            let tag = inst.operands.first?.displayString ?? ""
            return !getTagBool(tag)
        case .ote:
            let tag = inst.operands.first?.displayString ?? ""
            setTagBool(tag, value: powerIn)
            return powerIn
        case .otl:
            let tag = inst.operands.first?.displayString ?? ""
            if powerIn { setTagBool(tag, value: true) }
            return powerIn
        case .otu:
            let tag = inst.operands.first?.displayString ?? ""
            if powerIn { setTagBool(tag, value: false) }
            return powerIn
        case .ton:
            let tag = inst.operands.first?.displayString ?? ""
            let preset = getOperandInt(inst.operands, index: 1)
            if powerIn {
                var acc = getTagInt("\(tag).ACC")
                acc += Int64(scanRateMs)
                setTagInt("\(tag).ACC", value: acc)
                setTagBool("\(tag).EN", value: true)
                let done = acc >= preset
                setTagBool("\(tag).DN", value: done)
                setTagBool("\(tag).TT", value: !done)
            } else {
                setTagInt("\(tag).ACC", value: 0)
                setTagBool("\(tag).EN", value: false)
                setTagBool("\(tag).DN", value: false)
                setTagBool("\(tag).TT", value: false)
            }
            return powerIn
        case .ctu:
            let tag = inst.operands.first?.displayString ?? ""
            let preset = getOperandInt(inst.operands, index: 1)
            let prevPower = prevTagValues["\(tag)._prev"]?.boolVal ?? false
            if powerIn && !prevPower {
                var acc = getTagInt("\(tag).ACC")
                acc += 1
                setTagInt("\(tag).ACC", value: acc)
                setTagBool("\(tag).DN", value: acc >= preset)
            }
            tagValues["\(tag)._prev"] = TagValueWrapper(boolVal: powerIn, isBool: true)
            return powerIn
        case .mov:
            if powerIn && inst.operands.count >= 2 {
                let val = getOperandInt(inst.operands, index: 0)
                let dest = inst.operands[1].displayString
                setTagInt(dest, value: val)
            }
            return powerIn
        case .add:
            if powerIn && inst.operands.count >= 3 {
                let a = getOperandInt(inst.operands, index: 0)
                let b = getOperandInt(inst.operands, index: 1)
                let dest = inst.operands[2].displayString
                setTagInt(dest, value: a + b)
            }
            return powerIn
        case .sub:
            if powerIn && inst.operands.count >= 3 {
                let a = getOperandInt(inst.operands, index: 0)
                let b = getOperandInt(inst.operands, index: 1)
                let dest = inst.operands[2].displayString
                setTagInt(dest, value: a - b)
            }
            return powerIn
        case .mul:
            if powerIn && inst.operands.count >= 3 {
                let a = getOperandInt(inst.operands, index: 0)
                let b = getOperandInt(inst.operands, index: 1)
                let dest = inst.operands[2].displayString
                setTagInt(dest, value: a * b)
            }
            return powerIn
        case .equ:
            guard powerIn else { return false }
            let a = getOperandInt(inst.operands, index: 0)
            let b = getOperandInt(inst.operands, index: 1)
            return a == b
        case .neq:
            guard powerIn else { return false }
            let a = getOperandInt(inst.operands, index: 0)
            let b = getOperandInt(inst.operands, index: 1)
            return a != b
        case .grt:
            guard powerIn else { return false }
            let a = getOperandInt(inst.operands, index: 0)
            let b = getOperandInt(inst.operands, index: 1)
            return a > b
        case .les:
            guard powerIn else { return false }
            let a = getOperandInt(inst.operands, index: 0)
            let b = getOperandInt(inst.operands, index: 1)
            return a < b
        case .res:
            if powerIn {
                let tag = inst.operands.first?.displayString ?? ""
                setTagInt("\(tag).ACC", value: 0)
                setTagBool("\(tag).DN", value: false)
                setTagBool("\(tag).EN", value: false)
            }
            return powerIn
        default:
            return powerIn
        }
    }

    // MARK: - Tag helpers

    private func getTagBool(_ name: String) -> Bool {
        tagValues[name]?.boolVal ?? false
    }

    private func setTagBool(_ name: String, value: Bool) {
        if tagValues[name] != nil {
            tagValues[name]!.boolVal = value
            tagValues[name]!.isBool = true
        } else {
            tagValues[name] = TagValueWrapper(boolVal: value, isBool: true)
        }
    }

    private func getTagInt(_ name: String) -> Int64 {
        tagValues[name]?.intVal ?? 0
    }

    private func setTagInt(_ name: String, value: Int64) {
        if tagValues[name] != nil {
            tagValues[name]!.intVal = value
            tagValues[name]!.isBool = false
        } else {
            tagValues[name] = TagValueWrapper(intVal: value, isBool: false)
        }
    }

    private func getOperandInt(_ operands: [Operand], index: Int) -> Int64 {
        guard index < operands.count else { return 0 }
        switch operands[index] {
        case .intLiteral(let v): return v
        case .tagRef(let name): return getTagInt(name)
        case .realLiteral(let v): return Int64(v)
        }
    }

    private func updateWatchTags() {
        watchTags = tagValues
            .filter { !$0.key.hasSuffix("._prev") }
            .sorted { $0.key < $1.key }
            .map { (name, wrapper) in
                let changed = prevTagValues[name]?.boolVal != wrapper.boolVal ||
                              prevTagValues[name]?.intVal != wrapper.intVal
                if wrapper.isBool {
                    return WatchTag(name: name, valueString: wrapper.boolVal ? "TRUE" : "FALSE",
                                   displayValue: .boolValue(wrapper.boolVal), changed: changed)
                } else {
                    return WatchTag(name: name, valueString: "\(wrapper.intVal)",
                                   displayValue: .intValue(wrapper.intVal), changed: changed)
                }
            }
    }
}

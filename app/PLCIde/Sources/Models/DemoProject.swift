import Foundation

/// Generates a realistic demo PLC project for development and testing.
/// This represents a typical conveyor line control system.
enum DemoProject {
    static func create() -> PlcProject {
        // Tags
        let tags: [Tag] = [
            Tag(id: UUID().uuidString, name: "Start_PB", dataType: .bool_, scope: .controller,
                description: "Start pushbutton", initialValue: "0", aliasFor: nil, externalAccess: .readWrite),
            Tag(id: UUID().uuidString, name: "Stop_PB", dataType: .bool_, scope: .controller,
                description: "Stop pushbutton (NC)", initialValue: "0", aliasFor: nil, externalAccess: .readWrite),
            Tag(id: UUID().uuidString, name: "Motor_Run", dataType: .bool_, scope: .controller,
                description: "Motor running status", initialValue: "0", aliasFor: nil, externalAccess: .readWrite),
            Tag(id: UUID().uuidString, name: "E_Stop", dataType: .bool_, scope: .controller,
                description: "Emergency stop (NC)", initialValue: "0", aliasFor: nil, externalAccess: .readOnly),
            Tag(id: UUID().uuidString, name: "Line_Speed", dataType: .dint, scope: .controller,
                description: "Conveyor line speed (RPM)", initialValue: "0", aliasFor: nil, externalAccess: .readWrite),
            Tag(id: UUID().uuidString, name: "Speed_Setpoint", dataType: .dint, scope: .controller,
                description: "Speed setpoint from HMI", initialValue: "1500", aliasFor: nil, externalAccess: .readWrite),
            Tag(id: UUID().uuidString, name: "Run_Delay", dataType: .timer, scope: .controller,
                description: "Motor start delay timer", initialValue: "", aliasFor: nil, externalAccess: .readWrite),
            Tag(id: UUID().uuidString, name: "Fault_Count", dataType: .counter, scope: .controller,
                description: "Accumulated fault count", initialValue: "", aliasFor: nil, externalAccess: .readOnly),
            Tag(id: UUID().uuidString, name: "Sensor_1", dataType: .bool_, scope: .controller,
                description: "Proximity sensor - entry", initialValue: "0", aliasFor: nil, externalAccess: .readOnly),
            Tag(id: UUID().uuidString, name: "Sensor_2", dataType: .bool_, scope: .controller,
                description: "Proximity sensor - exit", initialValue: "0", aliasFor: nil, externalAccess: .readOnly),
            Tag(id: UUID().uuidString, name: "Cycle_Timer", dataType: .timer, scope: .program(programName: "MainProgram"),
                description: "Production cycle timer", initialValue: "", aliasFor: nil, externalAccess: .readWrite),
            Tag(id: UUID().uuidString, name: "Part_Count", dataType: .counter, scope: .program(programName: "MainProgram"),
                description: "Parts produced counter", initialValue: "", aliasFor: nil, externalAccess: .readWrite),
        ]

        // Rungs for MainRoutine
        let rungs: [Rung] = [
            // Rung 0: Motor seal-in circuit
            Rung(id: UUID().uuidString, number: 0,
                 element: .series(elements: [
                    .parallel(branches: [
                        .instruction(instruction: Instruction(id: UUID().uuidString,
                            instructionType: .xic, operands: [.tagRef(name: "Start_PB")], comment: "")),
                        .instruction(instruction: Instruction(id: UUID().uuidString,
                            instructionType: .xic, operands: [.tagRef(name: "Motor_Run")], comment: "")),
                    ]),
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .xio, operands: [.tagRef(name: "E_Stop")], comment: "")),
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .otl, operands: [.tagRef(name: "Motor_Run")], comment: "")),
                 ]),
                 comment: "Motor seal-in circuit with E-Stop interlock",
                 editable: true),

            // Rung 1: Motor stop
            Rung(id: UUID().uuidString, number: 1,
                 element: .series(elements: [
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .xio, operands: [.tagRef(name: "Stop_PB")], comment: "")),
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .otu, operands: [.tagRef(name: "Motor_Run")], comment: "")),
                 ]),
                 comment: "Motor stop circuit",
                 editable: true),

            // Rung 2: Start delay timer
            Rung(id: UUID().uuidString, number: 2,
                 element: .series(elements: [
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .xic, operands: [.tagRef(name: "Motor_Run")], comment: "")),
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .ton, operands: [
                            .tagRef(name: "Run_Delay"),
                            .intLiteral(value: 5000),
                            .intLiteral(value: 0)
                        ], comment: "")),
                 ]),
                 comment: "Motor run delay timer (5 seconds)",
                 editable: true),

            // Rung 3: Speed compare and move
            Rung(id: UUID().uuidString, number: 3,
                 element: .series(elements: [
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .xic, operands: [.tagRef(name: "Run_Delay.DN")], comment: "")),
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .mov, operands: [
                            .tagRef(name: "Speed_Setpoint"),
                            .tagRef(name: "Line_Speed")
                        ], comment: "")),
                 ]),
                 comment: "After delay, apply speed setpoint",
                 editable: true),

            // Rung 4: Part counting
            Rung(id: UUID().uuidString, number: 4,
                 element: .series(elements: [
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .xic, operands: [.tagRef(name: "Sensor_2")], comment: "")),
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .ctu, operands: [
                            .tagRef(name: "Part_Count"),
                            .intLiteral(value: 99999),
                            .intLiteral(value: 0)
                        ], comment: "")),
                 ]),
                 comment: "Count parts at exit sensor",
                 editable: true),

            // Rung 5: Fault detection with parallel inputs
            Rung(id: UUID().uuidString, number: 5,
                 element: .series(elements: [
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .xic, operands: [.tagRef(name: "Motor_Run")], comment: "")),
                    .parallel(branches: [
                        .instruction(instruction: Instruction(id: UUID().uuidString,
                            instructionType: .xio, operands: [.tagRef(name: "Sensor_1")], comment: "")),
                        .instruction(instruction: Instruction(id: UUID().uuidString,
                            instructionType: .xio, operands: [.tagRef(name: "Sensor_2")], comment: "")),
                    ]),
                    .instruction(instruction: Instruction(id: UUID().uuidString,
                        instructionType: .ctu, operands: [
                            .tagRef(name: "Fault_Count"),
                            .intLiteral(value: 100),
                            .intLiteral(value: 0)
                        ], comment: "")),
                 ]),
                 comment: "Fault detection: motor running but no sensor activity",
                 editable: true),
        ]

        let mainRoutine = Routine(id: UUID().uuidString, name: "MainRoutine",
                                   description: "Main execution routine", rungs: rungs)
        let faultRoutine = Routine(id: UUID().uuidString, name: "FaultHandler",
                                    description: "Fault handling routine", rungs: [])

        let mainProgram = Program(id: UUID().uuidString, name: "MainProgram",
                                   description: "Main conveyor control program",
                                   mainRoutineName: "MainRoutine",
                                   faultRoutineName: "FaultHandler",
                                   routines: [mainRoutine, faultRoutine])

        let mainTask = Task(id: UUID().uuidString, name: "MainTask",
                            description: "Continuous scan task",
                            taskType: .continuous, priority: 10,
                            programs: [mainProgram])

        let controller = Controller(name: "ConveyorLine1",
                                     family: .compactLogix,
                                     catalogNumber: "1769-L33ER",
                                     firmwareVersion: "34.011",
                                     description: "Main conveyor line controller")

        return PlcProject(
            formatVersion: 1,
            id: UUID().uuidString,
            name: "ConveyorLine1",
            description: "Conveyor Line 1 — Main production line control",
            controller: controller,
            tasks: [mainTask],
            tagDatabase: TagDatabase(tags: tags),
            importedFrom: nil
        )
    }
}

import SwiftUI

/// Text-based ladder rung display — Phase 1 viewer before Phase 2 graphical canvas.
///
/// Displays rungs as formatted text with:
/// - Rung numbers and comments
/// - Neutral-text instruction representation
/// - Color-coded instruction types (inputs blue, outputs red, etc.)
struct RungListView: View {
    @EnvironmentObject var projectManager: ProjectManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if case .routine(let progName, let routName) = projectManager.selection {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(.orange)
                    Text("\(progName) / \(routName)")
                        .font(.headline)
                } else {
                    Text("Rungs")
                        .font(.headline)
                }
                Spacer()
                Text("\(projectManager.selectedRoutineRungs.count) rungs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Rung list
            if projectManager.selectedRoutineRungs.isEmpty {
                VStack {
                    Spacer()
                    Text("No rungs in this routine")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(projectManager.selectedRoutineRungs) { rung in
                            RungRowView(rung: rung)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// A single rung displayed as formatted text
struct RungRowView: View {
    let rung: Rung

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Rung number and comment
            HStack(alignment: .top) {
                Text("\(rung.number)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.tertiaryLabel)
                    .frame(width: 24, alignment: .trailing)

                if !rung.comment.isEmpty {
                    Text("// \(rung.comment)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(2)
                }
            }

            // Rung logic as visual representation
            HStack(alignment: .top, spacing: 0) {
                // Left power rail
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 3)
                    .padding(.trailing, 8)

                // Instruction elements
                RungElementView(element: rung.element)

                Spacer(minLength: 8)

                // Right power rail
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 3)
            }
            .frame(minHeight: 36)
            .padding(.leading, 28)

            // Neutral text representation
            Text(rung.element.neutralText + " ;")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.tertiaryLabel)
                .padding(.leading, 36)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}

/// Renders a rung element tree as a horizontal chain of instruction badges
struct RungElementView: View {
    let element: RungElement

    var body: some View {
        switch element {
        case .instruction(let inst):
            InstructionBadge(instruction: inst)

        case .series(let elements):
            HStack(spacing: 2) {
                ForEach(Array(elements.enumerated()), id: \.offset) { _, el in
                    // Wire between elements
                    Rectangle()
                        .fill(Color(nsColor: .labelColor))
                        .frame(width: 12, height: 2)
                    RungElementView(element: el)
                }
            }

        case .parallel(let branches):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(branches.enumerated()), id: \.offset) { index, branch in
                    HStack(spacing: 2) {
                        // Branch indicator
                        Text(index == 0 ? "+" : "|")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        RungElementView(element: branch)
                    }
                }
            }
            .padding(.vertical, 2)
            .overlay(
                Rectangle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    .padding(.horizontal, -2)
            )
        }
    }
}

/// Visual badge for a single instruction
struct InstructionBadge: View {
    let instruction: Instruction

    var body: some View {
        VStack(spacing: 1) {
            // Mnemonic
            Text(instruction.instructionType.mnemonic)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(mnemonicColor)

            // Operands
            HStack(spacing: 2) {
                ForEach(Array(instruction.operands.enumerated()), id: \.offset) { _, op in
                    Text(op.displayString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeBackground)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(mnemonicColor.opacity(0.5), lineWidth: 1)
        )
    }

    private var mnemonicColor: Color {
        let it = instruction.instructionType
        if it.isInput {
            return .blue
        } else if it.isOutput {
            return .red
        }
        switch it {
        case .ton, .tof, .rto:
            return .orange
        case .ctu, .ctd, .res:
            return .purple
        case .add, .sub, .mul, .div, .mod_, .neg, .mov, .cop:
            return .teal
        case .jmp, .lbl, .jsr, .ret, .sbr:
            return .brown
        default:
            return .gray
        }
    }

    private var badgeBackground: Color {
        mnemonicColor.opacity(0.08)
    }
}

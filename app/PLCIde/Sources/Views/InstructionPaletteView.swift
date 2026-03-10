import SwiftUI

/// Instruction palette — shows available ladder instructions grouped by category.
/// Users drag instructions from here onto the canvas (Phase 2 editing).
struct InstructionPaletteView: View {
    @EnvironmentObject var projectManager: ProjectManager

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search instructions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredCategories, id: \.name) { category in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)

                            FlowLayout(spacing: 4) {
                                ForEach(category.instructions, id: \.mnemonic) { info in
                                    PaletteItem(info: info)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 200, maxWidth: 300)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var filteredCategories: [InstructionCategory] {
        if searchText.isEmpty {
            return InstructionCategory.all
        }
        let query = searchText.uppercased()
        return InstructionCategory.all.compactMap { cat in
            let filtered = cat.instructions.filter {
                $0.mnemonic.contains(query) || $0.name.uppercased().contains(query)
            }
            return filtered.isEmpty ? nil : InstructionCategory(name: cat.name, instructions: filtered)
        }
    }
}

/// A single instruction in the palette
struct PaletteItem: View {
    let info: InstructionInfo

    var body: some View {
        VStack(spacing: 1) {
            Text(info.mnemonic)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(info.color)
            Text(info.name)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 56, height: 36)
        .background(info.color.opacity(0.08))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(info.color.opacity(0.3), lineWidth: 0.5)
        )
        .help(info.description)
    }
}

/// Instruction metadata for palette display
struct InstructionInfo {
    let mnemonic: String
    let name: String
    let description: String
    let color: Color
}

/// Instruction categories
struct InstructionCategory {
    let name: String
    let instructions: [InstructionInfo]

    static let all: [InstructionCategory] = [
        InstructionCategory(name: "Bit", instructions: [
            InstructionInfo(mnemonic: "XIC", name: "Contact NO", description: "Examine If Closed — passes power when tag is true", color: .blue),
            InstructionInfo(mnemonic: "XIO", name: "Contact NC", description: "Examine If Open — passes power when tag is false", color: .blue),
            InstructionInfo(mnemonic: "OTE", name: "Coil", description: "Output Energize — sets tag to rung condition", color: .red),
            InstructionInfo(mnemonic: "OTL", name: "Latch", description: "Output Latch — sets tag true, stays true", color: .red),
            InstructionInfo(mnemonic: "OTU", name: "Unlatch", description: "Output Unlatch — sets tag false", color: .red),
            InstructionInfo(mnemonic: "ONS", name: "One-Shot", description: "One-Shot Rising — passes power for one scan", color: .blue),
        ]),
        InstructionCategory(name: "Timer", instructions: [
            InstructionInfo(mnemonic: "TON", name: "Timer On", description: "Timer On Delay — times while rung is true", color: .orange),
            InstructionInfo(mnemonic: "TOF", name: "Timer Off", description: "Timer Off Delay — times after rung goes false", color: .orange),
            InstructionInfo(mnemonic: "RTO", name: "Retentive", description: "Retentive Timer On — accumulates time, doesn't reset", color: .orange),
        ]),
        InstructionCategory(name: "Counter", instructions: [
            InstructionInfo(mnemonic: "CTU", name: "Count Up", description: "Count Up — increments on false-to-true transition", color: .purple),
            InstructionInfo(mnemonic: "CTD", name: "Count Down", description: "Count Down — decrements on false-to-true transition", color: .purple),
            InstructionInfo(mnemonic: "RES", name: "Reset", description: "Reset — clears timer or counter accumulator", color: .purple),
        ]),
        InstructionCategory(name: "Compare", instructions: [
            InstructionInfo(mnemonic: "EQU", name: "Equal", description: "Equal — passes power when A = B", color: .blue),
            InstructionInfo(mnemonic: "NEQ", name: "Not Equal", description: "Not Equal — passes power when A != B", color: .blue),
            InstructionInfo(mnemonic: "GRT", name: "Greater", description: "Greater Than — passes power when A > B", color: .blue),
            InstructionInfo(mnemonic: "GEQ", name: "Greater/Eq", description: "Greater Than or Equal — A >= B", color: .blue),
            InstructionInfo(mnemonic: "LES", name: "Less Than", description: "Less Than — passes power when A < B", color: .blue),
            InstructionInfo(mnemonic: "LEQ", name: "Less/Equal", description: "Less Than or Equal — A <= B", color: .blue),
        ]),
        InstructionCategory(name: "Math", instructions: [
            InstructionInfo(mnemonic: "ADD", name: "Add", description: "Add — Dest = A + B", color: .teal),
            InstructionInfo(mnemonic: "SUB", name: "Subtract", description: "Subtract — Dest = A - B", color: .teal),
            InstructionInfo(mnemonic: "MUL", name: "Multiply", description: "Multiply — Dest = A * B", color: .teal),
            InstructionInfo(mnemonic: "DIV", name: "Divide", description: "Divide — Dest = A / B", color: .teal),
            InstructionInfo(mnemonic: "MOD", name: "Modulo", description: "Modulo — Dest = A mod B", color: .teal),
            InstructionInfo(mnemonic: "NEG", name: "Negate", description: "Negate — Dest = -Source", color: .teal),
        ]),
        InstructionCategory(name: "Move", instructions: [
            InstructionInfo(mnemonic: "MOV", name: "Move", description: "Move — copies source to destination", color: .teal),
            InstructionInfo(mnemonic: "COP", name: "Copy", description: "Copy — copies block of data", color: .teal),
        ]),
        InstructionCategory(name: "Program", instructions: [
            InstructionInfo(mnemonic: "JMP", name: "Jump", description: "Jump to Label", color: .brown),
            InstructionInfo(mnemonic: "LBL", name: "Label", description: "Label — jump target", color: .brown),
            InstructionInfo(mnemonic: "JSR", name: "Subroutine", description: "Jump to Subroutine", color: .brown),
            InstructionInfo(mnemonic: "RET", name: "Return", description: "Return from Subroutine", color: .brown),
        ]),
    ]
}

/// Simple flow layout for instruction items
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x,
                                               y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

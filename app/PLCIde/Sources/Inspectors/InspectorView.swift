import SwiftUI

/// Right-side inspector panel — shows properties of selected element.
struct InspectorView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Properties (placeholder — populated when something is selected)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Tag Properties") {
                        VStack(alignment: .leading, spacing: 8) {
                            PropertyRow(label: "Name", value: "—")
                            PropertyRow(label: "Type", value: "—")
                            PropertyRow(label: "Scope", value: "—")
                            PropertyRow(label: "Value", value: "—")
                        }
                        .padding(4)
                    }

                    GroupBox("Instruction") {
                        VStack(alignment: .leading, spacing: 8) {
                            PropertyRow(label: "Type", value: "—")
                            PropertyRow(label: "Operands", value: "—")
                        }
                        .padding(4)
                    }

                    GroupBox("Rung Comment") {
                        TextEditor(text: .constant(""))
                            .frame(minHeight: 60)
                            .font(.system(.body, design: .monospaced))
                    }

                    Spacer()
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
    }
}

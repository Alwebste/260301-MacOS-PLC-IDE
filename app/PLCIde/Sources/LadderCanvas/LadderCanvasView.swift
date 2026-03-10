import SwiftUI
import AppKit

/// NSViewRepresentable wrapper for the AppKit-based ladder canvas.
///
/// Phase 2 will implement the full Core Graphics rendering here.
/// This file establishes the architecture: SwiftUI hosts an NSView,
/// which does all custom drawing via Core Graphics.
struct LadderCanvasView: NSViewRepresentable {
    // Phase 2: bind to routine data from plc_core

    func makeNSView(context: Context) -> LadderNSView {
        let view = LadderNSView()
        return view
    }

    func updateNSView(_ nsView: LadderNSView, context: Context) {
        nsView.needsDisplay = true
    }
}

/// The actual AppKit view that renders ladder logic using Core Graphics.
///
/// This is where all the ladder drawing happens in Phase 2:
/// - Power rails (left/right vertical lines)
/// - Horizontal rung wires
/// - Instruction symbols (contacts, coils, boxes)
/// - Branch rendering (parallel paths)
/// - Selection highlighting
/// - Drag-drop hit testing
class LadderNSView: NSView {
    // MARK: - Drawing Constants

    private let rungHeight: CGFloat = 80
    private let railWidth: CGFloat = 4
    private let railMargin: CGFloat = 40
    private let instructionWidth: CGFloat = 80
    private let instructionHeight: CGFloat = 40
    private let wireThickness: CGFloat = 2

    // Colors — will be configurable in Phase 6
    private let railColor = NSColor.systemGray
    private let wireColor = NSColor.labelColor
    private let contactColor = NSColor.systemBlue
    private let coilColor = NSColor.systemRed
    private let backgroundColor = NSColor.controlBackgroundColor

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        context.setFillColor(backgroundColor.cgColor)
        context.fill(dirtyRect)

        // Draw demo rungs to validate the rendering approach
        let rungCount = 5
        let totalHeight = CGFloat(rungCount) * rungHeight + railMargin * 2
        let canvasWidth = bounds.width

        // Left power rail
        context.setStrokeColor(railColor.cgColor)
        context.setLineWidth(railWidth)
        context.move(to: CGPoint(x: railMargin, y: railMargin))
        context.addLine(to: CGPoint(x: railMargin, y: totalHeight))
        context.strokePath()

        // Right power rail
        context.move(to: CGPoint(x: canvasWidth - railMargin, y: railMargin))
        context.addLine(to: CGPoint(x: canvasWidth - railMargin, y: totalHeight))
        context.strokePath()

        // Draw placeholder rungs
        for i in 0..<rungCount {
            let y = railMargin + CGFloat(i) * rungHeight + rungHeight / 2
            drawPlaceholderRung(context: context, rungNumber: i, y: y, canvasWidth: canvasWidth)
        }
    }

    private func drawPlaceholderRung(context: CGContext, rungNumber: Int, y: CGFloat, canvasWidth: CGFloat) {
        let leftRail = railMargin
        let rightRail = canvasWidth - railMargin

        // Horizontal wire
        context.setStrokeColor(wireColor.cgColor)
        context.setLineWidth(wireThickness)
        context.move(to: CGPoint(x: leftRail, y: y))
        context.addLine(to: CGPoint(x: rightRail, y: y))
        context.strokePath()

        // Draw placeholder contact symbol (two vertical lines)
        let contactX = leftRail + 100
        drawContact(context: context, x: contactX, y: y, label: "XIC")

        // Draw placeholder coil symbol (circle)
        let coilX = rightRail - 100
        drawCoil(context: context, x: coilX, y: y, label: "OTE")

        // Rung number
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let rungLabel = NSAttributedString(string: "\(rungNumber)", attributes: attrs)
        rungLabel.draw(at: CGPoint(x: 8, y: y - 6))
    }

    private func drawContact(context: CGContext, x: CGFloat, y: CGFloat, label: String) {
        let halfH: CGFloat = 12

        // Contact symbol: two vertical bars with gap
        context.setStrokeColor(contactColor.cgColor)
        context.setLineWidth(2)

        // Left bar
        context.move(to: CGPoint(x: x - 4, y: y - halfH))
        context.addLine(to: CGPoint(x: x - 4, y: y + halfH))
        context.strokePath()

        // Right bar
        context.move(to: CGPoint(x: x + 4, y: y - halfH))
        context.addLine(to: CGPoint(x: x + 4, y: y + halfH))
        context.strokePath()

        // Label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: contactColor,
        ]
        let text = NSAttributedString(string: label, attributes: attrs)
        text.draw(at: CGPoint(x: x - 10, y: y - halfH - 14))
    }

    private func drawCoil(context: CGContext, x: CGFloat, y: CGFloat, label: String) {
        let radius: CGFloat = 12

        // Coil symbol: circle
        context.setStrokeColor(coilColor.cgColor)
        context.setLineWidth(2)
        context.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                       width: radius * 2, height: radius * 2))
        context.strokePath()

        // Label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: coilColor,
        ]
        let text = NSAttributedString(string: label, attributes: attrs)
        text.draw(at: CGPoint(x: x - 10, y: y - radius - 14))
    }

    // MARK: - Mouse Handling (Phase 2)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Phase 2: hit-test instructions, select elements
        print("[LadderCanvas] Click at: \(point)")
    }
}

import SwiftUI
import AppKit

/// NSViewRepresentable wrapper for the AppKit-based ladder canvas.
/// Renders real rung data from the project using Core Graphics.
struct LadderCanvasView: NSViewRepresentable {
    let rungs: [Rung]
    let energizedRungs: Set<UInt32>
    var onRungClicked: ((Int) -> Void)?
    var onInstructionClicked: ((Int, String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let ladderView = LadderNSView()
        ladderView.rungs = rungs
        ladderView.energizedRungs = energizedRungs
        ladderView.onRungClicked = onRungClicked
        ladderView.onInstructionClicked = onInstructionClicked

        scrollView.documentView = ladderView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let ladderView = scrollView.documentView as? LadderNSView else { return }
        ladderView.rungs = rungs
        ladderView.energizedRungs = energizedRungs
        ladderView.onRungClicked = onRungClicked
        ladderView.onInstructionClicked = onInstructionClicked

        // Resize to fit content
        let totalHeight = ladderView.railMargin * 2 + CGFloat(rungs.count) * ladderView.rungHeight
        let width = scrollView.contentView.bounds.width
        ladderView.frame = NSRect(x: 0, y: 0, width: max(width, 800),
                                   height: max(totalHeight, scrollView.contentView.bounds.height))
        ladderView.needsDisplay = true
    }
}

/// The actual AppKit view that renders ladder logic using Core Graphics.
/// Draws real rung data: power rails, contacts, coils, branches, wires.
class LadderNSView: NSView {
    // MARK: - Data

    var rungs: [Rung] = []
    var energizedRungs: Set<UInt32> = []
    var onRungClicked: ((Int) -> Void)?
    var onInstructionClicked: ((Int, String) -> Void)?

    // MARK: - Layout Constants

    let rungHeight: CGFloat = 80
    let railWidth: CGFloat = 3
    let railMargin: CGFloat = 40
    let instructionWidth: CGFloat = 90
    let instructionHeight: CGFloat = 36
    let wireThickness: CGFloat = 2
    let branchSpacing: CGFloat = 28
    let instrSpacing: CGFloat = 16

    // MARK: - Colors

    private var railColor: NSColor { .systemGray }
    private var wireColor: NSColor { .labelColor }
    private var energizedColor: NSColor { .systemGreen }
    private var contactColor: NSColor { .systemBlue }
    private var coilColor: NSColor { .systemRed }
    private var timerColor: NSColor { .systemOrange }
    private var counterColor: NSColor { .systemPurple }
    private var mathColor: NSColor { .systemTeal }
    private var commentColor: NSColor { .systemGreen }

    // Hit test rects
    private var instructionRects: [(rect: CGRect, rungIndex: Int, instructionId: String)] = []

    override var isFlipped: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        instructionRects.removeAll()

        // Background
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(bounds)

        guard !rungs.isEmpty else {
            drawEmptyState(ctx: ctx)
            return
        }

        let canvasWidth = bounds.width
        let totalHeight = railMargin + CGFloat(rungs.count) * rungHeight + railMargin

        // Power rails
        ctx.setStrokeColor(railColor.cgColor)
        ctx.setLineWidth(railWidth)
        ctx.move(to: CGPoint(x: railMargin, y: railMargin))
        ctx.addLine(to: CGPoint(x: railMargin, y: totalHeight))
        ctx.strokePath()

        ctx.move(to: CGPoint(x: canvasWidth - railMargin, y: railMargin))
        ctx.addLine(to: CGPoint(x: canvasWidth - railMargin, y: totalHeight))
        ctx.strokePath()

        // Draw each rung
        for (index, rung) in rungs.enumerated() {
            let y = railMargin + CGFloat(index) * rungHeight + rungHeight / 2
            let isEnergized = energizedRungs.contains(rung.number)
            drawRung(ctx: ctx, rung: rung, rungIndex: index, centerY: y,
                    canvasWidth: canvasWidth, energized: isEnergized)
        }
    }

    private func drawEmptyState(ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let str = NSAttributedString(string: "Select a routine to view ladder logic", attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height / 2 - size.height / 2))
    }

    private func drawRung(ctx: CGContext, rung: Rung, rungIndex: Int,
                          centerY: CGFloat, canvasWidth: CGFloat, energized: Bool) {
        let leftRail = railMargin
        let rightRail = canvasWidth - railMargin

        // Rung number
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        NSAttributedString(string: "\(rung.number)", attributes: numAttrs)
            .draw(at: CGPoint(x: 8, y: centerY - 6))

        // Comment above rung
        if !rung.comment.isEmpty {
            let commentAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: commentColor,
            ]
            NSAttributedString(string: rung.comment, attributes: commentAttrs)
                .draw(at: CGPoint(x: leftRail + 8, y: centerY - rungHeight / 2 + 2))
        }

        // Energized highlight
        if energized {
            ctx.setFillColor(energizedColor.withAlphaComponent(0.05).cgColor)
            ctx.fill(CGRect(x: leftRail, y: centerY - rungHeight / 2,
                           width: rightRail - leftRail, height: rungHeight))
        }

        // Main horizontal wire
        let wireCol = energized ? energizedColor : wireColor
        ctx.setStrokeColor(wireCol.cgColor)
        ctx.setLineWidth(wireThickness)
        ctx.move(to: CGPoint(x: leftRail, y: centerY))
        ctx.addLine(to: CGPoint(x: rightRail, y: centerY))
        ctx.strokePath()

        // Draw the element tree
        let startX = leftRail + 20
        let availableWidth = rightRail - leftRail - 40
        drawElement(ctx: ctx, element: rung.element, rungIndex: rungIndex,
                   x: startX, centerY: centerY, availableWidth: availableWidth,
                   energized: energized)
    }

    @discardableResult
    private func drawElement(ctx: CGContext, element: RungElement, rungIndex: Int,
                             x: CGFloat, centerY: CGFloat, availableWidth: CGFloat,
                             energized: Bool) -> CGFloat {
        switch element {
        case .instruction(let inst):
            return drawInstruction(ctx: ctx, instruction: inst, rungIndex: rungIndex,
                                 x: x, centerY: centerY, energized: energized)

        case .series(let elements):
            guard !elements.isEmpty else { return 0 }
            let perElement = availableWidth / CGFloat(elements.count)
            var currentX = x
            for el in elements {
                let consumed = drawElement(ctx: ctx, element: el, rungIndex: rungIndex,
                                          x: currentX, centerY: centerY,
                                          availableWidth: perElement - instrSpacing,
                                          energized: energized)
                currentX += consumed + instrSpacing
            }
            return currentX - x

        case .parallel(let branches):
            guard !branches.isEmpty else { return 0 }
            let branchCount = CGFloat(branches.count)
            let totalBranchHeight = branchCount * branchSpacing
            let topY = centerY - totalBranchHeight / 2 + branchSpacing / 2

            let wireCol = energized ? energizedColor : wireColor
            ctx.setStrokeColor(wireCol.cgColor)
            ctx.setLineWidth(wireThickness)

            let branchWidth = min(availableWidth, instructionWidth + instrSpacing * 2)

            // Left vertical connector
            ctx.move(to: CGPoint(x: x, y: topY))
            ctx.addLine(to: CGPoint(x: x, y: topY + totalBranchHeight - branchSpacing))
            ctx.strokePath()

            // Right vertical connector
            ctx.move(to: CGPoint(x: x + branchWidth, y: topY))
            ctx.addLine(to: CGPoint(x: x + branchWidth, y: topY + totalBranchHeight - branchSpacing))
            ctx.strokePath()

            for (i, branch) in branches.enumerated() {
                let branchY = topY + CGFloat(i) * branchSpacing

                ctx.setStrokeColor(wireCol.cgColor)
                ctx.setLineWidth(wireThickness)
                ctx.move(to: CGPoint(x: x, y: branchY))
                ctx.addLine(to: CGPoint(x: x + branchWidth, y: branchY))
                ctx.strokePath()

                drawElement(ctx: ctx, element: branch, rungIndex: rungIndex,
                           x: x + instrSpacing, centerY: branchY,
                           availableWidth: branchWidth - instrSpacing * 2,
                           energized: energized)
            }
            return branchWidth
        }
    }

    private func drawInstruction(ctx: CGContext, instruction: Instruction,
                                 rungIndex: Int, x: CGFloat, centerY: CGFloat,
                                 energized: Bool) -> CGFloat {
        let it = instruction.instructionType
        let color = instructionColor(it)
        let tagName = instruction.operands.first?.displayString ?? ""

        if it.isInput {
            drawContactSymbol(ctx: ctx, x: x, y: centerY, color: color,
                            tagName: tagName, isNormallyClosed: it == .xio,
                            energized: energized)
        } else if it.isOutput {
            drawCoilSymbol(ctx: ctx, x: x, y: centerY, color: color,
                         mnemonic: it.mnemonic, tagName: tagName, energized: energized)
        } else {
            drawBoxInstruction(ctx: ctx, x: x, y: centerY, color: color,
                             instruction: instruction, energized: energized)
        }

        let rect = CGRect(x: x - instructionWidth / 2, y: centerY - instructionHeight / 2,
                          width: instructionWidth, height: instructionHeight)
        instructionRects.append((rect: rect, rungIndex: rungIndex,
                                instructionId: instruction.id))
        return instructionWidth
    }

    // MARK: - Symbol Drawing

    private func drawContactSymbol(ctx: CGContext, x: CGFloat, y: CGFloat,
                                   color: NSColor, tagName: String,
                                   isNormallyClosed: Bool, energized: Bool) {
        let halfH: CGFloat = 14
        let drawColor = energized ? energizedColor : color

        ctx.setStrokeColor(drawColor.cgColor)
        ctx.setLineWidth(2)

        ctx.move(to: CGPoint(x: x - 5, y: y - halfH))
        ctx.addLine(to: CGPoint(x: x - 5, y: y + halfH))
        ctx.strokePath()

        ctx.move(to: CGPoint(x: x + 5, y: y - halfH))
        ctx.addLine(to: CGPoint(x: x + 5, y: y + halfH))
        ctx.strokePath()

        if isNormallyClosed {
            ctx.move(to: CGPoint(x: x - 6, y: y + halfH - 2))
            ctx.addLine(to: CGPoint(x: x + 6, y: y - halfH + 2))
            ctx.strokePath()
        }

        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: drawColor,
        ]
        let tagStr = NSAttributedString(string: tagName, attributes: tagAttrs)
        let tagSize = tagStr.size()
        tagStr.draw(at: CGPoint(x: x - tagSize.width / 2, y: y - halfH - 14))
    }

    private func drawCoilSymbol(ctx: CGContext, x: CGFloat, y: CGFloat,
                                color: NSColor, mnemonic: String, tagName: String,
                                energized: Bool) {
        let radius: CGFloat = 14
        let drawColor = energized ? energizedColor : color

        ctx.setStrokeColor(drawColor.cgColor)
        ctx.setLineWidth(2)
        ctx.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.strokePath()

        if mnemonic == "OTL" || mnemonic == "OTU" {
            let letter = mnemonic == "OTL" ? "L" : "U"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: drawColor,
            ]
            let str = NSAttributedString(string: letter, attributes: attrs)
            let sz = str.size()
            str.draw(at: CGPoint(x: x - sz.width / 2, y: y - sz.height / 2))
        }

        if energized {
            ctx.setFillColor(drawColor.withAlphaComponent(0.15).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                        width: radius * 2, height: radius * 2))
        }

        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: drawColor,
        ]
        let tagStr = NSAttributedString(string: tagName, attributes: tagAttrs)
        let tagSize = tagStr.size()
        tagStr.draw(at: CGPoint(x: x - tagSize.width / 2, y: y - radius - 14))
    }

    private func drawBoxInstruction(ctx: CGContext, x: CGFloat, y: CGFloat,
                                    color: NSColor, instruction: Instruction,
                                    energized: Bool) {
        let drawColor = energized ? energizedColor : color
        let w: CGFloat = instructionWidth - 10
        let h: CGFloat = instructionHeight
        let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)

        ctx.setStrokeColor(drawColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)

        if energized {
            ctx.setFillColor(drawColor.withAlphaComponent(0.08).cgColor)
            ctx.fill(rect)
        }

        let mnemonicAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: drawColor,
        ]
        let mnemonicStr = NSAttributedString(string: instruction.instructionType.mnemonic,
                                              attributes: mnemonicAttrs)
        let mnSize = mnemonicStr.size()
        mnemonicStr.draw(at: CGPoint(x: x - mnSize.width / 2, y: y - h / 2 + 2))

        let operandText = instruction.operands.map { $0.displayString }.joined(separator: ", ")
        let opAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: drawColor.withAlphaComponent(0.8),
        ]
        let opStr = NSAttributedString(string: operandText, attributes: opAttrs)
        let opSize = opStr.size()
        opStr.draw(at: CGPoint(x: x - opSize.width / 2, y: y + 2))
    }

    private func instructionColor(_ it: InstructionType) -> NSColor {
        if it.isInput { return contactColor }
        if it.isOutput { return coilColor }
        switch it {
        case .ton, .tof, .rto: return timerColor
        case .ctu, .ctd, .res: return counterColor
        case .add, .sub, .mul, .div, .mod_, .neg, .mov, .cop: return mathColor
        default: return .labelColor
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        for hit in instructionRects {
            if hit.rect.contains(point) {
                onInstructionClicked?(hit.rungIndex, hit.instructionId)
                return
            }
        }

        let rungIndex = Int((point.y - railMargin) / rungHeight)
        if rungIndex >= 0 && rungIndex < rungs.count {
            onRungClicked?(rungIndex)
        }
    }
}

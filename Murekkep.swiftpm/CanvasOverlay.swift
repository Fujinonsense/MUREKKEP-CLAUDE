import UIKit

/// Everything drawn over the ink that is not ink: drafting instruments, shape and lasso previews,
/// the selection frame, the compass and live measurements. Geometry is given in document space.
final class CanvasOverlayView: UIView {
    /// View position of document point (0, 0) and view points per document point.
    var origin: CGPoint = .zero
    var zoom: CGFloat = 1

    var instrument: Instrument?
    /// Shown upright next to the instrument while it is being turned ("37°").
    var instrumentLabel: String?
    /// A measurement following the pencil (document point, text).
    var liveLabel: (point: CGPoint, text: String)?
    var previewPaths: [[CGPoint]] = []
    var lasso: [CGPoint] = []
    var selection: CGRect?
    var compass: (center: CGPoint, radius: CGFloat)?
    var compassPen: CGPoint?
    /// Handles of a recognized shape (document space); the last one moves the whole shape.
    var shapeHandles: [CGPoint] = []

    private let accent = UIColor(red: 0.10, green: 0.33, blue: 0.80, alpha: 1)
    /// Dash and gap of the lasso outline, in screen points (the pencil ticks once per period).
    static let lassoDash: [CGFloat] = [6, 4]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isEmpty: Bool {
        instrument == nil && liveLabel == nil && previewPaths.isEmpty && lasso.isEmpty && selection == nil && compass == nil
            && shapeHandles.isEmpty
    }

    private func view(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * zoom, y: origin.y + p.y * zoom)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        if let instrument {
            drawInstrument(instrument, in: ctx)
        }
        if !previewPaths.isEmpty {
            ctx.saveGState()
            ctx.setStrokeColor(accent.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.6)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for path in previewPaths where path.count >= 2 {
                ctx.move(to: view(path[0]))
                for p in path.dropFirst() {
                    ctx.addLine(to: view(p))
                }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        if lasso.count >= 2 {
            ctx.saveGState()
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.4)
            ctx.setLineDash(phase: 0, lengths: Self.lassoDash)
            ctx.move(to: view(lasso[0]))
            for p in lasso.dropFirst() {
                ctx.addLine(to: view(p))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        if let selection {
            drawSelection(selection, in: ctx)
        }
        if !shapeHandles.isEmpty {
            drawShapeHandles(in: ctx)
        }
        if let compass {
            drawCompass(center: compass.center, radius: compass.radius, in: ctx)
        }
        if let liveLabel {
            let p = view(liveLabel.point)
            bubble(liveLabel.text, at: CGPoint(x: p.x + 26, y: p.y - 30), in: ctx)
        }
        if let instrumentLabel, let instrument {
            let c = view(instrument.center)
            bubble(instrumentLabel, at: CGPoint(x: c.x, y: c.y - 54), in: ctx)
        }
    }

    // MARK: Instruments

    private func drawInstrument(_ ins: Instrument, in ctx: CGContext) {
        ctx.saveGState()
        let c = view(ins.center)
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: ins.angle)
        ctx.scaleBy(x: zoom, y: zoom)
        let outline = ins.localOutline
        let body = CGMutablePath()
        body.addLines(between: outline)
        body.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3 / zoom), blur: 10 / zoom, color: UIColor.black.withAlphaComponent(0.18).cgColor)
        ctx.addPath(body)
        ctx.setFillColor(UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 0.72).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(body)
        ctx.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1.1 / zoom)
        ctx.strokePath()

        let mm = pointsPerMillimetre
        ctx.setStrokeColor(UIColor(white: 0.12, alpha: 0.85).cgColor)
        ctx.setLineWidth(0.7 / zoom)
        switch ins.kind {
        case .ruler:
            let half = Instrument.rulerLength / 2
            let h = Instrument.rulerWidth / 2
            let count = Int((Instrument.rulerLength / mm).rounded())
            for i in 0...count {
                let x = -half + CGFloat(i) * mm
                let len: CGFloat = i % 10 == 0 ? 4.2 * mm : (i % 5 == 0 ? 3 * mm : 1.7 * mm)
                ctx.move(to: CGPoint(x: x, y: -h))
                ctx.addLine(to: CGPoint(x: x, y: -h + len))
                ctx.move(to: CGPoint(x: x, y: h))
                ctx.addLine(to: CGPoint(x: x, y: h - len))
            }
            ctx.strokePath()
            for cm in 0...(count / 10) {
                label("\(cm)", at: CGPoint(x: -half + CGFloat(cm) * 10 * mm, y: -h + 6.4 * mm), size: 2.7 * mm)
            }
            label("cm", at: CGPoint(x: half - 6 * mm, y: h - 6.4 * mm), size: 2.4 * mm)
        case .setSquare45, .setSquare3060:
            let a = outline[0]
            let b = outline[1]
            let top = outline[2]
            legTicks(from: a, to: b, inward: CGPoint(x: 0, y: -1), in: ctx)
            legTicks(from: a, to: top, inward: CGPoint(x: 1, y: 0), in: ctx)
            ctx.strokePath()
            let small = ins.kind == .setSquare45 ? "45°" : "30°"
            let big = ins.kind == .setSquare45 ? "45°" : "60°"
            label(small, at: CGPoint(x: b.x - 16 * mm, y: b.y - 4 * mm), size: 3 * mm)
            label(big, at: CGPoint(x: top.x + 5 * mm, y: top.y + 14 * mm), size: 3 * mm)
            label("90°", at: CGPoint(x: a.x + 7 * mm, y: a.y - 6 * mm), size: 3 * mm)
        case .protractor:
            let r = Instrument.protractorRadius
            for d in 0...180 {
                let ang = CGFloat(d) * .pi / 180
                let dir = CGPoint(x: cos(ang), y: -sin(ang))
                let len: CGFloat = d % 10 == 0 ? 5 * mm : (d % 5 == 0 ? 3.4 * mm : 2 * mm)
                ctx.move(to: CGPoint(x: dir.x * r, y: dir.y * r))
                ctx.addLine(to: CGPoint(x: dir.x * (r - len), y: dir.y * (r - len)))
            }
            ctx.move(to: CGPoint(x: -r, y: 0))
            ctx.addLine(to: CGPoint(x: r, y: 0))
            ctx.move(to: CGPoint(x: -3 * mm, y: 0))
            ctx.addLine(to: CGPoint(x: 3 * mm, y: 0))
            ctx.move(to: CGPoint(x: 0, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: -4 * mm))
            ctx.strokePath()
            for d in stride(from: 0, through: 180, by: 10) {
                let ang = CGFloat(d) * .pi / 180
                let outer = CGPoint(x: cos(ang) * (r - 8.5 * mm), y: -sin(ang) * (r - 8.5 * mm))
                let inner = CGPoint(x: cos(ang) * (r - 13 * mm), y: -sin(ang) * (r - 13 * mm))
                label("\(d)", at: outer, size: 2.5 * mm)
                label("\(180 - d)", at: inner, size: 2 * mm, color: accent)
            }
        }
        ctx.restoreGState()
    }

    private func legTicks(from a: CGPoint, to b: CGPoint, inward: CGPoint, in ctx: CGContext) {
        let mm = pointsPerMillimetre
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return }
        let u = CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        let count = Int(length / mm) - 6
        guard count > 6 else { return }
        for i in 6...count {
            let p = CGPoint(x: a.x + u.x * CGFloat(i) * mm, y: a.y + u.y * CGFloat(i) * mm)
            let len: CGFloat = i % 10 == 0 ? 3.6 * mm : (i % 5 == 0 ? 2.6 * mm : 1.5 * mm)
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x + inward.x * len, y: p.y + inward.y * len))
        }
    }

    private func label(_ text: String, at p: CGPoint, size: CGFloat, color: UIColor = UIColor(white: 0.15, alpha: 0.9)) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
    }

    // MARK: Selection, compass, labels

    /// View points between the selection frame and its turn handle.
    static let turnHandleOffset: CGFloat = 30

    private func drawSelection(_ r: CGRect, in ctx: CGContext) {
        let a = view(CGPoint(x: r.minX, y: r.minY))
        let b = view(CGPoint(x: r.maxX, y: r.maxY))
        let frame = CGRect(x: a.x - 8, y: a.y - 8, width: b.x - a.x + 16, height: b.y - a.y + 16)
        ctx.saveGState()
        ctx.setFillColor(accent.withAlphaComponent(0.06).cgColor)
        ctx.fill(frame)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.4)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(frame)
        ctx.setLineDash(phase: 0, lengths: [])
        // Turn handle on a short stem above the frame.
        let turn = CGPoint(x: frame.midX, y: frame.minY - Self.turnHandleOffset)
        ctx.move(to: CGPoint(x: frame.midX, y: frame.minY))
        ctx.addLine(to: CGPoint(x: turn.x, y: turn.y + 9))
        ctx.setLineWidth(1.2)
        ctx.strokePath()
        let turnDisc = CGRect(x: turn.x - 10, y: turn.y - 10, width: 20, height: 20)
        ctx.setFillColor(accent.cgColor)
        ctx.fillEllipse(in: turnDisc)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1.6)
        ctx.addArc(center: turn, radius: 5, startAngle: -.pi * 0.85, endAngle: .pi * 0.55, clockwise: false)
        ctx.strokePath()
        let tip = CGPoint(x: turn.x + 5 * cos(.pi * 0.55), y: turn.y + 5 * sin(.pi * 0.55))
        ctx.move(to: CGPoint(x: tip.x + 2.6, y: tip.y - 0.4))
        ctx.addLine(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x + 0.6, y: tip.y - 2.8))
        ctx.strokePath()
        // A resize handle on every corner.
        for c in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                  CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)] {
            let handle = CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: handle)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: handle.insetBy(dx: 1, dy: 1))
        }
        ctx.restoreGState()
    }

    /// Round handles on the corners (or axis ends) of a recognized shape, and a filled one with
    /// arrows in its middle for moving it.
    private func drawShapeHandles(in ctx: CGContext) {
        ctx.saveGState()
        for (i, h) in shapeHandles.enumerated() {
            let c = view(h)
            if i == shapeHandles.count - 1 {
                let disc = CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)
                ctx.setFillColor(accent.withAlphaComponent(0.9).cgColor)
                ctx.fillEllipse(in: disc)
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineCap(.round)
                for (dx, dy) in [(CGFloat(1), CGFloat(0)), (-1, 0), (0, 1), (0, -1)] {
                    let tip = CGPoint(x: c.x + dx * 6.5, y: c.y + dy * 6.5)
                    ctx.move(to: CGPoint(x: c.x + dx * 2, y: c.y + dy * 2))
                    ctx.addLine(to: tip)
                    ctx.move(to: CGPoint(x: tip.x - dx * 2.2 + dy * 2.2, y: tip.y - dy * 2.2 + dx * 2.2))
                    ctx.addLine(to: tip)
                    ctx.addLine(to: CGPoint(x: tip.x - dx * 2.2 - dy * 2.2, y: tip.y - dy * 2.2 - dx * 2.2))
                }
                ctx.strokePath()
            } else {
                let handle = CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)
                ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.25).cgColor)
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fillEllipse(in: handle)
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(2.2)
                ctx.strokeEllipse(in: handle.insetBy(dx: 1.2, dy: 1.2))
            }
        }
        ctx.restoreGState()
    }

    private func drawCompass(center: CGPoint, radius: CGFloat, in ctx: CGContext) {
        let c = view(center)
        let r = radius * zoom
        ctx.saveGState()
        ctx.setStrokeColor(accent.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 5])
        if r > 1 {
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.6)
        ctx.move(to: CGPoint(x: c.x - 7, y: c.y))
        ctx.addLine(to: CGPoint(x: c.x + 7, y: c.y))
        ctx.move(to: CGPoint(x: c.x, y: c.y - 7))
        ctx.addLine(to: CGPoint(x: c.x, y: c.y + 7))
        if let pen = compassPen {
            let p = view(pen)
            ctx.move(to: c)
            ctx.addLine(to: p)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func bubble(_ text: String, at p: CGPoint, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        let box = CGRect(x: p.x - sz.width / 2 - 10, y: p.y - sz.height / 2 - 5, width: sz.width + 20, height: sz.height + 10)
        ctx.saveGState()
        ctx.addPath(UIBezierPath(roundedRect: box, cornerRadius: box.height / 2).cgPath)
        ctx.setFillColor(accent.withAlphaComponent(0.92).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        s.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 5))
    }
}

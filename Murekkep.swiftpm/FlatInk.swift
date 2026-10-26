import CoreGraphics
import Foundation

/// 2D (Core Graphics) version of the ink, used for PDF export, thumbnails and page images for Claude.
enum FlatInk {
    static func draw(_ strokes: [Stroke], in ctx: CGContext) {
        ctx.saveGState()
        for s in strokes where s.brush == .highlighter {
            drawHighlighter(s, in: ctx)
        }
        for s in strokes where s.brush != .highlighter {
            drawInk(s, in: ctx)
        }
        ctx.restoreGState()
    }

    /// Every stroke as an even, dark line (for text recognition: no foam, beads, glow or blades).
    static func drawPlain(_ strokes: [Stroke], in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for s in strokes where s.brush != .highlighter {
            guard let first = s.points.first else { continue }
            let width = CGFloat(min(max(s.width * 0.55, 1.4), 3.0))
            if s.points.count == 1 {
                ctx.fillEllipse(in: CGRect(x: CGFloat(first.x) - width * 0.6, y: CGFloat(first.y) - width * 0.6,
                                           width: width * 1.2, height: width * 1.2))
                continue
            }
            ctx.setLineWidth(width)
            ctx.move(to: point(first))
            for p in s.points.dropFirst() {
                ctx.addLine(to: point(p))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func color(_ c: InkColor, lighten: CGFloat = 0) -> CGColor {
        let r = CGFloat(c.r) + (1 - CGFloat(c.r)) * lighten
        let g = CGFloat(c.g) + (1 - CGFloat(c.g)) * lighten
        let b = CGFloat(c.b) + (1 - CGFloat(c.b)) * lighten
        return CGColor(red: r, green: g, blue: b, alpha: CGFloat(c.a))
    }

    private static func point(_ p: InkPoint) -> CGPoint {
        CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }

    private static func drawHighlighter(_ s: Stroke, in ctx: CGContext) {
        guard let first = s.points.first else { return }
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        let c = color(s.color)
        if s.points.count == 1 {
            let r = CGFloat(first.r)
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: CGFloat(first.x) - r, y: CGFloat(first.y) - r, width: r * 2, height: r * 2))
        } else {
            let path = CGMutablePath()
            path.move(to: point(first))
            for p in s.points.dropFirst() {
                path.addLine(to: point(p))
            }
            let avg = s.points.reduce(Float(0)) { $0 + $1.r } / Float(s.points.count)
            ctx.addPath(path)
            ctx.setStrokeColor(c)
            ctx.setLineWidth(CGFloat(avg * 2))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func drawInk(_ s: Stroke, in ctx: CGContext) {
        switch s.brush {
        case .rainbow:
            drawRainbow(s, in: ctx)
            return
        case .grass:
            drawGrass(s, in: ctx)
            return
        case .bloom:
            drawBloom(s, in: ctx)
            return
        case .neon:
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: CGFloat(s.width) * 2.2, color: color(s.color))
            drawPolyline(s.points, color: color(s.color, lighten: 0.15), widthScale: 1, in: ctx)
            ctx.restoreGState()
            drawPolyline(s.points, color: color(s.color, lighten: 0.7), widthScale: 0.45, in: ctx)
            return
        case .watercolor:
            var c = s.color
            c.a *= 0.42
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawPolyline(s.points, color: color(c), widthScale: 1, in: ctx)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return
        case .pencil:
            let avg = s.points.isEmpty ? 1 : s.points.reduce(Float(0)) { $0 + $1.ink } / Float(s.points.count)
            var c = s.color
            c.a *= min(1, 0.25 + avg * 0.75)
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawPolyline(s.points, color: color(c), widthScale: 1, in: ctx)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return
        case .glitter:
            drawPolyline(s.points, color: color(s.color, lighten: 0.1), widthScale: 1, in: ctx)
            drawSparkles(s, in: ctx)
            return
        case .wave:
            drawPolyline(s.points, color: color(s.color, lighten: 0.12), widthScale: 1, in: ctx)
        case .sea:
            drawPolyline(s.points, color: color(s.color, lighten: 0.1), widthScale: 0.9, in: ctx)
            drawAlong(s, every: { max($0 * 3.4, 5) }, in: ctx) { p, r, c in
                c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
                c.fillEllipse(in: CGRect(x: p.x - r * 0.45, y: p.y - r * 0.8, width: r * 0.9, height: r * 1.6))
            }
        case .lava:
            // Exports show the cooled crust with glowing cracks.
            drawPolyline(s.points, color: CGColor(red: 0.13, green: 0.08, blue: 0.07, alpha: 1), widthScale: 1, in: ctx)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: CGFloat(s.width) * 0.8, color: color(s.color))
            drawPolyline(s.points, color: color(s.color, lighten: 0.25), widthScale: 0.3, in: ctx)
            ctx.restoreGState()
        case .lightning:
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: CGFloat(s.width) * 2.4, color: color(s.color))
            drawPolyline(s.points, color: color(s.color, lighten: 0.3), widthScale: 0.8, in: ctx)
            ctx.restoreGState()
            drawPolyline(s.points, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95), widthScale: 0.35, in: ctx)
        case .galaxy:
            drawPolyline(s.points, color: color(InkColor(s.color.r * 0.35, s.color.g * 0.3, s.color.b * 0.45, s.color.a)),
                         widthScale: 1, in: ctx)
            drawSparkles(s, in: ctx)
        case .pearl:
            drawAlong(s, every: { $0 * 2 }, in: ctx) { p, r, c in
                c.setFillColor(color(s.color))
                c.fillEllipse(in: CGRect(x: p.x - r * 0.92, y: p.y - r * 0.92, width: r * 1.84, height: r * 1.84))
                c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
                c.fillEllipse(in: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.6, width: r * 0.45, height: r * 0.4))
            }
        case .ice, .jelly:
            var c = s.color
            c.a *= s.brush == .ice ? 0.7 : 0.85
            drawPolyline(s.points, color: color(c), widthScale: 1, in: ctx)
            drawHighlight(s, alpha: 0.6, in: ctx)
        case .fountain, .gold, .chrome, .impasto:
            drawPolyline(s.points, color: color(s.color), widthScale: 1, in: ctx)
            drawHighlight(s, alpha: s.brush == .fountain ? 0.35 : 0.65, in: ctx)
        default:
            drawPolyline(s.points, color: color(s.color), widthScale: 1, in: ctx)
        }
    }

    /// A thin light streak towards the top-left, suggesting a raised, glossy surface.
    private static func drawHighlight(_ s: Stroke, alpha: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: -CGFloat(s.width) * 0.12, y: -CGFloat(s.width) * 0.15)
        drawPolyline(s.points, color: CGColor(red: 1, green: 1, blue: 1, alpha: alpha), widthScale: 0.28, in: ctx)
        ctx.restoreGState()
    }

    /// Calls `body` at regular distances along the stroke (spacing depends on the local radius).
    private static func drawAlong(_ s: Stroke, every spacing: (CGFloat) -> CGFloat, in ctx: CGContext,
                                  _ body: (CGPoint, CGFloat, CGContext) -> Void) {
        let pts = s.points
        guard let first = pts.first else { return }
        if pts.count == 1 {
            body(point(first), CGFloat(first.r), ctx)
            return
        }
        var next: CGFloat = 0
        var travelled: CGFloat = 0
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            let len = CGFloat(vlength(b.position - a.position))
            while next <= travelled + len {
                let t = len > 0 ? (next - travelled) / len : 0
                let p = CGPoint(x: CGFloat(a.x) + CGFloat(b.x - a.x) * t, y: CGFloat(a.y) + CGFloat(b.y - a.y) * t)
                let r = CGFloat(a.r) + CGFloat(b.r - a.r) * t
                body(p, r, ctx)
                next += max(spacing(r), 1)
            }
            travelled += len
        }
    }

    private static func drawPolyline(_ pts: [InkPoint], color c: CGColor, widthScale: Float, in ctx: CGContext) {
        guard let first = pts.first else { return }
        ctx.setStrokeColor(c)
        ctx.setFillColor(c)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if pts.count == 1 {
            let r = CGFloat(first.r * widthScale)
            ctx.fillEllipse(in: CGRect(x: CGFloat(first.x) - r, y: CGFloat(first.y) - r, width: r * 2, height: r * 2))
            return
        }
        // Group runs of similar width into one path to keep the output small.
        var i = 0
        while i < pts.count - 1 {
            let r0 = pts[i].r
            var j = i + 1
            var sum = pts[i].r + pts[j].r
            var n: Float = 2
            while j + 1 < pts.count, abs(pts[j + 1].r - r0) <= r0 * 0.08, j - i < 48 {
                j += 1
                sum += pts[j].r
                n += 1
            }
            let path = CGMutablePath()
            path.move(to: point(pts[i]))
            for k in (i + 1)...j {
                path.addLine(to: point(pts[k]))
            }
            ctx.addPath(path)
            ctx.setLineWidth(CGFloat(sum / n * 2 * widthScale))
            ctx.strokePath()
            i = j
        }
    }

    /// Same hue cycle as the shader: the hue moves with the distance along the stroke.
    private static func drawRainbow(_ s: Stroke, in ctx: CGContext) {
        let pts = s.points
        guard pts.count > 1 else {
            drawPolyline(pts, color: color(s.color), widthScale: 1, in: ctx)
            return
        }
        let base = UIColorComponents.hsv(r: s.color.r, g: s.color.g, b: s.color.b)
        ctx.setLineCap(.round)
        var arc: Float = 0
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            let hue = (base.h + arc / 220).truncatingRemainder(dividingBy: 1)
            let rgb = UIColorComponents.rgb(h: hue, s: max(base.s, 0.25), v: max(base.v, 0.35))
            ctx.setStrokeColor(CGColor(red: CGFloat(rgb.0), green: CGFloat(rgb.1), blue: CGFloat(rgb.2), alpha: CGFloat(s.color.a)))
            ctx.setLineWidth(CGFloat(a.r + b.r))
            ctx.move(to: point(a))
            ctx.addLine(to: point(b))
            ctx.strokePath()
            arc += vlength(b.position - a.position)
        }
    }

    private static func drawSparkles(_ s: Stroke, in ctx: CGContext) {
        let pts = s.points
        guard pts.count > 1 else { return }
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        for i in stride(from: 0, to: pts.count, by: 2) {
            let p = pts[i]
            let h = Float((i &* 2_654_435_761) & 0xFFFF) / 65_535
            guard h > 0.55 else { continue }
            let angle = h * 40
            let off = SIMD2<Float>(cos(angle), sin(angle)) * p.r * 0.6 * h
            let r = CGFloat(max(0.35, p.r * 0.14))
            ctx.fillEllipse(in: CGRect(x: CGFloat(p.x + off.x) - r, y: CGFloat(p.y + off.y) - r, width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
    }

    /// Fully grown grass with open flowers.
    private static func drawGrass(_ s: Stroke, in ctx: CGContext) {
        // Soil line under the blades.
        drawPolyline(s.points, color: CGColor(red: CGFloat(s.color.r * 0.45), green: CGFloat(s.color.g * 0.45),
                                              blue: CGFloat(s.color.b * 0.45), alpha: 0.85), widthScale: 0.7, in: ctx)
        drawField(GrassGenerator.field(points: s.points, width: s.width, color: s.color, seed: s.seed), alpha: s.color.a, in: ctx)
    }

    /// The flowering water: the glossy line, then its flowers on their stems.
    private static func drawBloom(_ s: Stroke, in ctx: CGContext) {
        var c = s.color
        c.a *= 0.85
        drawPolyline(s.points, color: color(c), widthScale: 1, in: ctx)
        drawHighlight(s, alpha: 0.6, in: ctx)
        drawField(GrassGenerator.blooms(points: s.points, width: s.width, color: s.color, seed: s.seed), alpha: s.color.a, in: ctx)
    }

    /// Blades and stems, then the flowers at their tips.
    private static func drawField(_ field: GrassField, alpha: Float, in ctx: CGContext) {
        ctx.saveGState()
        for b in field.blades {
            let tip = GrassGenerator.point(on: b, at: 1)
            let mid = GrassGenerator.point(on: b, at: 0.5)
            let half = CGFloat(b.width * 0.5)
            let path = CGMutablePath()
            if b.kind == .glassLeaf {
                // A leaf: pointed at both ends, bulging either side of its midline.
                let d = tip - b.base
                let dl = max(vlength(d), 1e-4)
                let n = SIMD2<Float>(-d.y, d.x) / dl * b.width
                path.move(to: CGPoint(x: CGFloat(b.base.x), y: CGFloat(b.base.y)))
                path.addQuadCurve(to: CGPoint(x: CGFloat(tip.x), y: CGFloat(tip.y)),
                                  control: CGPoint(x: CGFloat(mid.x - n.x), y: CGFloat(mid.y - n.y)))
                path.addQuadCurve(to: CGPoint(x: CGFloat(b.base.x), y: CGFloat(b.base.y)),
                                  control: CGPoint(x: CGFloat(mid.x + n.x), y: CGFloat(mid.y + n.y)))
            } else {
                path.move(to: CGPoint(x: CGFloat(b.base.x) - half, y: CGFloat(b.base.y)))
                path.addQuadCurve(to: CGPoint(x: CGFloat(tip.x), y: CGFloat(tip.y)),
                                  control: CGPoint(x: CGFloat(mid.x) - half * 0.6, y: CGFloat(mid.y)))
                path.addQuadCurve(to: CGPoint(x: CGFloat(b.base.x) + half, y: CGFloat(b.base.y)),
                                  control: CGPoint(x: CGFloat(mid.x) + half * 0.6, y: CGFloat(mid.y)))
            }
            path.closeSubpath()
            let shade: Float = b.kind == .stem ? 0.9 : 1.0
            // Glass stems and leaves are see-through, with a lighter edge.
            let glassAlpha: Float = b.kind == .glassStem ? 0.74 : (b.kind == .glassLeaf ? 0.6 : 1)
            ctx.setFillColor(CGColor(red: CGFloat(min(1, b.color.x * shade)), green: CGFloat(min(1, b.color.y * shade)),
                                     blue: CGFloat(min(1, b.color.z * shade)), alpha: CGFloat(alpha * glassAlpha)))
            ctx.addPath(path)
            ctx.fillPath()
            if b.kind == .glassStem || b.kind == .glassLeaf {
                ctx.setStrokeColor(CGColor(red: CGFloat(min(1, b.color.x * 0.7)), green: CGFloat(min(1, b.color.y * 0.9)),
                                           blue: 1, alpha: CGFloat(alpha * 0.35)))
                ctx.setLineWidth(max(0.25, CGFloat(b.width) * 0.12))
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        for f in field.flowers where field.blades.indices.contains(f.stem) {
            let center = GrassGenerator.point(on: field.blades[f.stem], at: 1)
            let c = CGPoint(x: CGFloat(center.x), y: CGFloat(center.y))
            let r = CGFloat(f.radius)
            if f.style > 2.5 {
                drawGlassFlower(f, at: c, radius: r, alpha: CGFloat(alpha), in: ctx)
                continue
            }
            let count = max(4, Int(f.petals))
            ctx.setFillColor(CGColor(red: CGFloat(f.petal.x), green: CGFloat(f.petal.y), blue: CGFloat(f.petal.z), alpha: 1))
            let petalLength = r * 0.62
            let petalWidth = f.style < 0.5 ? r * 0.22 : r * 0.5
            for i in 0..<count {
                let a = CGFloat(f.spin) + CGFloat(i) * 2 * .pi / CGFloat(count)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: a)
                ctx.fillEllipse(in: CGRect(x: r * 0.15, y: -petalWidth / 2, width: petalLength + r * 0.2, height: petalWidth))
                ctx.restoreGState()
            }
            let coreR = r * (f.style < 0.5 ? 0.3 : 0.2)
            ctx.setFillColor(CGColor(red: CGFloat(f.core.x), green: CGFloat(f.core.y), blue: CGFloat(f.core.z), alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - coreR, y: c.y - coreR, width: coreR * 2, height: coreR * 2))
        }
        ctx.restoreGState()
    }

    /// The flowering water's glass flower, as the shader draws it: an outer whorl of long translucent
    /// petals (pale centre, blue or violet tips), a shorter inner whorl turned half a petal, a pale
    /// glowing heart and fine pale stamens; a touch wider than tall.
    private static func drawGlassFlower(_ f: GrassFlower, at c: CGPoint, radius r: CGFloat, alpha: CGFloat, in ctx: CGContext) {
        let count = max(5, Int(f.petals))
        let seed = (f.spin * 0.15915494 + f.radius * 0.731).truncatingRemainder(dividingBy: 1)
        let aspect = CGFloat(0.78 + 0.17 * (seed * 7.13 + 0.37).truncatingRemainder(dividingBy: 1))
        let tip = (CGFloat(f.petal.x), CGFloat(f.petal.y), CGFloat(f.petal.z))
        let pale = (CGFloat(f.core.x) + (1 - CGFloat(f.core.x)) * 0.25, CGFloat(f.core.y) + (1 - CGFloat(f.core.y)) * 0.25,
                    CGFloat(f.core.z) + (1 - CGFloat(f.core.z)) * 0.25)
        let deep = (tip.0 * 0.8, tip.1 * 0.74, tip.2)

        func petalPath(length L: CGFloat, halfWidth: CGFloat, from t0: CGFloat) -> CGPath {
            // A leaf shape from t0 (0 = centre) to the tip; the cubic bows out to about the half-width.
            let hw = halfWidth * L
            let x0 = L * t0
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x0, y: 0))
            path.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: x0 + (L - x0) * 0.3, y: hw * 1.4),
                          control2: CGPoint(x: x0 + (L - x0) * 0.8, y: hw * 0.9))
            path.addCurve(to: CGPoint(x: x0, y: 0), control1: CGPoint(x: x0 + (L - x0) * 0.8, y: -hw * 0.9),
                          control2: CGPoint(x: x0 + (L - x0) * 0.3, y: -hw * 1.4))
            path.closeSubpath()
            return path
        }

        func whorl(length L: CGFloat, halfWidth: CGFloat, offset: CGFloat, paleAlpha: CGFloat, tipAlpha: CGFloat) {
            let outline = petalPath(length: L, halfWidth: halfWidth, from: 0)
            let tipPart = petalPath(length: L, halfWidth: halfWidth * 0.92, from: 0.42)
            for i in 0..<count {
                let a = CGFloat(f.spin) + (CGFloat(i) + offset) * 2 * .pi / CGFloat(count)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: 1, y: aspect)
                ctx.rotate(by: a)
                ctx.setFillColor(CGColor(red: pale.0, green: pale.1, blue: pale.2, alpha: alpha * paleAlpha))
                ctx.addPath(outline)
                ctx.fillPath()
                ctx.setFillColor(CGColor(red: tip.0, green: tip.1, blue: tip.2, alpha: alpha * tipAlpha))
                ctx.addPath(tipPart)
                ctx.fillPath()
                ctx.setStrokeColor(CGColor(red: deep.0, green: deep.1, blue: deep.2, alpha: alpha * 0.4))
                ctx.setLineWidth(max(0.25, r * 0.035))
                ctx.addPath(outline)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        // A faint blue shadow, the whorls, then the heart.
        ctx.setFillColor(CGColor(red: 0.30, green: 0.36, blue: 0.70, alpha: alpha * 0.08))
        ctx.fillEllipse(in: CGRect(x: c.x + r * 0.1 - r * 0.9, y: c.y + r * 0.14 - r * 0.9 * aspect, width: r * 1.8, height: r * 1.8 * aspect))
        whorl(length: r, halfWidth: 0.38 - 0.03 * CGFloat(count - 5), offset: 0, paleAlpha: 0.42, tipAlpha: 0.55)
        whorl(length: r * 0.58, halfWidth: 0.40, offset: 0.5, paleAlpha: 0.32, tipAlpha: 0.36)
        ctx.setFillColor(CGColor(red: pale.0, green: pale.1, blue: pale.2, alpha: alpha * 0.55))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.36, y: c.y - r * 0.36 * aspect, width: r * 0.72, height: r * 0.72 * aspect))
        let stamen = (0.98 + (tip.0 - 0.98) * 0.22, 0.98 + (tip.1 - 0.98) * 0.22, 1 + (tip.2 - 1) * 0.22)
        ctx.setStrokeColor(CGColor(red: stamen.0, green: stamen.1, blue: stamen.2, alpha: alpha * 0.85))
        ctx.setFillColor(CGColor(red: stamen.0, green: stamen.1, blue: stamen.2, alpha: alpha * 0.85))
        ctx.setLineWidth(max(0.2, r * 0.045))
        ctx.setLineCap(.round)
        for k in 0..<10 {
            let a = (CGFloat(k) + CGFloat(seed)) * 2 * .pi / 10
            let dir = CGPoint(x: cos(a), y: sin(a) * aspect)
            ctx.move(to: CGPoint(x: c.x + dir.x * r * 0.05, y: c.y + dir.y * r * 0.05))
            ctx.addLine(to: CGPoint(x: c.x + dir.x * r * 0.30, y: c.y + dir.y * r * 0.30))
            ctx.strokePath()
            let d = r * 0.045
            ctx.fillEllipse(in: CGRect(x: c.x + dir.x * r * 0.30 - d, y: c.y + dir.y * r * 0.30 - d, width: d * 2, height: d * 2))
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha * 0.9))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.07, y: c.y - r * 0.07, width: r * 0.14, height: r * 0.14))
    }
}

/// HSV helpers shared by the rainbow brush (CPU side).
enum UIColorComponents {
    static func hsv(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let d = mx - mn
        var h: Float = 0
        if d > 1e-5 {
            if mx == r {
                h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
            } else if mx == g {
                h = (b - r) / d + 2
            } else {
                h = (r - g) / d + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    static func rgb(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
        let k = { (n: Float) -> Float in
            let x = (n + h * 6).truncatingRemainder(dividingBy: 6)
            return v - v * s * max(0, min(x, 4 - x, 1))
        }
        return (k(5), k(3), k(1))
    }
}


import SwiftUI
import UIKit

// MARK: - Pen bodies

enum NibStyle {
    case cone
    case chisel
    case flat
    case brush
    case leaf
    case eraser
}

extension Brush {
    var nibStyle: NibStyle {
        switch self {
        case .highlighter: return .chisel
        case .calligraphy, .fountain: return .flat
        case .watercolor, .wave, .sea, .impasto: return .brush
        case .grass: return .leaf
        default: return .cone
        }
    }

    /// Colors of the pen barrel, left to right (gives a cylindrical look).
    func barrel(ink: Color) -> [Color] {
        switch self {
        case .pen: return [Color(white: 0.97), Color(white: 0.84)]
        case .pencil: return [Color(red: 1.0, green: 0.84, blue: 0.32), Color(red: 0.90, green: 0.66, blue: 0.16)]
        case .calligraphy: return [Color(white: 0.24), Color(white: 0.06)]
        case .highlighter: return [ink.opacity(0.75), ink]
        case .wet: return [Color(red: 0.20, green: 0.27, blue: 0.52), Color(red: 0.08, green: 0.12, blue: 0.30)]
        case .watercolor: return [Color(red: 0.78, green: 0.58, blue: 0.38), Color(red: 0.55, green: 0.36, blue: 0.20)]
        case .neon: return [Color(white: 0.26), Color(white: 0.10)]
        case .rainbow: return [.red, .orange, .yellow, .green, .blue, .purple]
        case .glitter: return [Color(white: 0.92), Color(white: 0.62), Color(white: 0.88)]
        case .wave: return [Color(red: 0.38, green: 0.80, blue: 0.90), Color(red: 0.06, green: 0.48, blue: 0.70)]
        case .grass: return [Color(red: 0.48, green: 0.78, blue: 0.36), Color(red: 0.20, green: 0.52, blue: 0.20)]
        case .sea: return [Color(red: 0.25, green: 0.62, blue: 0.90), Color(red: 0.04, green: 0.28, blue: 0.58)]
        case .lava: return [Color(red: 0.30, green: 0.13, blue: 0.08), Color(red: 0.08, green: 0.04, blue: 0.03)]
        case .fountain: return [Color(red: 0.14, green: 0.16, blue: 0.26), Color(red: 0.03, green: 0.04, blue: 0.09)]
        case .gold: return [Color(red: 1.0, green: 0.90, blue: 0.55), Color(red: 0.72, green: 0.52, blue: 0.16)]
        case .chrome: return [Color(white: 0.96), Color(white: 0.52), Color(white: 0.90)]
        case .ice: return [Color(red: 0.86, green: 0.97, blue: 1.0), Color(red: 0.55, green: 0.80, blue: 0.92)]
        case .jelly: return [ink.opacity(0.55), ink]
        case .galaxy: return [Color(red: 0.22, green: 0.11, blue: 0.42), Color(red: 0.03, green: 0.02, blue: 0.10)]
        case .lightning: return [Color(white: 0.22), Color(white: 0.05)]
        case .pearl: return [Color(white: 0.99), Color(red: 0.90, green: 0.86, blue: 0.82)]
        case .impasto: return [Color(red: 0.82, green: 0.62, blue: 0.42), Color(red: 0.55, green: 0.36, blue: 0.20)]
        }
    }

    /// Metal of the grip ring and trim.
    var trimIsGold: Bool {
        switch self {
        case .fountain, .gold, .galaxy, .lava, .pearl: return true
        default: return false
        }
    }
}

/// Draws the tools of the palette like real objects: a turned barrel lit from the left, a metal
/// grip ring, the tip that belongs to the ink and a band in the current ink color. The eraser is a
/// block eraser in its paper sleeve. Drawn in a 30 × 68 box, tip up.
enum ToolArt {
    static let box = CGSize(width: 30, height: 68)

    static func draw(_ brush: Brush?, ink: Color, in ctx: inout GraphicsContext, size: CGSize) {
        ctx.scaleBy(x: size.width / box.width, y: size.height / box.height)
        guard let brush else {
            eraser(&ctx)
            return
        }
        if brush == .pencil {
            pencil(&ctx, ink: ink)
            return
        }
        switch brush.nibStyle {
        case .chisel: highlighter(&ctx, brush: brush, ink: ink)
        case .flat: nibPen(&ctx, brush: brush, ink: ink)
        case .brush: paintBrush(&ctx, brush: brush, ink: ink)
        case .leaf: grassBrush(&ctx, brush: brush, ink: ink)
        case .cone, .eraser: fineliner(&ctx, brush: brush, ink: ink)
        }
    }

    // MARK: Light

    private static func across(_ minX: CGFloat, _ maxX: CGFloat) -> (CGPoint, CGPoint) {
        (CGPoint(x: minX, y: 0), CGPoint(x: maxX, y: 0))
    }

    /// Base colors plus the soft highlight and the shadowed edge of a round body.
    private static func cylinder(_ ctx: inout GraphicsContext, _ path: Path, minX: CGFloat, maxX: CGFloat,
                                 colors: [Color], gloss: Double = 0.55) {
        let (a, b) = across(minX, maxX)
        ctx.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: a, endPoint: b))
        ctx.fill(path, with: .linearGradient(Gradient(stops: [
            .init(color: .black.opacity(0.22), location: 0),
            .init(color: .white.opacity(0), location: 0.12),
            .init(color: .white.opacity(gloss), location: 0.30),
            .init(color: .white.opacity(0), location: 0.50),
            .init(color: .black.opacity(0), location: 0.68),
            .init(color: .black.opacity(0.32), location: 1),
        ]), startPoint: a, endPoint: b))
    }

    private static func metal(_ gold: Bool) -> [Color] {
        gold ? [Color(red: 0.62, green: 0.44, blue: 0.12), Color(red: 1.0, green: 0.94, blue: 0.68),
                Color(red: 0.86, green: 0.66, blue: 0.24), Color(red: 0.52, green: 0.35, blue: 0.08),
                Color(red: 0.92, green: 0.76, blue: 0.38)]
             : [Color(white: 0.48), Color(white: 0.97), Color(white: 0.72), Color(white: 0.40), Color(white: 0.80)]
    }

    private static func metalBand(_ ctx: inout GraphicsContext, _ path: Path, minX: CGFloat, maxX: CGFloat, gold: Bool) {
        let (a, b) = across(minX, maxX)
        ctx.fill(path, with: .linearGradient(Gradient(colors: metal(gold)), startPoint: a, endPoint: b))
    }

    private static func line(_ ctx: inout GraphicsContext, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat,
                             _ color: Color, _ width: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
        ctx.stroke(p, with: .color(color), lineWidth: width)
    }

    private static func trapezoid(top: CGFloat, topHalf: CGFloat, bottom: CGFloat, bottomHalf: CGFloat, cx: CGFloat = 15) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx - bottomHalf, y: bottom))
        p.addLine(to: CGPoint(x: cx - topHalf, y: top))
        p.addLine(to: CGPoint(x: cx + topHalf, y: top))
        p.addLine(to: CGPoint(x: cx + bottomHalf, y: bottom))
        p.closeSubpath()
        return p
    }

    /// Lower body with an ink-colored band, shared by most tools.
    private static func barrel(_ ctx: inout GraphicsContext, brush: Brush, ink: Color, top: CGFloat,
                               minX: CGFloat = 4, maxX: CGFloat = 26, band: CGFloat? = nil) {
        let body = Path(roundedRect: CGRect(x: minX, y: top, width: maxX - minX, height: 80 - top), cornerRadius: 2.5)
        cylinder(&ctx, body, minX: minX, maxX: maxX, colors: brush.barrel(ink: ink))
        let y = band ?? top + 5
        let ring = Path(CGRect(x: minX, y: y, width: maxX - minX, height: 3.6))
        cylinder(&ctx, ring, minX: minX, maxX: maxX, colors: [ink, ink], gloss: 0.4)
        if brush.isPremium {
            star(&ctx, center: CGPoint(x: (minX + maxX) / 2, y: y + 13), radius: 2.6)
        }
    }

    private static func star(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat) {
        var p = Path()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let rr = i % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        ctx.fill(p, with: .linearGradient(Gradient(colors: metal(true)), startPoint: CGPoint(x: c.x - r, y: c.y),
                                          endPoint: CGPoint(x: c.x + r, y: c.y)))
    }

    // MARK: Tools

    /// Pen, gel, neon, metallic and the other fine tips: barrel, grip ring, cone, metal sleeve, ink point.
    private static func fineliner(_ ctx: inout GraphicsContext, brush: Brush, ink: Color) {
        barrel(&ctx, brush: brush, ink: ink, top: 32)
        let grip = trapezoid(top: 24, topHalf: 8, bottom: 32.5, bottomHalf: 10.2)
        metalBand(&ctx, grip, minX: 4.8, maxX: 25.2, gold: brush.trimIsGold)
        line(&ctx, 6, 27.2, 24, 27.2, .black.opacity(0.22), 0.5)
        line(&ctx, 5.5, 30, 24.5, 30, .black.opacity(0.22), 0.5)
        let cone = trapezoid(top: 9, topHalf: 2.5, bottom: 24.2, bottomHalf: 8)
        cylinder(&ctx, cone, minX: 7, maxX: 23, colors: brush.barrel(ink: ink))
        let sleeve = trapezoid(top: 4, topHalf: 1.2, bottom: 9.2, bottomHalf: 2.5)
        metalBand(&ctx, sleeve, minX: 12.5, maxX: 17.5, gold: false)
        let point = Path(roundedRect: CGRect(x: 14.15, y: 0.9, width: 1.7, height: 3.4), cornerRadius: 0.85)
        ctx.fill(point, with: .color(ink))
    }

    /// A sharpened hexagonal pencil: painted facets, scalloped paint edge, wood cone, lead in the ink color.
    private static func pencil(_ ctx: inout GraphicsContext, ink: Color) {
        let wood = trapezoid(top: 10, topHalf: 3.6, bottom: 33, bottomHalf: 11)
        let (wa, wb) = across(4, 26)
        ctx.fill(wood, with: .linearGradient(Gradient(colors: [Color(red: 0.80, green: 0.62, blue: 0.42),
                                                               Color(red: 0.98, green: 0.86, blue: 0.68),
                                                               Color(red: 0.74, green: 0.55, blue: 0.36)]),
                                             startPoint: wa, endPoint: wb))
        var lead = Path()
        lead.move(to: CGPoint(x: 11.4, y: 10.2))
        lead.addLine(to: CGPoint(x: 14.6, y: 1.6))
        lead.addQuadCurve(to: CGPoint(x: 15.4, y: 1.6), control: CGPoint(x: 15, y: 0.9))
        lead.addLine(to: CGPoint(x: 18.6, y: 10.2))
        lead.closeSubpath()
        cylinder(&ctx, lead, minX: 11.4, maxX: 18.6, colors: [ink, ink], gloss: 0.35)
        var paint = Path()
        paint.move(to: CGPoint(x: 4, y: 80))
        paint.addLine(to: CGPoint(x: 4, y: 33))
        paint.addQuadCurve(to: CGPoint(x: 11.33, y: 33), control: CGPoint(x: 7.67, y: 28.5))
        paint.addQuadCurve(to: CGPoint(x: 18.67, y: 33), control: CGPoint(x: 15, y: 28.5))
        paint.addQuadCurve(to: CGPoint(x: 26, y: 33), control: CGPoint(x: 22.33, y: 28.5))
        paint.addLine(to: CGPoint(x: 26, y: 80))
        paint.closeSubpath()
        let yellowDark = Color(red: 0.90, green: 0.66, blue: 0.12)
        let yellow = Color(red: 1.0, green: 0.84, blue: 0.30)
        let yellowLight = Color(red: 1.0, green: 0.93, blue: 0.56)
        ctx.fill(paint, with: .linearGradient(Gradient(stops: [
            .init(color: yellow, location: 0), .init(color: yellowLight, location: 0.33),
            .init(color: yellow, location: 0.335), .init(color: yellow, location: 0.66),
            .init(color: yellowDark, location: 0.665), .init(color: Color(red: 0.78, green: 0.54, blue: 0.08), location: 1),
        ]), startPoint: wa, endPoint: wb))
        line(&ctx, 11.33, 32, 11.33, 80, .black.opacity(0.10), 0.5)
        line(&ctx, 18.67, 32, 18.67, 80, .black.opacity(0.14), 0.5)
        let stripe = Path(CGRect(x: 4, y: 42, width: 22, height: 2.4))
        cylinder(&ctx, stripe, minX: 4, maxX: 26, colors: [ink, ink], gloss: 0.3)
    }

    /// A chunky marker with a cap shoulder and a slanted felt tip.
    private static func highlighter(_ ctx: inout GraphicsContext, brush: Brush, ink: Color) {
        barrel(&ctx, brush: brush, ink: ink, top: 30, minX: 3, maxX: 27, band: 40)
        let shoulder = trapezoid(top: 20, topHalf: 8, bottom: 30.5, bottomHalf: 12)
        cylinder(&ctx, shoulder, minX: 3, maxX: 27, colors: [Color(white: 0.30), Color(white: 0.12)], gloss: 0.35)
        let collar = Path(CGRect(x: 8.5, y: 18.6, width: 13, height: 1.8))
        metalBand(&ctx, collar, minX: 8.5, maxX: 21.5, gold: false)
        var felt = Path()
        felt.move(to: CGPoint(x: 9.6, y: 18.8))
        felt.addLine(to: CGPoint(x: 9.6, y: 5.6))
        felt.addLine(to: CGPoint(x: 20.4, y: 1.8))
        felt.addLine(to: CGPoint(x: 20.4, y: 18.8))
        felt.closeSubpath()
        cylinder(&ctx, felt, minX: 9.6, maxX: 20.4, colors: [ink, ink], gloss: 0.3)
        line(&ctx, 9.6, 5.6, 20.4, 1.8, .white.opacity(0.55), 0.6)
    }

    /// Fountain and calligraphy pens: resin body, trim ring, grip and a metal nib with slit and breather hole.
    private static func nibPen(_ ctx: inout GraphicsContext, brush: Brush, ink: Color) {
        let gold = brush.trimIsGold
        barrel(&ctx, brush: brush, ink: ink, top: 34, minX: 4.5, maxX: 25.5, band: 46)
        let trim = Path(CGRect(x: 4.5, y: 34, width: 21, height: 2))
        metalBand(&ctx, trim, minX: 4.5, maxX: 25.5, gold: gold)
        let grip = trapezoid(top: 21.5, topHalf: 5.6, bottom: 34.2, bottomHalf: 9)
        cylinder(&ctx, grip, minX: 6, maxX: 24, colors: brush.barrel(ink: ink), gloss: 0.45)
        var nib = Path()
        nib.move(to: CGPoint(x: 9.6, y: 22.5))
        if brush == .calligraphy {
            nib.addQuadCurve(to: CGPoint(x: 11.4, y: 3.2), control: CGPoint(x: 9.4, y: 10))
            nib.addLine(to: CGPoint(x: 18.6, y: 3.2))
            nib.addQuadCurve(to: CGPoint(x: 20.4, y: 22.5), control: CGPoint(x: 20.6, y: 10))
        } else {
            nib.addQuadCurve(to: CGPoint(x: 15, y: 1.4), control: CGPoint(x: 9.0, y: 8.5))
            nib.addQuadCurve(to: CGPoint(x: 20.4, y: 22.5), control: CGPoint(x: 21.0, y: 8.5))
        }
        nib.closeSubpath()
        metalBand(&ctx, nib, minX: 9.6, maxX: 20.4, gold: gold)
        ctx.stroke(nib, with: .color(.black.opacity(0.25)), lineWidth: 0.4)
        line(&ctx, 15, 13.6, 15, brush == .calligraphy ? 3.2 : 2.2, .black.opacity(0.55), 0.55)
        ctx.fill(Path(ellipseIn: CGRect(x: 13.8, y: 12.6, width: 2.4, height: 2.4)), with: .color(.black.opacity(0.6)))
        var engraving = Path()
        engraving.move(to: CGPoint(x: 11.2, y: 19.5))
        engraving.addQuadCurve(to: CGPoint(x: 18.8, y: 19.5), control: CGPoint(x: 15, y: 16.5))
        ctx.stroke(engraving, with: .color(.black.opacity(0.18)), lineWidth: 0.4)
        let tipY: CGFloat = brush == .calligraphy ? 2.6 : 1.0
        let tipW: CGFloat = brush == .calligraphy ? 7.2 : 1.8
        ctx.fill(Path(roundedRect: CGRect(x: 15 - tipW / 2, y: tipY, width: tipW, height: 1.3), cornerRadius: 0.6), with: .color(ink))
    }

    /// Watercolor and the other wet brushes: lacquered handle, crimped ferrule, a tuft loaded with ink.
    private static func paintBrush(_ ctx: inout GraphicsContext, brush: Brush, ink: Color) {
        barrel(&ctx, brush: brush, ink: ink, top: 34, minX: 6, maxX: 24, band: 44)
        let ferrule = trapezoid(top: 17.5, topHalf: 6.6, bottom: 34.2, bottomHalf: 9)
        metalBand(&ctx, ferrule, minX: 6, maxX: 24, gold: brush.trimIsGold)
        line(&ctx, 6.8, 29.6, 23.2, 29.6, .black.opacity(0.25), 0.5)
        line(&ctx, 6.9, 31.4, 23.1, 31.4, .black.opacity(0.25), 0.5)
        var tuft = Path()
        tuft.move(to: CGPoint(x: 8.6, y: 18.2))
        tuft.addQuadCurve(to: CGPoint(x: 15, y: 0.8), control: CGPoint(x: 6.6, y: 7))
        tuft.addQuadCurve(to: CGPoint(x: 21.4, y: 18.2), control: CGPoint(x: 23.4, y: 7))
        tuft.closeSubpath()
        ctx.fill(tuft, with: .linearGradient(Gradient(stops: [
            .init(color: ink, location: 0), .init(color: ink, location: 0.55),
            .init(color: Color(red: 0.93, green: 0.86, blue: 0.72), location: 1),
        ]), startPoint: CGPoint(x: 0, y: 1), endPoint: CGPoint(x: 0, y: 18)))
        cylinder(&ctx, tuft, minX: 7.5, maxX: 22.5, colors: [.clear, .clear], gloss: 0.35)
        for x in [11.5, 14.0, 16.5, 18.6] as [CGFloat] {
            line(&ctx, x, 17.6, 15 + (x - 15) * 0.25, 4, .white.opacity(0.22), 0.35)
        }
    }

    /// The grass brush: a ferrule holding a little tuft of blades with a flower on top.
    private static func grassBrush(_ ctx: inout GraphicsContext, brush: Brush, ink: Color) {
        barrel(&ctx, brush: brush, ink: ink, top: 34, minX: 5, maxX: 25, band: 44)
        let ferrule = trapezoid(top: 24, topHalf: 7.4, bottom: 34.2, bottomHalf: 10)
        metalBand(&ctx, ferrule, minX: 5, maxX: 25, gold: false)
        let blades: [(base: CGFloat, tip: CGPoint)] = [
            (9, CGPoint(x: 6.5, y: 11)), (11.5, CGPoint(x: 10.5, y: 6)), (15, CGPoint(x: 15.5, y: 4.5)),
            (18.5, CGPoint(x: 20, y: 7)), (21, CGPoint(x: 24, y: 12)),
        ]
        for (i, blade) in blades.enumerated() {
            var p = Path()
            p.move(to: CGPoint(x: blade.base - 1.8, y: 24.5))
            p.addQuadCurve(to: blade.tip, control: CGPoint(x: blade.base - 1.2, y: 14))
            p.addQuadCurve(to: CGPoint(x: blade.base + 1.8, y: 24.5), control: CGPoint(x: blade.base + 1.6, y: 14))
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [ink.opacity(i % 2 == 0 ? 0.85 : 1), ink]),
                                              startPoint: blade.tip, endPoint: CGPoint(x: blade.base, y: 24.5)))
            ctx.fill(p, with: .color(.black.opacity(i % 2 == 0 ? 0 : 0.12)))
        }
        let flower = CGPoint(x: 15.5, y: 4.6)
        for k in 0..<5 {
            let a = CGFloat(k) * 2 * .pi / 5 - .pi / 2
            let petal = CGRect(x: flower.x + cos(a) * 2.2 - 1.7, y: flower.y + sin(a) * 2.2 - 1.7, width: 3.4, height: 3.4)
            ctx.fill(Path(ellipseIn: petal), with: .color(Color(red: 1, green: 0.72, blue: 0.84)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: flower.x - 1.2, y: flower.y - 1.2, width: 2.4, height: 2.4)),
                 with: .color(Color(red: 1, green: 0.78, blue: 0.2)))
    }

    /// A block eraser in a paper sleeve, seen slightly from the side so it has depth.
    private static func eraser(_ ctx: inout GraphicsContext) {
        let pink = Color(red: 0.99, green: 0.72, blue: 0.76)
        let pinkLight = Color(red: 1.0, green: 0.86, blue: 0.88)
        let pinkDark = Color(red: 0.86, green: 0.52, blue: 0.58)
        // Rubber: top face, side face, front face.
        var top = Path()
        top.move(to: CGPoint(x: 4, y: 7.5))
        top.addQuadCurve(to: CGPoint(x: 8, y: 4), control: CGPoint(x: 4.6, y: 4.6))
        top.addLine(to: CGPoint(x: 26, y: 4))
        top.addLine(to: CGPoint(x: 22, y: 7.5))
        top.closeSubpath()
        ctx.fill(top, with: .color(pinkLight))
        var side = Path()
        side.move(to: CGPoint(x: 22, y: 7.5))
        side.addLine(to: CGPoint(x: 26, y: 4))
        side.addLine(to: CGPoint(x: 26, y: 27))
        side.addLine(to: CGPoint(x: 22, y: 30.5))
        side.closeSubpath()
        ctx.fill(side, with: .color(pinkDark))
        let front = Path(roundedRect: CGRect(x: 4, y: 7.5, width: 18, height: 24), cornerSize: CGSize(width: 1.2, height: 1.2))
        ctx.fill(front, with: .linearGradient(Gradient(colors: [pinkLight, pink, pink]),
                                              startPoint: CGPoint(x: 0, y: 7.5), endPoint: CGPoint(x: 0, y: 30)))
        line(&ctx, 6.2, 10.5, 6.2, 27, .white.opacity(0.45), 1.1)
        // Paper sleeve: front and side, with a white band like a stationery brand stripe.
        let blue = Color(red: 0.16, green: 0.40, blue: 0.82)
        let blueDark = Color(red: 0.08, green: 0.25, blue: 0.60)
        var sleeveSide = Path()
        sleeveSide.move(to: CGPoint(x: 23, y: 29))
        sleeveSide.addLine(to: CGPoint(x: 27, y: 25.5))
        sleeveSide.addLine(to: CGPoint(x: 27, y: 80))
        sleeveSide.addLine(to: CGPoint(x: 23, y: 80))
        sleeveSide.closeSubpath()
        ctx.fill(sleeveSide, with: .color(blueDark))
        let sleeve = Path(CGRect(x: 3, y: 29, width: 20, height: 51))
        ctx.fill(sleeve, with: .linearGradient(Gradient(colors: [blue.opacity(0.92), blue]),
                                               startPoint: CGPoint(x: 3, y: 0), endPoint: CGPoint(x: 23, y: 0)))
        ctx.fill(Path(CGRect(x: 3, y: 38, width: 20, height: 5)), with: .color(.white.opacity(0.92)))
        ctx.fill(Path(CGRect(x: 3, y: 44.4, width: 20, height: 1.2)), with: .color(Color(red: 0.90, green: 0.22, blue: 0.26)))
        var fold = Path()
        fold.move(to: CGPoint(x: 23, y: 38))
        fold.addLine(to: CGPoint(x: 27, y: 34.5))
        fold.addLine(to: CGPoint(x: 27, y: 39.5))
        fold.addLine(to: CGPoint(x: 23, y: 43))
        fold.closeSubpath()
        ctx.fill(fold, with: .color(.white.opacity(0.7)))
        line(&ctx, 3, 29, 23, 29, .black.opacity(0.18), 0.5)
    }
}

/// One tool drawn by `ToolArt`.
struct ToolArtwork: View {
    let brush: Brush?
    let ink: Color

    var body: some View {
        Canvas { ctx, size in
            ToolArt.draw(brush, ink: ink, in: &ctx, size: size)
        }
        .frame(width: ToolArt.box.width, height: ToolArt.box.height)
    }
}

/// The tool laid at an angle in a small square, for compact buttons and the radial palette.
struct ToolIcon: View {
    let brush: Brush?
    let ink: Color
    var side: CGFloat = 28

    var body: some View {
        ToolArtwork(brush: brush, ink: ink)
            .scaleEffect(side / ToolArt.box.height * 1.02)
            .rotationEffect(.degrees(40))
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.18), radius: 1.2, y: 0.8)
            .accessibilityHidden(true)
    }
}

/// A little pen standing in the palette, like a tool in a pencil case. The selected one is raised.
struct PenBodyView: View {
    let brush: Brush?
    let ink: Color
    let selected: Bool

    var body: some View {
        ToolArtwork(brush: brush, ink: ink)
            .frame(width: 30, height: 68, alignment: .top)
            .shadow(color: .black.opacity(selected ? 0.28 : 0.14), radius: selected ? 5 : 2.5, x: 1, y: 2)
            .offset(y: selected ? 2 : 18)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: selected)
    }
}

// MARK: - Floating palette

struct FloatingToolPalette: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    @Binding var collapsed: Bool
    @State private var inspector: Brush?
    @State private var showEraserOptions = false
    @State private var showTextPenOptions = false
    @State private var showColors = false
    @State private var group: BrushGroup = .writing

    var body: some View {
        Group {
            if collapsed {
                compact
            } else {
                full
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 66)
        .glassCapsule()
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: collapsed)
        .onAppear {
            group = editor.activeBrush.group
        }
        .onChange(of: editor.tool) { _, tool in
            if let brush = tool.selectedBrush, brush.group != group {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { group = brush.group }
            }
        }
    }

    /// Four small tabs: writing, art, living and premium 3D brushes.
    private var groupGrid: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                groupButton(.writing)
                groupButton(.art)
            }
            GridRow {
                groupButton(.living)
                groupButton(.premium)
            }
        }
    }

    private func groupButton(_ g: BrushGroup) -> some View {
        let selected = group == g
        let fill: AnyShapeStyle
        if selected {
            fill = g == .premium ? AnyShapeStyle(Theme.ai) : AnyShapeStyle(Theme.ink)
        } else {
            fill = AnyShapeStyle(Color.primary.opacity(0.07))
        }
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { group = g }
        } label: {
            Image(systemName: g.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(g.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var compact: some View {
        HStack(spacing: 10) {
            undoRedo
            Divider().frame(height: 30)
            Button {
                collapsed = false
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(editor.color(for: editor.activeBrush).swiftUIColor)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    switch editor.tool {
                    case .eraser:
                        ToolIcon(brush: nil, ink: .clear, side: 30)
                    case let .brush(brush):
                        ToolIcon(brush: brush, ink: editor.color(for: brush).swiftUIColor, side: 30)
                    default:
                        Image(systemName: editor.tool.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 30, height: 30)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Araçları göster"))
        }
    }

    private var full: some View {
        HStack(spacing: 8) {
            undoRedo
            Divider().frame(height: 34)
            groupGrid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(group.brushes) { brush in
                        penButton(brush)
                    }
                    textPenButton
                    eraserButton
                }
                .padding(.horizontal, 4)
                .frame(height: 66, alignment: .bottom)
            }
            .frame(maxWidth: 560)
            .clipped()
            Divider().frame(height: 34)
            colorWell
            if !editor.isPDF {
                Button {
                    editor.addPage()
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.t("Sayfa ekle"))
            }
            Button {
                collapsed = true
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Araçları gizle"))
        }
    }

    private var undoRedo: some View {
        HStack(spacing: 2) {
            Button {
                editor.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .disabled(!editor.canUndo)
            .accessibilityLabel(Loc.t("Geri al"))
            Button {
                editor.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .disabled(!editor.canRedo)
            .accessibilityLabel(Loc.t("Yinele"))
        }
        .buttonStyle(.plain)
    }

    private func penButton(_ brush: Brush) -> some View {
        let selected = editor.tool == .brush(brush)
        return Button {
            if selected {
                inspector = brush
            } else {
                editor.select(.brush(brush))
            }
        } label: {
            PenBodyView(brush: brush, ink: editor.color(for: brush).swiftUIColor, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(brush.title)
        .accessibilityHint(selected ? Loc.t("Ayarlarını açmak için tekrar dokun") : "")
        .popover(isPresented: Binding(get: { inspector == brush }, set: { if !$0 { inspector = nil } })) {
            BrushInspector(editor: editor, brush: brush)
                .environmentObject(settings)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// The text pen: the last pen's ink, labeled "Metin". What it writes becomes text on the lines.
    private var textPenButton: some View {
        let selected = editor.tool == .textPen
        let brush = editor.lastBrush
        return Button {
            if selected {
                showTextPenOptions = true
            } else {
                editor.select(.textPen)
            }
        } label: {
            ZStack(alignment: .bottom) {
                PenBodyView(brush: brush, ink: editor.color(for: brush).swiftUIColor, selected: selected)
                // A quiet monochrome badge in the system's material, like the tool marks in Apple's apps.
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .offset(y: -3)
            }
            .frame(width: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.t("Metin kalemi"))
        .accessibilityHint(selected ? Loc.t("Ayarlarını açmak için tekrar dokun") : Loc.t("Elle yaz, çizgilere hizalı yazıya dönüşsün"))
        .popover(isPresented: $showTextPenOptions) {
            TextPenInspector(editor: editor)
                .environmentObject(settings)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var eraserButton: some View {
        let selected = editor.tool == .eraser
        return Button {
            if selected {
                showEraserOptions = true
            } else {
                editor.select(.eraser)
            }
        } label: {
            PenBodyView(brush: nil, ink: .clear, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.t("Silgi"))
        .popover(isPresented: $showEraserOptions) {
            EraserInspector(editor: editor)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var colorWell: some View {
        let brush = editor.activeBrush
        return Button {
            showColors = true
        } label: {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(editor.color(for: brush).swiftUIColor)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.t("Renk ve kalınlık"))
        .popover(isPresented: $showColors) {
            BrushInspector(editor: editor, brush: brush)
                .environmentObject(settings)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Inspector

struct BrushInspector: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    let brush: Brush

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: brush.symbol)
                        .font(.title2)
                        .foregroundStyle(editor.color(for: brush).swiftUIColor)
                        .frame(width: 44, height: 44)
                        .background(editor.color(for: brush).swiftUIColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(brush.title)
                            .font(.headline)
                        Text(brush.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                StrokePreview(brush: brush, color: editor.color(for: brush).swiftUIColor,
                              width: CGFloat(editor.width(for: brush)))
                    .frame(height: 72)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.08)))

                section(Loc.t("Renk")) {
                    ColorGrid(editor: editor, brush: brush)
                }

                section(Loc.t("Kalınlık")) {
                    HStack {
                        Image(systemName: "circle.fill").font(.system(size: 6))
                        Slider(value: Binding(get: { Double(editor.width(for: brush)) },
                                              set: { editor.setWidth(Float($0), for: brush) }),
                               in: Double(brush.widthRange.lowerBound)...Double(brush.widthRange.upperBound))
                        Image(systemName: "circle.fill").font(.system(size: 16))
                    }
                    .foregroundStyle(.secondary)
                }

                extraOptions
            }
            .padding(18)
        }
        .frame(width: 330)
        .frame(maxHeight: 560)
        .onDisappear {
            let c = editor.color(for: brush)
            if !brush.palette.contains(c) {
                settings.rememberColor(c)
            }
        }
    }

    @ViewBuilder
    private var extraOptions: some View {
        switch brush {
        case .calligraphy:
            section(Loc.t("Uç açısı: {0}°", "\(Int(settings.nibAngle))")) {
                Slider(value: $settings.nibAngle, in: 0...180, step: 1)
                Toggle(Loc.t("Pencil Pro'yu döndürünce uç da dönsün"), isOn: $settings.rollRotatesNib)
                    .font(.subheadline)
            }
        case .grass:
            section(Loc.t("Çiçekler")) {
                Picker(Loc.t("Çiçekler"), selection: $settings.flowerLevel) {
                    Text(Loc.t("Yok")).tag(0)
                    Text(Loc.t("Az")).tag(1)
                    Text(Loc.t("Bol")).tag(2)
                }
                .pickerStyle(.segmented)
                Text(Loc.t("Kısa çim çizdikçe biter, küçük yazıda da harfler okunur. Kalemi kaldırdıktan 1–2 saniye sonra tomurcuklar açar."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(Loc.t("Rüzgârda salınsın"), isOn: $settings.animations)
                    .font(.subheadline)
            }
        case .wet:
            section(Loc.t("Kuruma süresi: {0} sn", "\(Int(settings.dryDuration))")) {
                Slider(value: $settings.dryDuration, in: 1...15, step: 1)
            }
        case .lava:
            section(Loc.t("Soğuma süresi: {0} sn", "\(Int(settings.lavaCoolDuration))")) {
                Slider(value: $settings.lavaCoolDuration, in: 2...20, step: 1)
                Text(Loc.t("Lav önce akar ve parlar, sonra kabuk bağlar; çatlaklarındaki kor yanmaya devam eder."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(Loc.t("Akış ve kor animasyonu"), isOn: $settings.animations)
                    .font(.subheadline)
            }
        case .fountain:
            Label(Loc.t("Bastırdıkça uç açılır ve çizgi kalınlaşır; aşağı çekişler daha dolgun çıkar. Mürekkep kabarık ve parlak kalır."),
                  systemImage: "applepencil")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .wave, .glitter, .sea, .ice, .jelly, .galaxy, .lightning:
            Toggle(Loc.t("Animasyon"), isOn: $settings.animations)
                .font(.subheadline)
        case .pencil:
            Label(Loc.t("Pencil'ı yatırarak geniş ve yumuşak tara, bastırdıkça koyulaşır."), systemImage: "applepencil")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

struct TextPenInspector: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Loc.t("Metin kalemi"), systemImage: "pencil.and.scribble")
                .font(.headline)
            Text(Loc.t("Elle yaz; kalemi kaldırıp kısa bir an bekleyince yazdıkların şablonun çizgilerine hizalı, düzgün yazıya dönüşür. Mürekkep ve renk son seçtiğin kalemden gelir; 3B mürekkepler 3B kalır."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(Loc.t("Mürekkep"))
                    .font(.subheadline)
                Spacer()
                ToolIcon(brush: editor.lastBrush, ink: editor.color(for: editor.lastBrush).swiftUIColor, side: 28)
                Text(editor.lastBrush.title)
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(Loc.t("Bekleme süresi"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Picker(Loc.t("Bekleme süresi"), selection: $settings.textPenDelay) {
                    Text(Loc.t("Hızlı")).tag(0.8)
                    Text("Normal").tag(1.3)
                    Text(Loc.t("Yavaş")).tag(2.2)
                }
                .pickerStyle(.segmented)
            }
            Text(Loc.t("Başka bir kalem seçince bekleyen yazı hemen dönüştürülür. Geri al ile el yazısına dönebilirsin."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 320)
    }
}

struct EraserInspector: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Loc.t("Silgi"), systemImage: "eraser")
                .font(.headline)
            Picker(Loc.t("Silgi"), selection: $editor.eraserMode) {
                ForEach(EraserMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Image(systemName: "circle").font(.caption)
                Slider(value: Binding(get: { Double(editor.eraserSize) }, set: { editor.eraserSize = Float($0) }), in: 6...60)
                Image(systemName: "circle").font(.title3)
            }
            .foregroundStyle(.secondary)
            Text(Loc.t("Pencil Pro'yu sık: silgiye geçer, tekrar sıkınca kalemin geri gelir; silmeyi bitirince de kaldığın kaleme, fosforlu kaleme… kendiliğinden döner. Kaleme çift dokununca açılan menüde de silgi var."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 300)
    }
}

struct ColorGrid: View {
    @ObservedObject var editor: EditorModel
    @EnvironmentObject private var settings: AppSettings
    let brush: Brush

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(brush.palette.enumerated()), id: \.offset) { _, color in
                    swatch(color)
                }
                ColorPicker(Loc.t("Özel renk"), selection: Binding(get: { editor.color(for: brush).swiftUIColor },
                                                          set: { editor.setColor(InkColor($0), for: brush) }),
                            supportsOpacity: brush == .watercolor || brush == .highlighter)
                    .labelsHidden()
                    .frame(width: 32, height: 32)
            }
            let recents = settings.recentColors.filter { !brush.palette.contains($0) }
            if !recents.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(recents.prefix(7).enumerated()), id: \.offset) { _, color in
                        swatch(color, small: true)
                    }
                }
            }
        }
    }

    private func swatch(_ color: InkColor, small: Bool = false) -> some View {
        let selected = editor.color(for: brush) == color
        let size: CGFloat = small ? 24 : 30
        return Circle()
            .fill(color.swiftUIColor)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.85 : 0), lineWidth: 2).padding(-3))
            .contentShape(Circle())
            .onTapGesture {
                editor.setColor(color, for: brush)
                editor.onHaptic?(.selection)
            }
            .accessibilityLabel(Loc.t("Renk"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A live sample stroke for the inspector.
struct StrokePreview: View {
    let brush: Brush
    let color: Color
    let width: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height * 0.62
            var path = Path()
            path.move(to: CGPoint(x: 16, y: mid))
            path.addCurve(to: CGPoint(x: size.width - 16, y: mid),
                          control1: CGPoint(x: size.width * 0.35, y: mid - size.height * 0.55),
                          control2: CGPoint(x: size.width * 0.62, y: mid + size.height * 0.35))
            let lw = max(1.5, min(width, size.height * 0.35))
            let round = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
            switch brush {
            case .rainbow:
                ctx.stroke(path, with: .linearGradient(Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple]),
                                                       startPoint: CGPoint(x: 0, y: mid), endPoint: CGPoint(x: size.width, y: mid)),
                           style: round)
            case .neon:
                var glow = ctx
                glow.addFilter(.blur(radius: lw * 1.2))
                glow.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lw * 2.4, lineCap: .round))
                ctx.stroke(path, with: .color(color), style: round)
                ctx.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: lw * 0.45, lineCap: .round))
            case .watercolor:
                ctx.stroke(path, with: .color(color.opacity(0.42)), style: round)
            case .pencil:
                ctx.stroke(path, with: .color(color.opacity(0.72)), style: round)
            case .highlighter:
                ctx.stroke(path, with: .color(color.opacity(0.65)), style: StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .round))
            case .calligraphy:
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1, lw * 0.35), lineCap: .round))
                var thick = Path()
                thick.move(to: CGPoint(x: size.width * 0.3, y: mid - size.height * 0.28))
                thick.addLine(to: CGPoint(x: size.width * 0.42, y: mid - size.height * 0.05))
                ctx.stroke(thick, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
            case .glitter:
                ctx.stroke(path, with: .color(color), style: round)
                for i in 0..<14 {
                    let x = 20 + CGFloat(i) * (size.width - 40) / 13
                    let y = mid + CGFloat((i * 37) % 11) - 5 - sin(CGFloat(i)) * size.height * 0.15
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(.white))
                }
            case .grass:
                var ground = Path()
                ground.move(to: CGPoint(x: 16, y: size.height - 10))
                ground.addLine(to: CGPoint(x: size.width - 16, y: size.height - 10))
                ctx.stroke(ground, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                let flowerColors: [Color] = [.pink, .white, .yellow, .purple]
                var x: CGFloat = 18
                var k = 0
                while x < size.width - 16 {
                    let h = 7 + CGFloat((k * 53) % 9)
                    let lean = CGFloat((k * 29) % 7) - 3
                    var blade = Path()
                    blade.move(to: CGPoint(x: x - 1.4, y: size.height - 10))
                    blade.addQuadCurve(to: CGPoint(x: x + lean, y: size.height - 10 - h), control: CGPoint(x: x, y: size.height - 10 - h * 0.6))
                    blade.addQuadCurve(to: CGPoint(x: x + 1.4, y: size.height - 10), control: CGPoint(x: x + 1, y: size.height - 10 - h * 0.6))
                    ctx.fill(blade, with: .color(color))
                    if k % 7 == 3 {
                        let c = CGPoint(x: x + lean, y: size.height - 14 - h)
                        let flower = flowerColors[(k / 7) % flowerColors.count]
                        for p in 0..<5 {
                            let a = CGFloat(p) * 2 * .pi / 5
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x + cos(a) * 4 - 3, y: c.y + sin(a) * 4 - 3, width: 6, height: 6)), with: .color(flower))
                        }
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(.orange))
                    }
                    x += 4
                    k += 1
                }
            case .sea:
                ctx.stroke(path, with: .linearGradient(Gradient(colors: [color, Color(red: 0.3, green: 0.85, blue: 0.88), color]),
                                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)),
                           style: round)
                for i in 0..<7 {
                    let px: CGFloat = 26 + CGFloat(i) * (size.width - 52) / 6
                    let phase: CGFloat = (px - 16) / (size.width - 32) * 2 * CGFloat.pi
                    let py: CGFloat = mid - sin(phase) * size.height * 0.16 - lw * 0.2
                    ctx.fill(Path(ellipseIn: CGRect(x: px - lw * 0.25, y: py - lw * 0.35, width: lw * 0.5, height: lw * 0.7)),
                             with: .color(.white.opacity(0.9)))
                }
            case .lava:
                ctx.stroke(path, with: .color(Color(red: 0.13, green: 0.08, blue: 0.07)), style: round)
                var glow = ctx
                glow.addFilter(.blur(radius: lw * 0.6))
                glow.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lw * 0.55, lineCap: .round))
                ctx.stroke(path, with: .color(Color(red: 1, green: 0.85, blue: 0.45)), style: StrokeStyle(lineWidth: lw * 0.2, lineCap: .round))
            case .lightning:
                var glow = ctx
                glow.addFilter(.blur(radius: lw * 1.4))
                glow.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lw * 2, lineCap: .round))
                ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: max(1, lw * 0.3), lineCap: .round))
            case .gold, .chrome:
                let stops: [Color] = brush == .gold
                    ? [Color(red: 1, green: 0.95, blue: 0.7), color, Color(red: 0.45, green: 0.3, blue: 0.08), color]
                    : [.white, Color(red: 0.55, green: 0.68, blue: 0.9), Color(white: 0.2), Color(white: 0.85)]
                ctx.stroke(path, with: .linearGradient(Gradient(colors: stops), startPoint: CGPoint(x: 0, y: mid - lw),
                                                       endPoint: CGPoint(x: 0, y: mid + lw)), style: round)
            case .galaxy:
                ctx.stroke(path, with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.03, blue: 0.2), color, Color(red: 0.08, green: 0.03, blue: 0.2)]),
                                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)),
                           style: round)
                for i in 0..<16 {
                    let px: CGFloat = 20 + CGFloat(i) * (size.width - 40) / 15
                    let jitter: CGFloat = CGFloat((i * 37) % 9) - 4
                    let py: CGFloat = mid + jitter - sin(CGFloat(i)) * size.height * 0.12
                    ctx.fill(Path(ellipseIn: CGRect(x: px - 0.9, y: py - 0.9, width: 1.8, height: 1.8)), with: .color(.white))
                }
            case .pearl:
                for i in 0..<12 {
                    let px: CGFloat = 22 + CGFloat(i) * (size.width - 44) / 11
                    let phase: CGFloat = (px - 16) / (size.width - 32) * 2 * CGFloat.pi
                    let py: CGFloat = mid - sin(phase) * size.height * 0.2
                    let r = lw * 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [.white, color, color.opacity(0.85)]),
                                                   center: CGPoint(x: px - r * 0.35, y: py - r * 0.4), startRadius: 0, endRadius: r * 1.2))
                }
            case .ice, .jelly, .fountain, .impasto:
                let opacity: Double = brush == .ice ? 0.6 : (brush == .jelly ? 0.82 : 1)
                ctx.stroke(path, with: .color(color.opacity(opacity)), style: round)
                var shine = ctx
                shine.translateBy(x: -lw * 0.12, y: -lw * 0.18)
                shine.stroke(path, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: lw * 0.22, lineCap: .round))
            default:
                ctx.stroke(path, with: .color(color), style: round)
            }
        }
    }
}


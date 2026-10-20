import CoreGraphics
import Foundation
import Metal
import UIKit

// MARK: - Templates

enum TemplateCategory: String, CaseIterable, Identifiable {
    case basic
    case technical
    case planning
    case professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return Loc.t("Temel")
        case .technical: return Loc.t("Teknik")
        case .planning: return Loc.t("Planlama")
        case .professional: return Loc.t("Profesyonel")
        }
    }

    var styles: [PaperStyle] {
        PaperStyle.allCases.filter { $0.category == self }
    }
}

/// Page template of a notebook. Raw values are stored in the library index; existing ones never change.
enum PaperStyle: String, CaseIterable, Identifiable, Codable {
    case plain
    case lined
    case grid
    case dotted
    case narrowLined
    case smallGrid
    case engineering
    case isometric
    case hexagon
    case music
    case handwriting
    case todo
    case daily
    case weekly
    case monthly
    case meeting
    case resume
    case letter
    case cornell
    case storyboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return Loc.t("Düz")
        case .lined: return Loc.t("Çizgili")
        case .grid: return Loc.t("Kareli")
        case .dotted: return Loc.t("Noktalı")
        case .narrowLined: return Loc.t("Dar çizgili")
        case .smallGrid: return Loc.t("Küçük kareli")
        case .engineering: return Loc.t("Mühendislik")
        case .isometric: return Loc.t("İzometrik")
        case .hexagon: return Loc.t("Altıgen")
        case .music: return Loc.t("Nota kâğıdı")
        case .handwriting: return Loc.t("Güzel yazı")
        case .todo: return Loc.t("Yapılacaklar")
        case .daily: return Loc.t("Günlük plan")
        case .weekly: return Loc.t("Haftalık plan")
        case .monthly: return Loc.t("Aylık takvim")
        case .meeting: return Loc.t("Toplantı notu")
        case .resume: return Loc.t("Özgeçmiş (CV)")
        case .letter: return Loc.t("Mektup / ön yazı")
        case .cornell: return Loc.t("Cornell notları")
        case .storyboard: return "Storyboard"
        }
    }

    var symbol: String {
        switch self {
        case .plain: return "doc"
        case .lined: return "line.3.horizontal"
        case .grid: return "squareshape.split.3x3"
        case .dotted: return "circle.grid.3x3"
        case .narrowLined: return "text.justify"
        case .smallGrid: return "grid"
        case .engineering: return "ruler"
        case .isometric: return "cube"
        case .hexagon: return "hexagon"
        case .music: return "music.note.list"
        case .handwriting: return "textformat"
        case .todo: return "checklist"
        case .daily: return "clock"
        case .weekly: return "calendar.day.timeline.left"
        case .monthly: return "calendar"
        case .meeting: return "person.3"
        case .resume: return "person.text.rectangle"
        case .letter: return "envelope"
        case .cornell: return "rectangle.split.2x1"
        case .storyboard: return "film"
        }
    }

    var category: TemplateCategory {
        switch self {
        case .plain, .lined, .grid, .dotted, .narrowLined, .smallGrid: return .basic
        case .engineering, .isometric, .hexagon, .music, .handwriting: return .technical
        case .todo, .daily, .weekly, .monthly, .meeting: return .planning
        case .resume, .letter, .cornell, .storyboard: return .professional
        }
    }

    /// Simple patterns are drawn by the paper shader (sharp at any zoom).
    var shaderIndex: UInt32 {
        switch self {
        case .lined: return 1
        case .grid: return 2
        case .dotted: return 3
        default: return 0
        }
    }

    /// Everything else is rendered with Core Graphics into a texture.
    var usesTexture: Bool {
        switch self {
        case .plain, .lined, .grid, .dotted: return false
        default: return true
        }
    }
}

// MARK: - Drawing

/// Draws a template into a y-down context whose user space is page points. Shared by the screen
/// (via textures), thumbnails, PDF export, page images for the assistant and the template gallery.
enum PaperDrawer {
    static func draw(_ style: PaperStyle, size: CGSize, in ctx: CGContext) {
        ctx.saveGState()
        UIGraphicsPushContext(ctx)
        defer {
            UIGraphicsPopContext()
            ctx.restoreGState()
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let d = Draw(ctx: ctx, size: size)
        switch style {
        case .plain: break
        case .lined: lined(d, spacing: 28, top: 84, margin: 72)
        case .narrowLined: lined(d, spacing: 21, top: 72, margin: 60)
        case .grid: grid(d, step: 20, color: Draw.gridBlue, width: 0.7)
        case .smallGrid: grid(d, step: 14.17, color: Draw.gridBlue, width: 0.45)
        case .dotted: dotted(d)
        case .engineering: engineering(d)
        case .isometric: isometric(d)
        case .hexagon: hexagon(d)
        case .music: music(d)
        case .handwriting: handwriting(d)
        case .todo: todo(d)
        case .daily: daily(d)
        case .weekly: weekly(d)
        case .monthly: monthly(d)
        case .meeting: meeting(d)
        case .resume: resume(d)
        case .letter: letter(d)
        case .cornell: cornell(d)
        case .storyboard: storyboard(d)
        }
    }

    /// Small drawing helper bound to one context.
    private struct Draw {
        let ctx: CGContext
        let size: CGSize

        static let lineBlue = CGColor(red: 0.66, green: 0.80, blue: 0.95, alpha: 1)
        static let gridBlue = CGColor(red: 0.78, green: 0.85, blue: 0.93, alpha: 1)
        static let rule = CGColor(red: 0.80, green: 0.83, blue: 0.88, alpha: 1)
        static let faint = CGColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        static let margin = CGColor(red: 0.96, green: 0.62, blue: 0.62, alpha: 1)
        static let accent = UIColor(red: 0.10, green: 0.33, blue: 0.80, alpha: 1)
        static let label = UIColor(white: 0.45, alpha: 1)
        static let placeholder = UIColor(white: 0.82, alpha: 1)

        var w: CGFloat { size.width }
        var h: CGFloat { size.height }

        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat,
                  _ color: CGColor = Draw.rule, _ width: CGFloat = 0.7, dash: [CGFloat] = []) {
            ctx.saveGState()
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
            ctx.move(to: CGPoint(x: x0, y: y0))
            ctx.addLine(to: CGPoint(x: x1, y: y1))
            ctx.strokePath()
            ctx.restoreGState()
        }

        func box(_ r: CGRect, stroke: CGColor? = Draw.rule, fill: CGColor? = nil, width: CGFloat = 0.8,
                 radius: CGFloat = 6, dash: [CGFloat] = []) {
            ctx.saveGState()
            let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if let fill {
                ctx.setFillColor(fill)
                ctx.addPath(path)
                ctx.fillPath()
            }
            if let stroke {
                ctx.setStrokeColor(stroke)
                ctx.setLineWidth(width)
                if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
                ctx.addPath(path)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }

        func circle(_ c: CGPoint, _ r: CGFloat, stroke: CGColor? = Draw.rule, fill: CGColor? = nil,
                    width: CGFloat = 0.8, dash: [CGFloat] = []) {
            ctx.saveGState()
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if let fill {
                ctx.setFillColor(fill)
                ctx.fillEllipse(in: rect)
            }
            if let stroke {
                ctx.setStrokeColor(stroke)
                ctx.setLineWidth(width)
                if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
                ctx.strokeEllipse(in: rect)
            }
            ctx.restoreGState()
        }

        /// Text with its top-left at (x, y). `width` > 0 enables alignment inside that width.
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: UIFont.Weight = .regular,
                  color: UIColor = Draw.label, align: NSTextAlignment = .left, width: CGFloat = 0, kern: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: style,
                .kern: kern,
            ]
            let str = NSAttributedString(string: s, attributes: attrs)
            if width > 0 {
                str.draw(in: CGRect(x: x, y: y, width: width, height: size * 1.6))
            } else {
                str.draw(at: CGPoint(x: x, y: y))
            }
        }

        /// Section heading in the accent color with a hairline under it.
        func heading(_ s: String, _ x: CGFloat, _ y: CGFloat, to x1: CGFloat) {
            text(s.uppercased(with: Loc.locale), x, y, size: 10.5, weight: .bold, color: Draw.accent, kern: 1.2)
            line(x, y + 18, x1, y + 18, Draw.accent.withAlphaComponent(0.35).cgColor, 0.8)
        }

        /// Writing lines from y0 (inclusive) while y <= y1.
        func rules(_ x0: CGFloat, _ x1: CGFloat, from y0: CGFloat, to y1: CGFloat, step: CGFloat,
                   color: CGColor = Draw.rule, width: CGFloat = 0.6) {
            var y = y0
            while y <= y1 {
                line(x0, y, x1, y, color, width)
                y += step
            }
        }

        func field(_ label: String, _ x: CGFloat, _ y: CGFloat, to x1: CGFloat) {
            text(label, x, y, size: 9, weight: .medium)
            line(x, y + 26, x1, y + 26)
        }

        func checkbox(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat = 13) {
            box(CGRect(x: x, y: y, width: s, height: s), stroke: CGColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1),
                width: 1, radius: 3)
        }
    }

    // MARK: Basic

    private static func lined(_ d: Draw, spacing: CGFloat, top: CGFloat, margin: CGFloat) {
        d.rules(0, d.w, from: top, to: d.h - 8, step: spacing, color: Draw.lineBlue, width: 0.9)
        d.line(margin, 0, margin, d.h, Draw.margin, 0.9)
    }

    private static func grid(_ d: Draw, step: CGFloat, color: CGColor, width: CGFloat) {
        var x: CGFloat = 0
        while x <= d.w {
            d.line(x, 0, x, d.h, color, width)
            x += step
        }
        var y: CGFloat = 0
        while y <= d.h {
            d.line(0, y, d.w, y, color, width)
            y += step
        }
    }

    private static func dotted(_ d: Draw) {
        d.ctx.setFillColor(CGColor(red: 0.60, green: 0.64, blue: 0.70, alpha: 1))
        var y: CGFloat = 0
        while y <= d.h {
            var x: CGFloat = 0
            while x <= d.w {
                d.ctx.fillEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                x += 20
            }
            y += 20
        }
    }

    // MARK: Technical

    private static func engineering(_ d: Draw) {
        d.ctx.setFillColor(CGColor(red: 0.95, green: 0.985, blue: 0.95, alpha: 1))
        d.ctx.fill(CGRect(origin: .zero, size: d.size))
        let step: CGFloat = 14.17
        let minor = CGColor(red: 0.72, green: 0.87, blue: 0.74, alpha: 1)
        let major = CGColor(red: 0.42, green: 0.70, blue: 0.48, alpha: 1)
        var i = 0
        var x: CGFloat = 0
        while x <= d.w {
            d.line(x, 0, x, d.h, i % 5 == 0 ? major : minor, i % 5 == 0 ? 0.9 : 0.4)
            x += step
            i += 1
        }
        i = 0
        var y: CGFloat = 0
        while y <= d.h {
            d.line(0, y, d.w, y, i % 5 == 0 ? major : minor, i % 5 == 0 ? 0.9 : 0.4)
            y += step
            i += 1
        }
    }

    private static func isometric(_ d: Draw) {
        let dx: CGFloat = 20
        let dy: CGFloat = 20 * 0.8660254
        d.ctx.setFillColor(CGColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1))
        var row = 0
        var y: CGFloat = 0
        while y <= d.h {
            var x: CGFloat = row % 2 == 0 ? 0 : dx / 2
            while x <= d.w {
                d.ctx.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                x += dx
            }
            y += dy
            row += 1
        }
    }

    private static func hexagon(_ d: Draw) {
        let r: CGFloat = 12
        let hw = 1.7320508 * r
        let color = CGColor(red: 0.74, green: 0.81, blue: 0.90, alpha: 1)
        d.ctx.saveGState()
        d.ctx.setStrokeColor(color)
        d.ctx.setLineWidth(0.55)
        var row = 0
        var cy: CGFloat = 0
        while cy <= d.h + r {
            var cx: CGFloat = row % 2 == 0 ? 0 : hw / 2
            while cx <= d.w + hw {
                for k in 0..<6 {
                    let a = CGFloat(k) * .pi / 3 + .pi / 6
                    let p = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                    if k == 0 { d.ctx.move(to: p) } else { d.ctx.addLine(to: p) }
                }
                d.ctx.closePath()
                cx += hw
            }
            cy += 1.5 * r
            row += 1
        }
        d.ctx.strokePath()
        d.ctx.restoreGState()
    }

    private static func music(_ d: Draw) {
        d.text(Loc.t("Başlık"), 40, 30, size: 9, weight: .medium)
        d.line(40, 56, d.w * 0.6, 56)
        d.text(Loc.t("Besteci"), d.w * 0.66, 30, size: 9, weight: .medium)
        d.line(d.w * 0.66, 56, d.w - 40, 56)
        let ink = CGColor(red: 0.45, green: 0.48, blue: 0.55, alpha: 1)
        var top: CGFloat = 92
        while top + 28 <= d.h - 36 {
            for k in 0..<5 {
                let y = top + CGFloat(k) * 7
                d.line(40, y, d.w - 40, y, ink, 0.7)
            }
            d.line(40, top, 40, top + 28, ink, 0.9)
            d.line(d.w - 40, top, d.w - 40, top + 28, ink, 0.9)
            top += 80
        }
    }

    private static func handwriting(_ d: Draw) {
        d.text(Loc.t("Güzel yazı defteri"), 40, 26, size: 9, weight: .medium)
        let blue = CGColor(red: 0.40, green: 0.58, blue: 0.86, alpha: 1)
        var y: CGFloat = 70
        while y + 42 <= d.h - 24 {
            d.line(40, y, d.w - 40, y, Draw.faint, 0.6)
            d.line(40, y + 15, d.w - 40, y + 15, blue, 0.6, dash: [4, 3])
            d.line(40, y + 30, d.w - 40, y + 30, Draw.margin, 0.9)
            d.line(40, y + 42, d.w - 40, y + 42, Draw.faint, 0.5, dash: [1.5, 2.5])
            y += 56
        }
    }

    // MARK: Planning

    private static func title(_ d: Draw, _ s: String, right: String) {
        d.text(s, 40, 30, size: 22, weight: .bold, color: UIColor(white: 0.22, alpha: 1))
        d.text(right, d.w - 220, 40, size: 9, weight: .medium)
        d.line(d.w - 220 + 34, 54, d.w - 40, 54)
    }

    private static func todo(_ d: Draw) {
        title(d, Loc.t("Yapılacaklar"), right: Loc.t("Tarih"))
        var y: CGFloat = 96
        while y + 34 <= d.h - 30 {
            d.checkbox(42, y + 12)
            d.line(66, y + 30, d.w - 40, y + 30)
            y += 34
        }
    }

    private static func daily(_ d: Draw) {
        title(d, Loc.t("Günlük Plan"), right: Loc.t("Tarih"))
        let left: CGFloat = 40
        let split: CGFloat = 340
        let top: CGFloat = 92
        let rowH = (d.h - top - 40) / 16
        for i in 0..<16 {
            let y = top + CGFloat(i) * rowH
            d.text(String(format: "%02d:00", 7 + i), left, y + 4, size: 9, weight: .medium)
            d.line(left + 40, y + rowH - 4, split - 16, y + rowH - 4)
        }
        let rx = split + 8
        d.heading(Loc.t("Öncelikler"), rx, top, to: d.w - 40)
        for k in 0..<3 {
            let y = top + 32 + CGFloat(k) * 30
            d.checkbox(rx, y)
            d.line(rx + 22, y + 13, d.w - 40, y + 13)
        }
        d.heading(Loc.t("Notlar"), rx, top + 140, to: d.w - 40)
        d.rules(rx, d.w - 40, from: top + 190, to: d.h - 140, step: 26)
        d.heading("Su", rx, d.h - 118, to: d.w - 40)
        for k in 0..<8 {
            d.circle(CGPoint(x: rx + 10 + CGFloat(k) * 26, y: d.h - 78), 9,
                     stroke: CGColor(red: 0.45, green: 0.68, blue: 0.92, alpha: 1))
        }
    }

    private static func weekly(_ d: Draw) {
        title(d, Loc.t("Haftalık Plan"), right: Loc.t("Hafta"))
        let days = [Loc.t("Pazartesi"), Loc.t("Salı"), Loc.t("Çarşamba"), Loc.t("Perşembe"), Loc.t("Cuma"), Loc.t("Cumartesi"), Loc.t("Pazar"), Loc.t("Notlar")]
        let top: CGFloat = 86
        let gap: CGFloat = 12
        let colW = (d.w - 80 - gap) / 2
        let rowH = (d.h - top - 36 - gap * 3) / 4
        for (i, day) in days.enumerated() {
            let col = CGFloat(i % 2)
            let row = CGFloat(i / 2)
            let r = CGRect(x: 40 + col * (colW + gap), y: top + row * (rowH + gap), width: colW, height: rowH)
            let weekend = i == 5 || i == 6
            d.box(r, stroke: Draw.rule, fill: weekend ? CGColor(red: 0.97, green: 0.97, blue: 1, alpha: 1) : nil, radius: 10)
            d.text(day, r.minX + 12, r.minY + 9, size: 11, weight: .bold, color: i == 7 ? Draw.label : Draw.accent)
            d.rules(r.minX + 12, r.maxX - 12, from: r.minY + 44, to: r.maxY - 10, step: 22, color: Draw.faint)
        }
    }

    private static func monthly(_ d: Draw) {
        d.text("Ay", 40, 40, size: 9, weight: .medium)
        d.line(62, 54, 300, 54)
        d.text(Loc.t("Yıl"), d.w - 200, 40, size: 9, weight: .medium)
        d.line(d.w - 180, 54, d.w - 40, 54)
        let names = [Loc.t("Pzt"), Loc.t("Sal"), Loc.t("Çar"), Loc.t("Per"), Loc.t("Cum"), Loc.t("Cmt"), Loc.t("Paz")]
        let top: CGFloat = 96
        let colW = (d.w - 80) / 7
        let bottom = d.h - 110
        let rowH = (bottom - (top + 22)) / 6
        for (i, n) in names.enumerated() {
            d.text(n, 40 + CGFloat(i) * colW, top, size: 10, weight: .bold,
                   color: i >= 5 ? Draw.accent : Draw.label, align: .center, width: colW)
        }
        for c in 5...6 {
            d.ctx.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 1, alpha: 1))
            d.ctx.fill(CGRect(x: 40 + CGFloat(c) * colW, y: top + 22, width: colW, height: rowH * 6))
        }
        for r in 0...6 {
            let y = top + 22 + CGFloat(r) * rowH
            d.line(40, y, d.w - 40, y, Draw.rule, 0.8)
        }
        for c in 0...7 {
            let x = 40 + CGFloat(c) * colW
            d.line(x, top + 22, x, top + 22 + rowH * 6, Draw.rule, 0.8)
        }
        d.heading(Loc.t("Notlar"), 40, bottom + 14, to: d.w - 40)
        d.rules(40, d.w - 40, from: bottom + 58, to: d.h - 24, step: 24)
    }

    private static func meeting(_ d: Draw) {
        d.text(Loc.t("Toplantı Notları"), 40, 30, size: 22, weight: .bold, color: UIColor(white: 0.22, alpha: 1))
        let third = (d.w - 80 - 24) / 3
        d.field(Loc.t("Tarih"), 40, 74, to: 40 + third)
        d.field(Loc.t("Saat"), 52 + third, 74, to: 52 + third * 2)
        d.field(Loc.t("Yer"), 64 + third * 2, 74, to: d.w - 40)
        d.field(Loc.t("Katılımcılar"), 40, 116, to: d.w - 40)
        d.line(40, 168, d.w - 40, 168)
        d.heading(Loc.t("Gündem"), 40, 190, to: d.w - 40)
        d.rules(40, d.w - 40, from: 236, to: 312, step: 25)
        d.heading(Loc.t("Notlar"), 40, 330, to: d.w - 40)
        d.rules(40, d.w - 40, from: 376, to: 552, step: 25)
        d.heading(Loc.t("Kararlar"), 40, 570, to: d.w - 40)
        d.rules(40, d.w - 40, from: 616, to: 666, step: 25)
        d.heading(Loc.t("Aksiyonlar"), 40, 684, to: d.w - 40)
        let c1 = 40 + (d.w - 80) * 0.55
        let c2 = 40 + (d.w - 80) * 0.80
        d.text(Loc.t("Görev"), 40, 708, size: 9, weight: .semibold)
        d.text(Loc.t("Sorumlu"), c1 + 6, 708, size: 9, weight: .semibold)
        d.text(Loc.t("Termin"), c2 + 6, 708, size: 9, weight: .semibold)
        d.rules(40, d.w - 40, from: 748, to: d.h - 24, step: 25)
        d.line(c1, 704, c1, d.h - 24, Draw.faint, 0.8)
        d.line(c2, 704, c2, d.h - 24, Draw.faint, 0.8)
    }

    // MARK: Professional

    private static func resume(_ d: Draw) {
        let side: CGFloat = 190
        d.ctx.setFillColor(CGColor(red: 0.93, green: 0.95, blue: 0.985, alpha: 1))
        d.ctx.fill(CGRect(x: 0, y: 0, width: side, height: d.h))
        d.circle(CGPoint(x: side / 2, y: 96), 54, stroke: CGColor(red: 0.62, green: 0.70, blue: 0.84, alpha: 1),
                 fill: CGColor(red: 1, green: 1, blue: 1, alpha: 1), width: 1, dash: [4, 3])
        d.text(Loc.t("Fotoğraf"), 0, 90, size: 9, weight: .medium, color: Draw.placeholder.withAlphaComponent(1),
               align: .center, width: side)
        let sx: CGFloat = 22
        let sx1 = side - 22
        d.heading(Loc.t("İletişim"), sx, 172, to: sx1)
        var y: CGFloat = 202
        for label in [Loc.t("Telefon"), Loc.t("E-posta"), Loc.t("Adres"), "Web / LinkedIn"] {
            d.text(label, sx, y, size: 8.5, weight: .medium)
            d.line(sx, y + 26, sx1, y + 26)
            y += 38
        }
        d.heading(Loc.t("Yetenekler"), sx, y + 8, to: sx1)
        y += 40
        for _ in 0..<5 {
            d.line(sx, y + 12, sx1 - 62, y + 12)
            for k in 0..<5 {
                d.circle(CGPoint(x: sx1 - 52 + CGFloat(k) * 12, y: y + 8), 3.5)
            }
            y += 28
        }
        d.heading(Loc.t("Diller"), sx, y + 8, to: sx1)
        y += 40
        for _ in 0..<3 {
            d.line(sx, y + 12, sx1 - 62, y + 12)
            for k in 0..<5 {
                d.circle(CGPoint(x: sx1 - 52 + CGFloat(k) * 12, y: y + 8), 3.5)
            }
            y += 28
        }
        d.heading(Loc.t("Hobiler"), sx, y + 8, to: sx1)
        d.rules(sx, sx1, from: y + 52, to: d.h - 30, step: 26)

        let mx: CGFloat = side + 26
        let mx1 = d.w - 36
        d.text(Loc.t("AD SOYAD"), mx, 46, size: 30, weight: .heavy, color: Draw.placeholder, kern: 2)
        d.text(Loc.t("Unvan / Pozisyon"), mx, 90, size: 13, weight: .medium, color: Draw.placeholder)
        d.line(mx, 122, mx1, 122, Draw.accent.cgColor, 2)
        d.heading(Loc.t("Profil"), mx, 146, to: mx1)
        d.rules(mx, mx1, from: 190, to: 236, step: 23)
        d.heading(Loc.t("Deneyim"), mx, 256, to: mx1)
        var ey: CGFloat = 286
        for _ in 0..<3 {
            d.text(Loc.t("Pozisyon · Şirket"), mx, ey, size: 9, weight: .semibold, color: Draw.placeholder)
            d.text("20__ – 20__", mx1 - 90, ey, size: 9, weight: .medium, color: Draw.placeholder, align: .right, width: 90)
            d.rules(mx, mx1, from: ey + 34, to: ey + 57, step: 23)
            ey += 74
        }
        d.heading(Loc.t("Eğitim"), mx, ey + 4, to: mx1)
        ey += 34
        for _ in 0..<2 {
            d.text(Loc.t("Okul · Bölüm"), mx, ey, size: 9, weight: .semibold, color: Draw.placeholder)
            d.text("20__ – 20__", mx1 - 90, ey, size: 9, weight: .medium, color: Draw.placeholder, align: .right, width: 90)
            d.line(mx, ey + 34, mx1, ey + 34)
            ey += 52
        }
        d.heading(Loc.t("Projeler ve sertifikalar"), mx, ey + 4, to: mx1)
        d.rules(mx, mx1, from: ey + 48, to: ey + 94, step: 23)
        d.heading(Loc.t("Referanslar"), mx, ey + 112, to: mx1)
        d.rules(mx, mx1, from: ey + 156, to: d.h - 30, step: 23)
    }

    private static func letter(_ d: Draw) {
        let rx: CGFloat = d.w - 250
        for (i, label) in [Loc.t("Ad Soyad"), Loc.t("Adres"), Loc.t("Telefon / E-posta")].enumerated() {
            d.field(label, rx, 40 + CGFloat(i) * 40, to: d.w - 40)
        }
        d.field(Loc.t("Tarih"), rx, 172, to: d.w - 40)
        for (i, label) in [Loc.t("Alıcı"), Loc.t("Kurum"), Loc.t("Adres")].enumerated() {
            d.field(label, 40, 220 + CGFloat(i) * 40, to: 300)
        }
        d.text(Loc.t("Konu:"), 40, 352, size: 10, weight: .bold, color: UIColor(white: 0.3, alpha: 1))
        d.line(76, 364, d.w - 40, 364)
        d.rules(40, d.w - 40, from: 410, to: d.h - 150, step: 26)
        d.text(Loc.t("Saygılarımla,"), 40, d.h - 128, size: 10, weight: .medium)
        d.line(40, d.h - 64, 240, d.h - 64)
        d.text(Loc.t("İmza"), 40, d.h - 58, size: 8.5, weight: .medium)
    }

    private static func cornell(_ d: Draw) {
        d.field(Loc.t("Konu"), 40, 30, to: 360)
        d.field(Loc.t("Tarih"), 380, 30, to: d.w - 40)
        let split: CGFloat = 170
        let summaryTop = d.h - 170
        d.line(split, 74, split, summaryTop, Draw.accent.withAlphaComponent(0.45).cgColor, 1.2)
        d.line(30, summaryTop, d.w - 30, summaryTop, Draw.accent.withAlphaComponent(0.45).cgColor, 1.2)
        d.text(Loc.t("Anahtar kelimeler · Sorular"), 34, 80, size: 8.5, weight: .semibold, color: Draw.accent)
        d.text(Loc.t("Notlar"), split + 10, 80, size: 8.5, weight: .semibold, color: Draw.accent)
        d.rules(split + 10, d.w - 36, from: 122, to: summaryTop - 10, step: 26, color: Draw.lineBlue, width: 0.7)
        d.text(Loc.t("Özet"), 34, summaryTop + 10, size: 8.5, weight: .semibold, color: Draw.accent)
        d.rules(34, d.w - 36, from: summaryTop + 50, to: d.h - 24, step: 26, color: Draw.lineBlue, width: 0.7)
    }

    private static func storyboard(_ d: Draw) {
        d.text("Storyboard", 40, 30, size: 22, weight: .bold, color: UIColor(white: 0.22, alpha: 1))
        d.text(Loc.t("Proje"), d.w - 250, 40, size: 9, weight: .medium)
        d.line(d.w - 220, 54, d.w - 130, 54)
        d.text(Loc.t("Sahne"), d.w - 120, 40, size: 9, weight: .medium)
        d.line(d.w - 88, 54, d.w - 40, 54)
        let gap: CGFloat = 20
        let fw = (d.w - 80 - gap) / 2
        let fh = fw * 9 / 16
        let block = fh + 64
        for i in 0..<6 {
            let col = CGFloat(i % 2)
            let row = CGFloat(i / 2)
            let x = 40 + col * (fw + gap)
            let y = 86 + row * (block + 12)
            d.box(CGRect(x: x, y: y, width: fw, height: fh), stroke: CGColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1),
                  width: 1, radius: 4)
            d.text("\(i + 1)", x + 6, y + 4, size: 9, weight: .bold, color: Draw.accent)
            d.line(x, y + fh + 26, x + fw, y + fh + 26)
            d.line(x, y + fh + 50, x + fw, y + fh + 50)
        }
    }
}

// MARK: - GPU textures for templates

/// Renders the current template into a Metal texture on a background queue. All notebook pages
/// share one template, so a single texture (re-rendered sharper when zooming in) serves them all.
final class TemplateTextureCache {
    var onUpdate: (() -> Void)?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let queue = DispatchQueue(label: "murekkep.template", qos: .userInitiated)
    private var current: (style: PaperStyle, size: CGSize, scale: CGFloat, texture: MTLTexture)?
    private var pending: (style: PaperStyle, scale: CGFloat)?

    static let maxDimension: CGFloat = 4096

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }

    /// Main thread. Returns the best texture available now and requests a sharper one if needed.
    func texture(style: PaperStyle, size: CGSize, desiredScale: CGFloat) -> MTLTexture? {
        let cap = Self.maxDimension / max(size.width, size.height, 1)
        let wanted = min(max(desiredScale, 0.5), cap)
        let bucket = min((wanted * 2).rounded(.up) / 2, cap)
        if let c = current, c.style == style, c.size == size {
            if c.scale < bucket * 0.8 { request(style, size, bucket) }
            return c.texture
        }
        request(style, size, bucket)
        return nil
    }

    private func request(_ style: PaperStyle, _ size: CGSize, _ scale: CGFloat) {
        if let p = pending, p.style == style, p.scale >= scale { return }
        pending = (style: style, scale: scale)
        queue.async { [weak self] in
            guard let self else { return }
            let made = autoreleasepool { self.render(style, size, scale) }
            DispatchQueue.main.async {
                if let p = self.pending, p.style == style, p.scale == scale {
                    self.pending = nil
                }
                guard let made else { return }
                self.current = (style: style, size: size, scale: scale, texture: made)
                self.onUpdate?()
            }
        }
    }

    /// Background queue.
    private func render(_ style: PaperStyle, _ size: CGSize, _ scale: CGFloat) -> MTLTexture? {
        let w = max(1, Int((size.width * scale).rounded(.up)))
        let h = max(1, Int((size.height * scale).rounded(.up)))
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info),
              let _ = ctx.data else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: CGFloat(w) / size.width, y: CGFloat(h) / size.height)
        ctx.interpolationQuality = .high
        PaperDrawer.draw(style, size: size, in: ctx)
        guard let bytes = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: true)
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: ctx.bytesPerRow)
        if texture.mipmapLevelCount > 1, let cb = commandQueue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        return texture
    }
}

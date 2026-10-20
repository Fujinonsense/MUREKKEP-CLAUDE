import CoreGraphics
import UIKit

// MARK: - Assets

/// Pictures prepared for the slides: the figures cropped from the source PDFs, and the illustrations
/// drawn for the overview ("file:" art in its folder).
final class SlideAssets: @unchecked Sendable {
    private var figures: [UUID: UIImage] = [:]
    private var illustrations: [UUID: UIImage] = [:]
    private let lock = NSLock()

    func figure(_ sceneID: UUID) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return figures[sceneID]
    }

    func set(_ image: UIImage, for sceneID: UUID) {
        lock.lock()
        figures[sceneID] = image
        lock.unlock()
    }

    func illustration(_ sceneID: UUID) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return illustrations[sceneID]
    }

    func set(illustration image: UIImage, for sceneID: UUID) {
        lock.lock()
        illustrations[sceneID] = image
        lock.unlock()
    }

    static func load(for overview: Overview, library: LibraryStore, folder: URL? = nil) async -> SlideAssets {
        let assets = SlideAssets()
        var jobs: [(id: UUID, url: URL, figure: FigureRef)] = []
        for scene in overview.scenes {
            guard let f = scene.figure, overview.sourceIDs.indices.contains(f.source) else { continue }
            jobs.append((id: scene.id, url: library.pdfURL(for: overview.sourceIDs[f.source]), figure: f))
        }
        var drawings: [(id: UUID, url: URL)] = []
        if let folder {
            for scene in overview.scenes {
                guard let art = scene.art, art.hasPrefix("file:") else { continue }
                drawings.append((id: scene.id, url: folder.appendingPathComponent(String(art.dropFirst(5)))))
            }
        }
        guard !jobs.isEmpty || !drawings.isEmpty else { return assets }
        let list = jobs
        let pictures = drawings
        await Task.detached(priority: .userInitiated) {
            for job in list {
                if let image = SlideAssets.renderFigure(job.url, job.figure) {
                    assets.set(image, for: job.id)
                }
            }
            for d in pictures {
                if let image = UIImage(contentsOfFile: d.url.path) {
                    assets.set(illustration: image, for: d.id)
                }
            }
        }.value
        return assets
    }

    static func renderFigure(_ url: URL, _ f: FigureRef) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path), let doc = PDFGeometry.openDocument(at: url),
              let page = doc.page(at: f.page + 1) else { return nil }
        let size = PDFGeometry.displaySize(of: page)
        var region = CGRect(origin: .zero, size: size)
        if let b = f.box, b.count == 4 {
            let pad = 0.035
            let x = max(0, b[0] - pad)
            let y = max(0, b[1] - pad)
            let w = min(1 - x, b[2] + pad * 2)
            let h = min(1 - y, b[3] + pad * 2)
            region = CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
        }
        guard region.width > 4, region.height > 4 else { return nil }
        let scale = min(5, 1600 / max(region.width, region.height))
        guard let image = PDFGeometry.renderBitmap(page: page, region: region, scale: scale)?.makeImage() else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: - Renderer

/// Draws the slides of a video overview with Core Graphics in a 1920 × 1080 space (y down).
/// The player and the MP4 export use the same frames.
enum SlideRenderer {
    static let canvas = CGSize(width: 1920, height: 1080)

    struct Palette {
        var top: UIColor
        var bottom: UIColor
        var text: UIColor
        var muted: UIColor
        var accent: UIColor
        var accent2: UIColor
        var good: UIColor
        var card: UIColor
        var cardText: UIColor
        var usesInk: Bool
        var chalk: Bool
    }

    /// The explainer look's accent colours: one per overview, picked by its title.
    static let explainerAccents: [UIColor] = [
        UIColor(red: 0xF2 / 255, green: 0x8C / 255, blue: 0x28 / 255, alpha: 1),
        UIColor(red: 0x1A / 255, green: 0x73 / 255, blue: 0xE8 / 255, alpha: 1),
        UIColor(red: 0x0F / 255, green: 0x9D / 255, blue: 0x58 / 255, alpha: 1),
        UIColor(red: 0x8E / 255, green: 0x44 / 255, blue: 0xAD / 255, alpha: 1),
    ]

    /// 32-bit FNV-1a of the title's UTF-8 bytes (twin of tests/ports/highlight.py), so an overview
    /// keeps its colour.
    static func accentIndex(_ title: String) -> Int {
        var h: UInt32 = 0x811C_9DC5
        for b in title.utf8 {
            h ^= UInt32(b)
            h = h &* 0x0100_0193
        }
        return Int(h % UInt32(explainerAccents.count))
    }

    static let marker = UIColor(red: 1.0, green: 0.898, blue: 0.541, alpha: 1)
    static let ink = UIColor(red: 0.09, green: 0.106, blue: 0.141, alpha: 1)

    static func palette(_ theme: SlideTheme) -> Palette {
        switch theme {
        case .explainer:
            return Palette(top: UIColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1), bottom: UIColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1),
                           text: ink, muted: UIColor(red: 0.357, green: 0.384, blue: 0.443, alpha: 1),
                           accent: explainerAccents[1], accent2: explainerAccents[1],
                           good: UIColor(red: 0.06, green: 0.62, blue: 0.35, alpha: 1), card: .white,
                           cardText: ink, usesInk: false, chalk: false)
        case .modern:
            return Palette(top: UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1), bottom: UIColor(red: 0.91, green: 0.94, blue: 0.99, alpha: 1),
                           text: UIColor(red: 0.08, green: 0.10, blue: 0.17, alpha: 1), muted: UIColor(red: 0.36, green: 0.40, blue: 0.48, alpha: 1),
                           accent: UIColor(red: 0.10, green: 0.33, blue: 0.80, alpha: 1), accent2: UIColor(red: 0.45, green: 0.30, blue: 0.96, alpha: 1),
                           good: UIColor(red: 0.13, green: 0.62, blue: 0.36, alpha: 1), card: .white,
                           cardText: UIColor(red: 0.08, green: 0.10, blue: 0.17, alpha: 1), usesInk: false, chalk: false)
        case .night:
            return Palette(top: UIColor(red: 0.05, green: 0.07, blue: 0.17, alpha: 1), bottom: UIColor(red: 0.10, green: 0.10, blue: 0.27, alpha: 1),
                           text: .white, muted: UIColor(red: 0.68, green: 0.72, blue: 0.86, alpha: 1),
                           accent: UIColor(red: 0.20, green: 0.78, blue: 0.95, alpha: 1), accent2: UIColor(red: 0.66, green: 0.50, blue: 1.0, alpha: 1),
                           good: UIColor(red: 0.30, green: 0.88, blue: 0.55, alpha: 1), card: UIColor(white: 1, alpha: 0.08),
                           cardText: .white, usesInk: false, chalk: false)
        case .notebook:
            return Palette(top: UIColor(red: 0.995, green: 0.985, blue: 0.955, alpha: 1), bottom: UIColor(red: 0.98, green: 0.965, blue: 0.93, alpha: 1),
                           text: UIColor(red: 0.07, green: 0.18, blue: 0.52, alpha: 1), muted: UIColor(red: 0.35, green: 0.40, blue: 0.52, alpha: 1),
                           accent: UIColor(red: 0.82, green: 0.20, blue: 0.22, alpha: 1), accent2: UIColor(red: 0.07, green: 0.18, blue: 0.52, alpha: 1),
                           good: UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1), card: UIColor(red: 1, green: 0.99, blue: 0.86, alpha: 1),
                           cardText: UIColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1), usesInk: true, chalk: false)
        case .chalkboard:
            return Palette(top: UIColor(red: 0.16, green: 0.25, blue: 0.21, alpha: 1), bottom: UIColor(red: 0.10, green: 0.17, blue: 0.14, alpha: 1),
                           text: UIColor(red: 0.96, green: 0.96, blue: 0.92, alpha: 1), muted: UIColor(red: 0.76, green: 0.82, blue: 0.77, alpha: 1),
                           accent: UIColor(red: 0.99, green: 0.88, blue: 0.45, alpha: 1), accent2: UIColor(red: 0.99, green: 0.64, blue: 0.72, alpha: 1),
                           good: UIColor(red: 0.55, green: 0.95, blue: 0.62, alpha: 1), card: UIColor(white: 1, alpha: 0.07),
                           cardText: UIColor(red: 0.96, green: 0.96, blue: 0.92, alpha: 1), usesInk: true, chalk: true)
        }
    }

    // MARK: Frame

    /// One frame of `overview` at `time` seconds, drawn into `size` (the context's user space, y down).
    static func drawFrame(_ overview: Overview, timeline: OverviewTimeline, time: Double, assets: SlideAssets?,
                          captions: Bool, size: CGSize, staticBackground: Bool = false, in ctx: CGContext) {
        ctx.saveGState()
        ctx.scaleBy(x: size.width / canvas.width, y: size.height / canvas.height)
        let theme = overview.options.theme
        var p = palette(theme)
        if theme == .explainer {
            let accent = explainerAccents[accentIndex(overview.title)]
            p.accent = accent
            p.accent2 = accent.withAlphaComponent(0.75)
        }
        if staticBackground {
            // The export draws thousands of frames: the background is drawn once.
            UIGraphicsPushContext(ctx)
            backgroundImage(theme).draw(in: CGRect(origin: .zero, size: canvas))
            UIGraphicsPopContext()
        } else {
            drawBackground(p, theme: theme, time: time, in: ctx)
        }
        let count = overview.scenes.count
        guard count > 0 else {
            ctx.restoreGState()
            return
        }
        let i = min(timeline.segment(at: time), count - 1)
        let local = time - timeline.sceneStart(i)
        let fade = 0.55
        if i > 0 && local < fade {
            let k = ease(local / fade)
            let prev = i - 1
            layer(alpha: 1 - k, ctx) {
                drawScene(overview.scenes[prev], index: prev, count: count, t: duration(timeline, prev) + 3,
                          duration: duration(timeline, prev), p: p, theme: theme, assets: assets, overview: overview, in: ctx)
            }
            layer(alpha: k, ctx) {
                drawScene(overview.scenes[i], index: i, count: count, t: narrationTime(timeline, i, time),
                          duration: duration(timeline, i), p: p, theme: theme, assets: assets, overview: overview, in: ctx)
            }
        } else {
            drawScene(overview.scenes[i], index: i, count: count, t: narrationTime(timeline, i, time),
                      duration: duration(timeline, i), p: p, theme: theme, assets: assets, overview: overview, in: ctx)
        }
        drawChrome(p, theme: theme, index: i, count: count, progress: timeline.total > 0 ? time / timeline.total : 0, in: ctx)
        if captions, overview.scenes.indices.contains(i) {
            let t = narrationTime(timeline, i, time)
            let d = duration(timeline, i)
            if t >= 0 && t <= d + 0.3 {
                drawCaption(caption(overview.scenes[i].narration, progress: t / max(d, 0.1)), p: p, theme: theme, in: ctx)
            }
        }
        ctx.restoreGState()
    }

    private static func duration(_ timeline: OverviewTimeline, _ i: Int) -> Double {
        timeline.durations.indices.contains(i) ? max(timeline.durations[i], 0.5) : 4
    }

    private static func narrationTime(_ timeline: OverviewTimeline, _ i: Int, _ time: Double) -> Double {
        timeline.starts.indices.contains(i) ? time - timeline.starts[i] : time
    }

    /// A still of the title slide (cards and thumbnails), without captions.
    static func poster(_ overview: Overview, size: CGSize, assets: SlideAssets? = nil, in ctx: CGContext) {
        var timeline = overview.timeline
        if timeline.starts.isEmpty {
            timeline = OverviewTimeline(durations: overview.scenes.map { _ in 6 }, kind: .video)
        }
        drawFrame(overview, timeline: timeline, time: timeline.sceneStart(0) + 4, assets: assets, captions: false, size: size, in: ctx)
    }

    // MARK: Animation helpers

    static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return 1 - pow(1 - c, 3)
    }

    /// 0 → 1 over `length` seconds from `start`.
    static func appear(_ t: Double, at start: Double, length: Double = 0.5) -> Double {
        ease((t - start) / length)
    }

    private static func layer(alpha: Double, _ ctx: CGContext, _ draw: () -> Void) {
        guard alpha > 0.002 else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // MARK: Background and chrome

    private static func drawBackground(_ p: Palette, theme: SlideTheme, time: Double, in ctx: CGContext) {
        let rect = CGRect(origin: .zero, size: canvas)
        let space = CGColorSpaceCreateDeviceRGB()
        if let g = CGGradient(colorsSpace: space, colors: [p.top.cgColor, p.bottom.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: canvas.height), options: [])
        } else {
            ctx.setFillColor(p.top.cgColor)
            ctx.fill(rect)
        }
        let drift = CGFloat(sin(time * 0.12)) * 60
        switch theme {
        case .explainer:
            // Grid paper.
            ctx.setStrokeColor(UIColor(red: 0.902, green: 0.914, blue: 0.937, alpha: 1).cgColor)
            ctx.setLineWidth(1.5)
            var x: CGFloat = 28
            while x < canvas.width {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: canvas.height))
                x += 28
            }
            var y: CGFloat = 28
            while y < canvas.height {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: canvas.width, y: y))
                y += 28
            }
            ctx.strokePath()
        case .modern, .night:
            let a: CGFloat = theme == .night ? 0.28 : 0.11
            blob(CGPoint(x: 1560 + drift, y: 180 - drift * 0.5), radius: 620, color: p.accent.withAlphaComponent(a), in: ctx)
            blob(CGPoint(x: 260 - drift, y: 960 + drift * 0.3), radius: 560, color: p.accent2.withAlphaComponent(a * 0.85), in: ctx)
            if theme == .night {
                ctx.setFillColor(UIColor(white: 1, alpha: 0.05).cgColor)
                var y: CGFloat = 60
                while y < canvas.height {
                    var x: CGFloat = 60
                    while x < canvas.width {
                        ctx.fillEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
                        x += 60
                    }
                    y += 60
                }
            }
        case .notebook:
            ctx.setStrokeColor(UIColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 0.17).cgColor)
            ctx.setLineWidth(2)
            var y: CGFloat = 150
            while y < canvas.height {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: canvas.width, y: y))
                y += 64
            }
            ctx.strokePath()
            ctx.setStrokeColor(UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 0.40).cgColor)
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: 92, y: 0))
            ctx.addLine(to: CGPoint(x: 92, y: canvas.height))
            ctx.strokePath()
        case .chalkboard:
            blob(CGPoint(x: 500 + drift, y: 380), radius: 520, color: UIColor(white: 1, alpha: 0.035), in: ctx)
            blob(CGPoint(x: 1420 - drift, y: 720), radius: 600, color: UIColor(white: 1, alpha: 0.03), in: ctx)
            // Chalk tray.
            ctx.setFillColor(UIColor(red: 0.36, green: 0.25, blue: 0.16, alpha: 0.85).cgColor)
            ctx.fill(CGRect(x: 0, y: canvas.height - 18, width: canvas.width, height: 18))
        }
    }

    private static let backgroundLock = NSLock()
    private static var backgrounds: [SlideTheme: UIImage] = [:]

    private static func backgroundImage(_ theme: SlideTheme) -> UIImage {
        backgroundLock.lock()
        defer { backgroundLock.unlock() }
        if let image = backgrounds[theme] { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            drawBackground(palette(theme), theme: theme, time: 0, in: ctx.cgContext)
        }
        backgrounds[theme] = image
        return image
    }

    private static func blob(_ center: CGPoint, radius: CGFloat, color: UIColor, in ctx: CGContext) {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func drawChrome(_ p: Palette, theme: SlideTheme, index: Int, count: Int, progress: Double, in ctx: CGContext) {
        // Progress along the top.
        ctx.setFillColor(p.text.withAlphaComponent(0.08).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvas.width, height: 8))
        let w = canvas.width * CGFloat(min(max(progress, 0), 1))
        let space = CGColorSpaceCreateDeviceRGB()
        if w > 1, let g = CGGradient(colorsSpace: space, colors: [p.accent.cgColor, p.accent2.cgColor] as CFArray, locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: 8))
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: canvas.width, y: 0), options: [])
            ctx.restoreGState()
        }
        text("\(index + 1) / \(count)", in: CGRect(x: 1600, y: 34, width: 260, height: 40),
             font: font(26, .semibold, theme), color: p.muted, align: .right, ctx: ctx)
        ctx.setFillColor(p.accent.cgColor)
        ctx.fillEllipse(in: CGRect(x: 64, y: 1022, width: 14, height: 14))
        text(Loc.t("Mürekkep"), in: CGRect(x: 88, y: 1010, width: 400, height: 40),
             font: font(24, .semibold, theme), color: p.muted.withAlphaComponent(0.8), ctx: ctx)
    }

    private static func drawCaption(_ s: String, p: Palette, theme: SlideTheme, in ctx: CGContext) {
        guard !s.isEmpty else { return }
        let f = font(36, .semibold, theme == .chalkboard ? .modern : theme == .notebook ? .modern : theme)
        let maxW: CGFloat = 1500
        let h = measure(s, width: maxW, font: f, lineSpacing: 4)
        let w = min(maxW, width(of: s, font: f)) + 64
        let rect = CGRect(x: (canvas.width - w) / 2, y: canvas.height - 70 - h - 28, width: w, height: h + 28)
        ctx.setFillColor(UIColor(white: 0, alpha: 0.62).cgColor)
        ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 22).cgPath)
        ctx.fillPath()
        text(s, in: rect.insetBy(dx: 32, dy: 14), font: f, color: .white, align: .center, lineSpacing: 4, ctx: ctx)
    }

    // MARK: Captions

    private static let captionLock = NSLock()
    private static var captionCache: [String: [(text: String, end: Double)]] = [:]

    /// The piece of narration being spoken at `progress` (0…1), short enough for two lines.
    static func caption(_ narration: String, progress: Double) -> String {
        captionLock.lock()
        var pieces = captionCache[narration]
        captionLock.unlock()
        if pieces == nil {
            var chunks: [String] = []
            var current = ""
            for word in narration.split(separator: " ") {
                current += (current.isEmpty ? "" : " ") + word
                let endsSentence = word.last.map { ".!?…".contains($0) } ?? false
                if current.count > 95 || (endsSentence && current.count > 30) {
                    chunks.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { chunks.append(current) }
            let total = Double(max(chunks.reduce(0) { $0 + $1.count }, 1))
            var acc = 0.0
            var built: [(text: String, end: Double)] = []
            for c in chunks {
                acc += Double(c.count)
                built.append((text: c, end: acc / total))
            }
            captionLock.lock()
            if captionCache.count > 300 { captionCache.removeAll() }
            captionCache[narration] = built
            captionLock.unlock()
            pieces = built
        }
        guard let list = pieces, !list.isEmpty else { return "" }
        for piece in list where progress <= piece.end {
            return piece.text
        }
        return list[list.count - 1].text
    }

    // MARK: Scenes

    private static func drawScene(_ scene: OverviewScene, index: Int, count: Int, t: Double, duration: Double,
                                   p: Palette, theme: SlideTheme, assets: SlideAssets?, overview: Overview, in ctx: CGContext) {
        let enter = t + 0.5
        let en = overview.language.isEnglish
        var layout = scene.layout
        let figure = assets?.figure(scene.id)
        if layout == .figure && figure == nil { layout = scene.bullets.isEmpty ? .title : .bullets }
        switch layout {
        case .title:
            drawTitleScene(scene, enter: enter, p: p, theme: theme, overview: overview, picture: assets?.illustration(scene.id), in: ctx)
        case .bullets, .steps, .summary:
            drawHeading(scene.title, enter: enter, p: p, theme: theme, in: ctx)
            if layout == .steps && scene.bullets.count >= 2 && scene.bullets.count <= 5 {
                drawSteps(scene.bullets, t: t, duration: duration, p: p, theme: theme, in: ctx)
            } else {
                let side = scene.art != nil
                let area = CGRect(x: 140, y: 290, width: side ? 1080 : 1640, height: 610)
                drawList(scene.bullets, style: layout == .summary ? .check : layout == .steps ? .number : .dot,
                         area: area, t: t, duration: duration, p: p, theme: theme, in: ctx)
                if let art = scene.art {
                    let a = appear(enter, at: 0.4, length: 0.7)
                    let bob = CGFloat(sin(enter * 1.3)) * 8
                    let s: CGFloat = 0.82 + 0.18 * CGFloat(a)
                    let side: CGFloat = 470 * s
                    drawArt(art, in: CGRect(x: 1500 - side / 2, y: 610 - side / 2 + bob, width: side, height: side),
                            color: p.accent, alpha: a, in: ctx)
                }
            }
        case .figure:
            drawHeading(scene.title, enter: enter, p: p, theme: theme, in: ctx)
            if let figure { drawFigureScene(scene, image: figure, t: t, duration: duration, p: p, theme: theme, in: ctx) }
        case .definition:
            drawDefinition(scene, enter: enter, p: p, theme: theme, en: en, in: ctx)
        case .compare:
            drawHeading(scene.title, enter: enter, p: p, theme: theme, in: ctx)
            drawCompare(scene, t: t, duration: duration, p: p, theme: theme, in: ctx)
        case .quote:
            drawQuote(scene, enter: enter, p: p, theme: theme, in: ctx)
        case .quiz:
            drawQuiz(scene, t: t, duration: duration, p: p, theme: theme, en: en, in: ctx)
        case .question:
            drawQuestion(scene, enter: enter, p: p, theme: theme, picture: assets?.illustration(scene.id), in: ctx)
        case .section:
            drawSectionCard(scene, enter: enter, p: p, theme: theme, picture: assets?.illustration(scene.id), in: ctx)
        case .agenda:
            drawAgenda(scene, t: t, duration: duration, p: p, theme: theme, in: ctx)
        }
    }

    // MARK: Explainer slides (NotebookLM-like)

    /// A drawn picture fitted into `rect` (aspect kept), faded in.
    private static func drawPicture(_ image: UIImage, in rect: CGRect, alpha: Double, in ctx: CGContext) {
        guard alpha > 0.01, image.size.width > 0, image.size.height > 0 else { return }
        let k = min(rect.width / image.size.width, rect.height / image.size.height)
        let w = image.size.width * k
        let h = image.size.height * k
        UIGraphicsPushContext(ctx)
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h), blendMode: .normal, alpha: CGFloat(alpha))
        UIGraphicsPopContext()
    }

    /// A big question; its highlighted words get a yellow marker that sweeps in.
    private static func drawQuestion(_ scene: OverviewScene, enter: Double, p: Palette, theme: SlideTheme, picture: UIImage?,
                                     in ctx: CGContext) {
        let parsed = Highlight.parse(scene.title)
        let a = appear(enter, at: 0.1, length: 0.7)
        text("?", in: CGRect(x: 560, y: 20, width: 800, height: 900), font: UIFont.systemFont(ofSize: 760, weight: .black),
             color: p.accent.withAlphaComponent(0.07), align: .center, alpha: a, ctx: ctx)
        var area = CGRect(x: 200, y: 250, width: 1520, height: 560)
        if let picture {
            drawPicture(picture, in: CGRect(x: 120, y: 250, width: 620, height: 560), alpha: appear(enter, at: 0.4, length: 0.8), in: ctx)
            area = CGRect(x: 800, y: 250, width: 980, height: 560)
        }
        let f = fitted(parsed.text, width: area.width, height: area.height, base: 92, minSize: 50, weight: .bold, theme: theme)
        let h = measure(parsed.text, width: area.width, font: f, lineSpacing: 14)
        let para = NSMutableParagraphStyle()
        para.alignment = picture == nil ? .center : .left
        para.lineSpacing = 14
        para.lineBreakMode = .byWordWrapping
        let body = NSMutableAttributedString(string: parsed.text, attributes: [
            .font: f, .foregroundColor: p.text.withAlphaComponent(CGFloat(a)), .paragraphStyle: para,
        ])
        let m = appear(enter, at: 0.9, length: 0.5)
        if m > 0 {
            for r in parsed.ranges where r.location + r.length <= body.length {
                body.addAttribute(.backgroundColor, value: marker.withAlphaComponent(CGFloat(m)), range: r)
            }
        }
        UIGraphicsPushContext(ctx)
        body.draw(with: CGRect(x: area.minX, y: area.midY - h / 2 + CGFloat(1 - a) * 24, width: area.width, height: h + 12),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        UIGraphicsPopContext()
    }

    /// A section card: the number big on an accent panel, the title on a white card beside it.
    private static func drawSectionCard(_ scene: OverviewScene, enter: Double, p: Palette, theme: SlideTheme, picture: UIImage?,
                                        in ctx: CGContext) {
        let a = appear(enter, at: 0, length: 0.6)
        let panel = CGRect(x: 0, y: 0, width: 760 * CGFloat(a), height: canvas.height)
        ctx.setFillColor(p.accent.cgColor)
        ctx.fill(panel)
        // Faint diagonal hatching on the panel.
        ctx.saveGState()
        ctx.clip(to: panel)
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.10).cgColor)
        ctx.setLineWidth(10)
        var x: CGFloat = -1080
        while x < 760 {
            ctx.move(to: CGPoint(x: x, y: canvas.height))
            ctx.addLine(to: CGPoint(x: x + 1080, y: 0))
            x += 64
        }
        ctx.strokePath()
        ctx.restoreGState()

        let n = appear(enter, at: 0.25, length: 0.6)
        if let number = scene.number, n > 0 {
            let numeral = NSAttributedString(string: "\(number)", attributes: [
                .font: UIFont.systemFont(ofSize: 560 * CGFloat(0.85 + 0.15 * n), weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(CGFloat(n)),
                .strokeColor: ink.withAlphaComponent(CGFloat(n)),
                .strokeWidth: -2.5,
            ])
            let size = numeral.size()
            UIGraphicsPushContext(ctx)
            numeral.draw(at: CGPoint(x: 380 - size.width / 2, y: 540 - size.height / 2))
            UIGraphicsPopContext()
        }

        let c = appear(enter, at: 0.35, length: 0.6)
        guard c > 0 else { return }
        let card = CGRect(x: 640 + CGFloat(1 - c) * 60, y: 300, width: 1180, height: 480)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(c))
        // A hard offset shadow, then the card with an ink outline.
        ctx.setFillColor(ink.withAlphaComponent(0.85).cgColor)
        ctx.addPath(UIBezierPath(roundedRect: card.offsetBy(dx: 14, dy: 14), cornerRadius: 44).cgPath)
        ctx.fillPath()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(UIBezierPath(roundedRect: card, cornerRadius: 44).cgPath)
        ctx.fillPath()
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(5)
        ctx.addPath(UIBezierPath(roundedRect: card, cornerRadius: 44).cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        var inner = card.insetBy(dx: 70, dy: 60)
        if let picture {
            drawPicture(picture, in: CGRect(x: card.maxX - 400, y: card.minY + 60, width: 340, height: card.height - 120),
                        alpha: appear(enter, at: 0.7, length: 0.6), in: ctx)
            inner.size.width -= 360
        }
        let titleFont = fitted(scene.title, width: inner.width, height: 240, base: 76, minSize: 44, weight: .bold, theme: theme)
        let th = measure(scene.title, width: inner.width, font: titleFont, lineSpacing: 8)
        let sub = scene.subtitle ?? ""
        let subFont = font(40, .medium, theme)
        let sh = sub.isEmpty ? 0 : measure(sub, width: inner.width, font: subFont) + 24
        let top = inner.midY - (th + sh) / 2
        text(scene.title, in: CGRect(x: inner.minX, y: top, width: inner.width, height: th + 8), font: titleFont, color: ink,
             alpha: c, lineSpacing: 8, ctx: ctx)
        if !sub.isEmpty {
            text(sub, in: CGRect(x: inner.minX, y: top + th + 24, width: inner.width, height: sh), font: subFont, color: p.muted,
                 alpha: appear(enter, at: 0.6), ctx: ctx)
        }
    }

    /// The roadmap: numbered tiles, three to a row, appearing one by one while they are read.
    private static func drawAgenda(_ scene: OverviewScene, t: Double, duration: Double, p: Palette, theme: SlideTheme, in ctx: CGContext) {
        let enter = t + 0.5
        drawHeading(scene.title, enter: enter, p: p, theme: theme, in: ctx)
        let items = Array(scene.bullets.prefix(VideoOutline.maxSections))
        guard !items.isEmpty else { return }
        let columns = min(3, items.count)
        let rows = (items.count + columns - 1) / columns
        let w: CGFloat = 500
        let h: CGFloat = rows > 1 ? 240 : 300
        let gap: CGFloat = 44
        let left = (canvas.width - CGFloat(columns) * w - CGFloat(columns - 1) * gap) / 2
        let top: CGFloat = rows > 1 ? 320 : 420
        let step = max(0.5, (duration - 1.5) / Double(items.count))
        for (i, item) in items.enumerated() {
            let a = appear(t, at: 0.8 + Double(i) * step, length: 0.45)
            guard a > 0 else { continue }
            let col = i % columns
            let row = i / columns
            let rect = CGRect(x: left + CGFloat(col) * (w + gap), y: top + CGFloat(row) * (h + gap) + CGFloat(1 - a) * 24, width: w, height: h)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(a))
            ctx.setFillColor(p.accent.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: rect.offsetBy(dx: 10, dy: 10), cornerRadius: 26).cgPath)
            ctx.fillPath()
            ctx.setFillColor(p.card.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 26).cgPath)
            ctx.fillPath()
            ctx.setStrokeColor(p.text.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(3)
            ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 26).cgPath)
            ctx.strokePath()
            ctx.setFillColor(p.accent.cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.maxX - 46, y: rect.maxY - 46, width: 20, height: 20))
            ctx.restoreGState()
            text("\(i + 1)", in: CGRect(x: rect.minX + 32, y: rect.minY + 22, width: 120, height: 70), font: font(54, .bold, theme),
                 color: p.accent, alpha: a, ctx: ctx)
            let body = CGRect(x: rect.minX + 32, y: rect.minY + 96, width: rect.width - 90, height: rect.height - 120)
            text(item, in: body, font: fitted(item, width: body.width, height: body.height, base: 40, minSize: 26, weight: .semibold,
                                              theme: theme),
                 color: p.cardText, alpha: a, lineSpacing: 6, ctx: ctx)
        }
    }

    private static func drawTitleScene(_ scene: OverviewScene, enter: Double, p: Palette, theme: SlideTheme,
                                       overview: Overview, picture: UIImage? = nil, in ctx: CGContext) {
        if let picture {
            // An illustrated title: the drawing above, the title under it.
            drawPicture(picture, in: CGRect(x: 610, y: 110, width: 700, height: 470), alpha: appear(enter, at: 0.1, length: 0.8), in: ctx)
            let titleRect = CGRect(x: 180, y: 620, width: 1560, height: 200)
            let h = headline(VideoOutline.plain(scene.title), in: titleRect, base: 92, minSize: 54, enter: enter, delay: 0.3,
                             centered: true, p: p, theme: theme, in: ctx)
            if let sub = scene.subtitle {
                let a = appear(enter, at: 1.1)
                text(sub, in: CGRect(x: 260, y: 640 + h, width: 1400, height: 80), font: font(40, .medium, theme), color: p.muted,
                     align: .center, alpha: a, ctx: ctx)
            }
            return
        }
        let hasArt = scene.art != nil && !(scene.art ?? "").hasPrefix("file:")
        if let art = scene.art, hasArt {
            let a = appear(enter, at: 0.1, length: 0.8)
            let bob = CGFloat(sin(enter * 1.2)) * 8
            let side: CGFloat = 250 * (0.8 + 0.2 * CGFloat(a))
            drawArt(art, in: CGRect(x: 960 - side / 2, y: 290 - side / 2 + bob, width: side, height: side), color: p.accent, alpha: a, in: ctx)
        }
        let top: CGFloat = hasArt ? 460 : 340
        let titleRect = CGRect(x: 180, y: top, width: 1560, height: 250)
        let h = headline(scene.title, in: titleRect, base: 104, minSize: 60, enter: enter, delay: 0.3, centered: true, p: p, theme: theme, in: ctx)
        // Accent underline that grows.
        let u = appear(enter, at: 0.9, length: 0.6)
        if u > 0 {
            let w: CGFloat = 220 * CGFloat(u)
            ctx.setFillColor(p.accent.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: 960 - w / 2, y: top + h + 26, width: w, height: 10), cornerRadius: 5).cgPath)
            ctx.fillPath()
        }
        if let sub = scene.subtitle {
            let a = appear(enter, at: 1.1)
            text(sub, in: CGRect(x: 260, y: top + h + 70 + CGFloat(1 - a) * 20, width: 1400, height: 160),
                 font: font(44, .medium, theme), color: p.muted, align: .center, alpha: a, ctx: ctx)
        }
        if !overview.sourceTitles.isEmpty {
            let a = appear(enter, at: 1.5)
            let s = overview.sourceTitles.prefix(3).joined(separator: "  ·  ")
            text(s, in: CGRect(x: 260, y: 900, width: 1400, height: 50), font: font(26, .semibold, theme),
                 color: p.muted.withAlphaComponent(0.8), align: .center, alpha: a, ctx: ctx)
        }
    }

    /// The title at the top of a content slide.
    private static func drawHeading(_ title: String, enter: Double, p: Palette, theme: SlideTheme, in ctx: CGContext) {
        let a = appear(enter, at: 0.05)
        ctx.setFillColor(p.accent.withAlphaComponent(CGFloat(a)).cgColor)
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: 140, y: 118, width: 12, height: 110 * CGFloat(a)), cornerRadius: 6).cgPath)
        ctx.fillPath()
        _ = headline(title, in: CGRect(x: 180, y: 108, width: 1600, height: 140), base: 72, minSize: 46,
                     enter: enter, delay: 0, centered: false, p: p, theme: theme, in: ctx)
    }

    /// Big text written in ink (notebook, chalkboard) or faded in. Returns the height used.
    @discardableResult
    private static func headline(_ s: String, in rect: CGRect, base: CGFloat, minSize: CGFloat, enter: Double, delay: Double,
                                 centered: Bool, p: Palette, theme: SlideTheme, in ctx: CGContext) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        if p.usesInk && s.count <= 80 && StrokeFont.canDraw(s) {
            let cap = inkCap(s, width: rect.width, height: rect.height, base: base * 0.72)
            let reveal = min(max((enter - delay) / max(0.6, Double(s.count) * 0.045), 0), 1)
            return drawInk(s, origin: rect.origin, cap: cap, maxWidth: rect.width, centered: centered, color: p.text,
                           reveal: reveal, chalk: p.chalk, in: ctx)
        }
        let f = fitted(s, width: rect.width, height: rect.height, base: base, minSize: minSize, weight: .bold, theme: theme)
        let a = appear(enter, at: delay)
        let h = measure(s, width: rect.width, font: f)
        text(s, in: CGRect(x: rect.minX, y: rect.minY + CGFloat(1 - a) * 26, width: rect.width, height: rect.height),
             font: f, color: p.text, align: centered ? .center : .left, alpha: a, ctx: ctx)
        return min(h, rect.height)
    }

    private enum Marker {
        case dot
        case number
        case check
    }

    private static func drawList(_ items: [String], style: Marker, area: CGRect, t: Double, duration: Double,
                                 p: Palette, theme: SlideTheme, in ctx: CGContext) {
        guard !items.isEmpty else { return }
        let n = items.count
        let textWidth = area.width - 90
        let gap: CGFloat = 34
        // One size for every item, as large as fits (worked out once per slide).
        let key = "list|\(items.joined(separator: "\u{1}"))|\(Int(textWidth))|\(Int(area.height))|\(theme.rawValue)"
        fitLock.lock()
        let cachedSize = fitCache[key]
        fitLock.unlock()
        var size: CGFloat = cachedSize ?? 50
        if cachedSize == nil {
            while size > 30 {
                let f = font(size, .medium, theme)
                let total = items.reduce(CGFloat(0)) { $0 + max(measure($1, width: textWidth, font: f), size * 1.2) }
                if total + gap * CGFloat(n - 1) <= area.height { break }
                size -= 3
            }
            fitLock.lock()
            fitCache[key] = size
            fitLock.unlock()
        }
        let f = font(size, .medium, theme)
        let heights = items.map { max(measure($0, width: textWidth, font: f), size * 1.2) }
        var y = area.minY
        for (k, item) in items.enumerated() {
            let reveal = 0.35 + Double(k) / Double(n) * max(0.5, duration * 0.72)
            let a = appear(t, at: reveal)
            guard a > 0 else {
                y += (heights.indices.contains(k) ? heights[k] : size) + gap
                continue
            }
            let h = heights.indices.contains(k) ? heights[k] : size * 1.2
            let dx = CGFloat(1 - a) * 30
            let markerCenter = CGPoint(x: area.minX + 26 - dx, y: y + size * 0.62)
            switch style {
            case .dot:
                ctx.setFillColor(p.accent.withAlphaComponent(CGFloat(a)).cgColor)
                ctx.fillEllipse(in: CGRect(x: markerCenter.x - 11, y: markerCenter.y - 11, width: 22, height: 22))
            case .number:
                ctx.setFillColor(p.accent.withAlphaComponent(CGFloat(a)).cgColor)
                ctx.fillEllipse(in: CGRect(x: markerCenter.x - 26, y: markerCenter.y - 26, width: 52, height: 52))
                text("\(k + 1)", in: CGRect(x: markerCenter.x - 26, y: markerCenter.y - 19, width: 52, height: 40),
                     font: font(30, .bold, .modern), color: p.chalk ? p.top : .white, align: .center, alpha: a, ctx: ctx)
            case .check:
                ctx.setStrokeColor(p.good.withAlphaComponent(CGFloat(a)).cgColor)
                ctx.setLineWidth(8)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.move(to: CGPoint(x: markerCenter.x - 18, y: markerCenter.y))
                ctx.addLine(to: CGPoint(x: markerCenter.x - 5, y: markerCenter.y + 14))
                ctx.addLine(to: CGPoint(x: markerCenter.x + 20, y: markerCenter.y - 16))
                ctx.strokePath()
            }
            let rect = CGRect(x: area.minX + 78 - dx, y: y, width: textWidth, height: h + 8)
            if p.usesInk && item.count <= 70 && StrokeFont.canDraw(item) {
                let cap = size * 0.62
                let reveal2 = min(max((t - reveal) / max(0.5, Double(item.count) * 0.035), 0), 1)
                _ = drawInk(item, origin: CGPoint(x: rect.minX, y: rect.minY + size * 0.08), cap: cap, maxWidth: rect.width,
                            centered: false, color: p.text, reveal: reveal2, chalk: p.chalk, in: ctx)
            } else {
                text(item, in: rect, font: f, color: p.text, alpha: a, ctx: ctx)
            }
            y += h + gap
        }
    }

    private static func drawSteps(_ items: [String], t: Double, duration: Double, p: Palette, theme: SlideTheme, in ctx: CGContext) {
        let n = items.count
        let left: CGFloat = 200
        let right: CGFloat = 1720
        let lineY: CGFloat = 470
        let step = (right - left) / CGFloat(max(n - 1, 1))
        let grow = appear(t, at: 0.2, length: max(0.8, duration * 0.7))
        ctx.setStrokeColor(p.muted.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(6)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: left, y: lineY))
        ctx.addLine(to: CGPoint(x: left + (right - left) * CGFloat(grow), y: lineY))
        ctx.strokePath()
        let f = fitted(items.max(by: { $0.count < $1.count }) ?? "", width: step * 0.92, height: 300, base: 40, minSize: 26,
                       weight: .medium, theme: theme)
        for (k, item) in items.enumerated() {
            let reveal = 0.3 + Double(k) / Double(n) * max(0.6, duration * 0.72)
            let a = appear(t, at: reveal)
            guard a > 0 else { continue }
            let x = left + step * CGFloat(k)
            let r: CGFloat = 40 * CGFloat(0.6 + 0.4 * a)
            ctx.setFillColor((k % 2 == 0 ? p.accent : p.accent2).withAlphaComponent(CGFloat(a)).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - r, y: lineY - r, width: r * 2, height: r * 2))
            text("\(k + 1)", in: CGRect(x: x - 40, y: lineY - 24, width: 80, height: 50), font: font(36, .bold, .modern),
                 color: p.chalk ? p.top : .white, align: .center, alpha: a, ctx: ctx)
            let w = step * 0.92
            text(item, in: CGRect(x: x - w / 2, y: lineY + 70 + CGFloat(1 - a) * 20, width: w, height: 320), font: f,
                 color: p.text, align: .center, alpha: a, ctx: ctx)
        }
    }

    private static func drawFigureScene(_ scene: OverviewScene, image: UIImage, t: Double, duration: Double,
                                        p: Palette, theme: SlideTheme, in ctx: CGContext) {
        let notes = scene.bullets.prefix(2)
        let box = notes.isEmpty ? CGRect(x: 160, y: 280, width: 1600, height: 680) : CGRect(x: 140, y: 280, width: 1100, height: 680)
        let size = image.size
        let k = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        let w = size.width * k
        let h = size.height * k
        let frame = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        let a = appear(t + 0.5, at: 0.2, length: 0.7)
        let card = frame.insetBy(dx: -18, dy: -18)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(a))
        ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 36, color: UIColor(white: 0, alpha: 0.22).cgColor)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(UIBezierPath(roundedRect: card, cornerRadius: 22).cgPath)
        ctx.fillPath()
        ctx.restoreGState()
        // Slow push-in (Ken Burns).
        let zoom = 1 + 0.05 * CGFloat(min(max(t / max(duration, 1), 0), 1))
        ctx.saveGState()
        ctx.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 8).cgPath)
        ctx.clip()
        let zw = frame.width * zoom
        let zh = frame.height * zoom
        UIGraphicsPushContext(ctx)
        image.draw(in: CGRect(x: frame.midX - zw / 2, y: frame.midY - zh / 2, width: zw, height: zh), blendMode: .normal, alpha: CGFloat(a))
        UIGraphicsPopContext()
        ctx.restoreGState()
        // Notes beside it.
        var y: CGFloat = 320
        for (k, note) in notes.enumerated() {
            let r = 0.8 + Double(k) * max(0.8, duration * 0.35)
            let na = appear(t, at: r)
            guard na > 0 else { continue }
            let f = fitted(note, width: 440, height: 260, base: 40, minSize: 28, weight: .medium, theme: theme)
            let th = measure(note, width: 440, font: f)
            let rect = CGRect(x: 1300, y: y, width: 500, height: th + 60)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(na))
            ctx.setFillColor(p.card.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 24).cgPath)
            ctx.fillPath()
            ctx.setFillColor(p.accent.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY + 18, width: 8, height: rect.height - 36), cornerRadius: 4).cgPath)
            ctx.fillPath()
            ctx.restoreGState()
            text(note, in: rect.insetBy(dx: 30, dy: 30), font: f, color: p.cardText, alpha: na, ctx: ctx)
            y += rect.height + 30
        }
    }

    private static func drawDefinition(_ scene: OverviewScene, enter: Double, p: Palette, theme: SlideTheme, en: Bool, in ctx: CGContext) {
        let label = en ? "DEFINITION" : "TANIM"
        let la = appear(enter, at: 0)
        chip(label, at: CGPoint(x: 140, y: 120), color: p.accent, alpha: la, theme: theme, in: ctx)
        let term = scene.term ?? scene.title
        let hasArt = scene.art != nil
        let h = headline(term, in: CGRect(x: 140, y: 200, width: hasArt ? 1250 : 1640, height: 220), base: 110, minSize: 60,
                         enter: enter, delay: 0.2, centered: false, p: Palette(top: p.top, bottom: p.bottom, text: p.accent,
                         muted: p.muted, accent: p.accent, accent2: p.accent2, good: p.good, card: p.card, cardText: p.cardText,
                         usesInk: p.usesInk, chalk: p.chalk), theme: theme, in: ctx)
        if let art = scene.art {
            let a = appear(enter, at: 0.5, length: 0.7)
            drawArt(art, in: CGRect(x: 1460, y: 150, width: 300, height: 300), color: p.accent, alpha: a, in: ctx)
        }
        if let def = scene.definition {
            let a = appear(enter, at: 0.9, length: 0.6)
            let top = max(470, 200 + h + 60)
            let rect = CGRect(x: 140, y: top + CGFloat(1 - a) * 24, width: 1640, height: min(440, 980 - top))
            ctx.saveGState()
            ctx.setAlpha(CGFloat(a))
            ctx.setFillColor(p.card.cgColor)
            if theme == .modern || theme == .explainer {
                ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: UIColor(white: 0, alpha: 0.10).cgColor)
            }
            ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 30).cgPath)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.setFillColor(p.accent.withAlphaComponent(CGFloat(a)).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY + 28, width: 10, height: rect.height - 56), cornerRadius: 5).cgPath)
            ctx.fillPath()
            let inner = rect.insetBy(dx: 60, dy: 44)
            let f = fitted(def, width: inner.width, height: inner.height, base: 52, minSize: 32, weight: .regular, theme: theme)
            text(def, in: inner, font: f, color: p.cardText, alpha: a, lineSpacing: 10, ctx: ctx)
        }
    }

    private static func drawCompare(_ scene: OverviewScene, t: Double, duration: Double, p: Palette, theme: SlideTheme, in ctx: CGContext) {
        guard let l = scene.left, let r = scene.right else { return }
        let columns = [(l, CGRect(x: 140, y: 290, width: 780, height: 660), p.accent, 0.3),
                       (r, CGRect(x: 1000, y: 290, width: 780, height: 660), p.accent2, max(1.0, duration * 0.42))]
        for (column, rect, color, start) in columns {
            let a = appear(t, at: start, length: 0.6)
            guard a > 0 else { continue }
            let shifted = rect.offsetBy(dx: 0, dy: CGFloat(1 - a) * 30)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(a))
            ctx.setFillColor(p.card.cgColor)
            if theme == .modern || theme == .explainer {
                ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: UIColor(white: 0, alpha: 0.10).cgColor)
            }
            ctx.addPath(UIBezierPath(roundedRect: shifted, cornerRadius: 30).cgPath)
            ctx.fillPath()
            ctx.restoreGState()
            let header = CGRect(x: shifted.minX, y: shifted.minY, width: shifted.width, height: 110)
            ctx.saveGState()
            ctx.addPath(UIBezierPath(roundedRect: shifted, cornerRadius: 30).cgPath)
            ctx.clip()
            ctx.setFillColor(color.withAlphaComponent(CGFloat(a) * (p.chalk ? 0.35 : 1)).cgColor)
            ctx.fill(header)
            ctx.restoreGState()
            text(column.title, in: header.insetBy(dx: 36, dy: 28), font: fitted(column.title, width: header.width - 72, height: 60,
                 base: 44, minSize: 28, weight: .bold, theme: theme), color: p.chalk ? p.text : .white, alpha: a, ctx: ctx)
            let body = CGRect(x: shifted.minX + 40, y: shifted.minY + 140, width: shifted.width - 80, height: shifted.height - 170)
            let joined = column.items.map { "•  " + $0 }.joined(separator: "\n")
            let f = fitted(joined, width: body.width, height: body.height, base: 40, minSize: 26, weight: .medium, theme: theme)
            text(joined, in: body, font: f, color: p.cardText, alpha: a, lineSpacing: 14, ctx: ctx)
        }
        // "vs" between the cards.
        let va = appear(t, at: 0.6)
        if va > 0 {
            ctx.setFillColor(p.text.withAlphaComponent(CGFloat(va)).cgColor)
            ctx.fillEllipse(in: CGRect(x: 960 - 44, y: 620 - 44, width: 88, height: 88))
            text("vs", in: CGRect(x: 916, y: 596, width: 88, height: 50), font: font(36, .heavy, .modern),
                 color: p.top, align: .center, alpha: va, ctx: ctx)
        }
    }

    private static func drawQuote(_ scene: OverviewScene, enter: Double, p: Palette, theme: SlideTheme, in ctx: CGContext) {
        let a = appear(enter, at: 0.1, length: 0.8)
        text("“", in: CGRect(x: 150, y: 120, width: 300, height: 300), font: UIFont.systemFont(ofSize: 340, weight: .black),
             color: p.accent.withAlphaComponent(0.22), alpha: a, ctx: ctx)
        let quote = scene.subtitle ?? scene.title
        let rect = CGRect(x: 240, y: 300, width: 1440, height: 440)
        let f = fitted(quote, width: rect.width, height: rect.height, base: 80, minSize: 44, weight: .semibold, theme: theme)
        let h = measure(quote, width: rect.width, font: f, lineSpacing: 10)
        text(quote, in: CGRect(x: rect.minX, y: rect.midY - h / 2 + CGFloat(1 - a) * 20, width: rect.width, height: h + 10),
             font: f, color: p.text, align: .center, alpha: a, lineSpacing: 10, ctx: ctx)
        if !scene.title.isEmpty && scene.subtitle != nil {
            let la = appear(enter, at: 1.0)
            text("— " + scene.title, in: CGRect(x: 240, y: rect.midY + h / 2 + 50, width: 1440, height: 60),
                 font: font(34, .semibold, theme), color: p.accent, align: .center, alpha: la, ctx: ctx)
        }
    }

    private static func drawQuiz(_ scene: OverviewScene, t: Double, duration: Double, p: Palette, theme: SlideTheme, en: Bool, in ctx: CGContext) {
        let enter = t + 0.5
        chip(scene.title.isEmpty ? (en ? "QUICK QUESTION" : "HIZLI SORU") : scene.title.uppercased(),
             at: CGPoint(x: 140, y: 110), color: p.accent2, alpha: appear(enter, at: 0), theme: theme, in: ctx)
        let question = scene.subtitle ?? scene.title
        let qa = appear(enter, at: 0.2)
        let qf = fitted(question, width: 1640, height: 220, base: 64, minSize: 38, weight: .bold, theme: theme)
        text(question, in: CGRect(x: 140, y: 190 + CGFloat(1 - qa) * 20, width: 1640, height: 230), font: qf, color: p.text, alpha: qa, ctx: ctx)
        let revealAt = max(2.5, duration * 0.62)
        let revealed = t >= revealAt
        let letters = ["A", "B", "C", "D"]
        let longest = scene.choices.max(by: { $0.count < $1.count }) ?? ""
        let cf = fitted(longest, width: 640, height: 110, base: 40, minSize: 26, weight: .medium, theme: theme)
        for (k, choice) in scene.choices.prefix(4).enumerated() {
            let a = appear(t, at: 0.6 + Double(k) * 0.25)
            guard a > 0 else { continue }
            let col = CGFloat(k % 2)
            let row = CGFloat(k / 2)
            let rect = CGRect(x: 140 + col * 840, y: 470 + row * 200 + CGFloat(1 - a) * 20, width: 800, height: 170)
            let correct = scene.answer == k
            var alpha = a
            if revealed && !correct { alpha *= 0.42 }
            ctx.saveGState()
            ctx.setAlpha(CGFloat(alpha))
            ctx.setFillColor((revealed && correct ? p.good.withAlphaComponent(p.chalk ? 0.35 : 0.16) : p.card).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 28).cgPath)
            ctx.fillPath()
            if revealed && correct {
                ctx.setStrokeColor(p.good.cgColor)
                ctx.setLineWidth(6)
                ctx.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 26).cgPath)
                ctx.strokePath()
            }
            let badge = CGRect(x: rect.minX + 28, y: rect.midY - 36, width: 72, height: 72)
            ctx.setFillColor((revealed && correct ? p.good : p.accent).cgColor)
            ctx.fillEllipse(in: badge)
            ctx.restoreGState()
            text(revealed && correct ? "✓" : letters[k], in: CGRect(x: badge.minX, y: badge.minY + 12, width: badge.width, height: 50),
                 font: font(36, .bold, .modern), color: p.chalk ? p.top : .white, align: .center, alpha: alpha, ctx: ctx)
            let th = measure(choice, width: 640, font: cf)
            text(choice, in: CGRect(x: rect.minX + 126, y: rect.midY - th / 2, width: 640, height: th + 6), font: cf,
                 color: p.cardText, alpha: alpha, ctx: ctx)
        }
        // Thinking time: a ring that empties until the answer shows.
        if !revealed && t > 0.8 {
            let left = 1 - min(max((t - 0.8) / max(revealAt - 0.8, 0.1), 0), 1)
            let c = CGPoint(x: 1740, y: 140)
            ctx.setStrokeColor(p.muted.withAlphaComponent(0.25).cgColor)
            ctx.setLineWidth(10)
            ctx.addArc(center: c, radius: 44, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
            ctx.setStrokeColor(p.accent2.cgColor)
            ctx.setLineCap(.round)
            ctx.addArc(center: c, radius: 44, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * CGFloat(left), clockwise: false)
            ctx.strokePath()
        }
    }

    private static func chip(_ s: String, at origin: CGPoint, color: UIColor, alpha: Double, theme: SlideTheme, in ctx: CGContext) {
        guard alpha > 0 else { return }
        let f = font(26, .heavy, theme == .notebook || theme == .chalkboard ? .modern : theme)
        let w = width(of: s, font: f) + 48
        let rect = CGRect(x: origin.x, y: origin.y, width: w, height: 52)
        ctx.setFillColor(color.withAlphaComponent(0.16 * CGFloat(alpha)).cgColor)
        ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 26).cgPath)
        ctx.fillPath()
        text(s, in: CGRect(x: rect.minX + 24, y: rect.minY + 11, width: w - 48, height: 34), font: f, color: color, alpha: alpha, ctx: ctx)
    }

    // MARK: Pictures

    private static let symbolCache = NSCache<NSString, UIImage>()

    static func drawArt(_ art: String, in rect: CGRect, color: UIColor, alpha: Double, in ctx: CGContext) {
        guard alpha > 0.01 else { return }
        if art.hasPrefix("art:") {
            layer(alpha: alpha, ctx) {
                StickerArt.draw(art, in: rect, context: ctx)
            }
            return
        }
        let name = art.hasPrefix("sf:") ? String(art.dropFirst(3)) : art
        let key = "\(name)#\(Int(rect.height))#\(color.hashValue)" as NSString
        var found = symbolCache.object(forKey: key)
        if found == nil {
            let config = UIImage.SymbolConfiguration(pointSize: rect.height * 0.7, weight: .semibold)
            found = UIImage(systemName: name, withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal)
            if let made = found { symbolCache.setObject(made, forKey: key) }
        }
        guard let image = found else { return }
        let s = image.size
        let k = min(rect.width / max(s.width, 1), rect.height / max(s.height, 1))
        let w = s.width * k
        let h = s.height * k
        UIGraphicsPushContext(ctx)
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h), blendMode: .normal, alpha: CGFloat(alpha))
        UIGraphicsPopContext()
    }

    // MARK: Ink lettering (the app's pen font, written on stroke by stroke)

    private static let inkLock = NSLock()
    private static var inkCache: [String: (paths: [[CGPoint]], lengths: [CGFloat], total: CGFloat, height: CGFloat)] = [:]

    private static func inkWidth(_ s: String, cap: CGFloat) -> CGFloat {
        CGFloat(StrokeFont.width(s)) * cap / 10
    }

    /// The largest cap height (≤ `base`) at which `s` fits the box in at most three lines.
    private static func inkCap(_ s: String, width: CGFloat, height: CGFloat, base: CGFloat) -> CGFloat {
        var cap = base
        while cap > 22 {
            let lines = inkLines(s, cap: cap, maxWidth: width)
            if lines.count <= 3 && CGFloat(lines.count) * cap * 1.95 <= height + cap * 0.4 { return cap }
            cap -= 4
        }
        return 22
    }

    private static func inkLines(_ s: String, cap: CGFloat, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in s.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if inkWidth(candidate, cap: cap) > maxWidth && !current.isEmpty {
                lines.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    @discardableResult
    private static func drawInk(_ s: String, origin: CGPoint, cap: CGFloat, maxWidth: CGFloat, centered: Bool, color: UIColor,
                                reveal: Double, chalk: Bool, in ctx: CGContext) -> CGFloat {
        let key = "\(s)|\(Int(cap))|\(Int(maxWidth))|\(centered)|\(Int(origin.x)),\(Int(origin.y))"
        inkLock.lock()
        var entry = inkCache[key]
        inkLock.unlock()
        if entry == nil {
            let lines = inkLines(s, cap: cap, maxWidth: maxWidth)
            let lineHeight = cap * 1.95
            var paths: [[CGPoint]] = []
            for (k, line) in lines.enumerated() {
                let w = inkWidth(line, cap: cap)
                let x = centered ? origin.x + (maxWidth - w) / 2 : origin.x
                let baseline = origin.y + cap * 1.25 + CGFloat(k) * lineHeight
                let ps = StrokeFont.paths(line, origin: SIMD2<Float>(Float(x), Float(baseline)), capHeight: Float(cap))
                paths += ps.map { path in path.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } }
            }
            var lengths: [CGFloat] = []
            for path in paths {
                var l: CGFloat = 0
                if path.count > 1 {
                    for j in 1..<path.count { l += hypot(path[j].x - path[j - 1].x, path[j].y - path[j - 1].y) }
                }
                lengths.append(max(l, 0.5))
            }
            let built = (paths: paths, lengths: lengths, total: lengths.reduce(0, +), height: CGFloat(lines.count) * lineHeight)
            inkLock.lock()
            if inkCache.count > 400 { inkCache.removeAll() }
            inkCache[key] = built
            inkLock.unlock()
            entry = built
        }
        guard let ink = entry else { return 0 }
        guard reveal > 0 else { return ink.height }
        let limit = ink.total * CGFloat(min(reveal, 1))
        func strokeAll(width: CGFloat, alpha: CGFloat, offset: CGPoint) {
            ctx.setStrokeColor(color.withAlphaComponent(color.cgColor.alpha * alpha).cgColor)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            var used: CGFloat = 0
            for (k, path) in ink.paths.enumerated() {
                guard used < limit, let first = path.first else { break }
                ctx.move(to: CGPoint(x: first.x + offset.x, y: first.y + offset.y))
                if path.count == 1 {
                    ctx.addLine(to: CGPoint(x: first.x + offset.x + 0.1, y: first.y + offset.y))
                }
                var j = 1
                while j < path.count {
                    let a = path[j - 1]
                    let b = path[j]
                    let seg = hypot(b.x - a.x, b.y - a.y)
                    if used + seg > limit {
                        let f = seg > 0 ? (limit - used) / seg : 0
                        ctx.addLine(to: CGPoint(x: a.x + (b.x - a.x) * f + offset.x, y: a.y + (b.y - a.y) * f + offset.y))
                        used = limit
                        break
                    }
                    ctx.addLine(to: CGPoint(x: b.x + offset.x, y: b.y + offset.y))
                    used += seg
                    j += 1
                }
                if path.count <= 1 { used += ink.lengths[k] }
            }
            ctx.strokePath()
        }
        if chalk {
            strokeAll(width: cap * 0.12, alpha: 0.9, offset: .zero)
            strokeAll(width: cap * 0.06, alpha: 0.35, offset: CGPoint(x: cap * 0.03, y: -cap * 0.025))
        } else {
            strokeAll(width: cap * 0.095, alpha: 1, offset: .zero)
        }
        return ink.height
    }

    // MARK: Text

    static func font(_ size: CGFloat, _ weight: UIFont.Weight, _ theme: SlideTheme) -> UIFont {
        let bold = weight.rawValue >= UIFont.Weight.semibold.rawValue
        switch theme {
        case .notebook:
            if let f = UIFont(name: bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size) { return f }
        case .chalkboard:
            if let f = UIFont(name: bold ? "ChalkboardSE-Bold" : "ChalkboardSE-Regular", size: size) { return f }
        case .explainer:
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .modern, .night:
            break
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: size)
        }
        return base
    }

    private static let fitLock = NSLock()
    private static var fitCache: [String: CGFloat] = [:]

    /// The largest font (from `base` down to `minSize`) at which `s` fits the box.
    static func fitted(_ s: String, width: CGFloat, height: CGFloat, base: CGFloat, minSize: CGFloat,
                       weight: UIFont.Weight, theme: SlideTheme) -> UIFont {
        let key = "\(s)|\(Int(width))|\(Int(height))|\(Int(base))|\(weight.rawValue)|\(theme.rawValue)"
        fitLock.lock()
        let cached = fitCache[key]
        fitLock.unlock()
        if let cached { return font(cached, weight, theme) }
        var size = base
        while size > minSize {
            if measure(s, width: width, font: font(size, weight, theme)) <= height { break }
            size -= 3
        }
        size = max(size, minSize)
        fitLock.lock()
        if fitCache.count > 600 { fitCache.removeAll() }
        fitCache[key] = size
        fitLock.unlock()
        return font(size, weight, theme)
    }

    private static func attributed(_ s: String, font: UIFont, color: UIColor, align: NSTextAlignment, lineSpacing: CGFloat) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineSpacing = lineSpacing
        para.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    static func measure(_ s: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat = 6) -> CGFloat {
        let a = attributed(s, font: font, color: .black, align: .left, lineSpacing: lineSpacing)
        let r = a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(r.height)
    }

    static func width(of s: String, font: UIFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    static func text(_ s: String, in rect: CGRect, font: UIFont, color: UIColor, align: NSTextAlignment = .left,
                     alpha: Double = 1, lineSpacing: CGFloat = 6, ctx: CGContext) {
        guard alpha > 0.005, !s.isEmpty else { return }
        let c = color.withAlphaComponent(color.cgColor.alpha * CGFloat(min(alpha, 1)))
        let a = attributed(s, font: font, color: c, align: align, lineSpacing: lineSpacing)
        UIGraphicsPushContext(ctx)
        a.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
        UIGraphicsPopContext()
    }
}

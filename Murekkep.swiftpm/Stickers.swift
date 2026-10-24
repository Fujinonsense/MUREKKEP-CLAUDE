import Metal
import SwiftUI
import UIKit

/// A picture placed on a page: one of the app's vector illustrations ("art:heart"). Notes from 2.4
/// may still hold emoji symbols; those keep drawing as before.
struct Sticker: Codable, Identifiable, Equatable {
    var id = UUID()
    var symbol: String
    /// Page-local rectangle in points, before turning.
    var rect: CGRect
    /// Turn in radians around the rectangle's middle (missing in older notes = 0).
    var angle: Double?
    /// Flipped left to right.
    var mirrored: Bool?
    /// Set when the user finished placing it: from then on it is part of the page. It can be erased
    /// and written on, but no longer selected, moved or resized.
    var embedded: Bool?

    var rotation: CGFloat { CGFloat(angle ?? 0) }
    var isMirrored: Bool { mirrored ?? false }
    var isEmbedded: Bool { embedded ?? false }

    /// The page area it covers once turned.
    var frame: CGRect {
        guard rotation != 0 else { return rect }
        let c = cos(rotation)
        let s = sin(rotation)
        let w = abs(rect.width * c) + abs(rect.height * s)
        let h = abs(rect.width * s) + abs(rect.height * c)
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

// MARK: - Catalog

enum StickerCatalog {
    struct Group: Identifiable {
        let title: String
        let symbols: [String]
        var id: String { title }
    }

    static var groups: [Group] { [
        Group(title: Loc.t("Anatomi"), symbols: ["art:heart", "art:lungs", "art:kidney", "art:spleen", "art:liver", "art:stomach", "art:brain"]),
        Group(title: Loc.t("Yüzler"), symbols: ["art:happy", "art:laugh", "art:wink", "art:love", "art:sad", "art:cry", "art:surprised"]),
        Group(title: Loc.t("Kalpler"), symbols: ["art:redheart", "art:pinkheart", "art:brokenheart"]),
        Group(title: Loc.t("İşaretler"), symbols: ["art:star", "art:check", "art:cross", "art:warning", "art:question", "art:bulb"]),
        Group(title: Loc.t("Fen"), symbols: ["art:atom", "art:flask"]),
    ] }

    static func title(_ symbol: String) -> String {
        StickerArt.library[StickerArt.name(symbol)].map { Loc.named($0.title, kind: "sticker") } ?? symbol
    }
}

// MARK: - Drawing

/// Draws the vector pictures of `StickerArtData` with Core Graphics (y down). Used for the GPU
/// textures, the PDF export, thumbnails and the menus, so every place shows the same picture.
enum StickerArt {
    enum Paint {
        case solid(CGColor)
        case linear(CGColor, CGColor, CGPoint, CGPoint)
        case radial(CGColor, CGColor, CGPoint, CGFloat)

        var baseColor: CGColor {
            switch self {
            case let .solid(c): return c
            case let .linear(_, c, _, _): return c
            case let .radial(_, c, _, _): return c
            }
        }
    }

    enum Layer {
        case fill(CGPath, Paint, shadow: Bool)
        case stroke(CGPath, CGColor, CGFloat)
        case gloss(CGRect)
    }

    struct Art {
        let name: String
        let title: String
        let layers: [Layer]
        /// The main body outlines (the shadowed fills), for recognizing drawings.
        let bodies: [CGPath]
    }

    static func isArt(_ symbol: String) -> Bool { symbol.hasPrefix("art:") }

    static func name(_ symbol: String) -> String {
        isArt(symbol) ? String(symbol.dropFirst(4)) : symbol
    }

    static let library: [String: Art] = parse(StickerArtData.source)

    /// Points along a body outline of `name` in its 100 × 100 box.
    static func bodyOutline(_ name: String, which: Int = 0) -> [CGPoint] {
        guard let art = library[name], art.bodies.indices.contains(which) else { return [] }
        return flatten(art.bodies[which])
    }

    static func draw(_ symbol: String, in rect: CGRect, context ctx: CGContext) {
        guard isArt(symbol) else {
            // Older notes: an emoji.
            let font = UIFont.systemFont(ofSize: rect.height * 0.8)
            let s = NSAttributedString(string: symbol, attributes: [.font: font])
            let size = s.size()
            UIGraphicsPushContext(ctx)
            s.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            UIGraphicsPopContext()
            return
        }
        guard let art = library[name(symbol)] else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 100, y: rect.height / 100)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        for layer in art.layers {
            switch layer {
            case let .fill(path, paint, shadow):
                if shadow {
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: CGColor(gray: 0, alpha: 0.28))
                    ctx.addPath(path)
                    ctx.setFillColor(paint.baseColor)
                    ctx.fillPath()
                    ctx.restoreGState()
                }
                switch paint {
                case let .solid(c):
                    ctx.addPath(path)
                    ctx.setFillColor(c)
                    ctx.fillPath()
                case let .linear(a, b, p0, p1):
                    ctx.saveGState()
                    ctx.addPath(path)
                    ctx.clip()
                    if let g = CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1]) {
                        ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    }
                    ctx.restoreGState()
                case let .radial(a, b, c, r):
                    ctx.saveGState()
                    ctx.addPath(path)
                    ctx.clip()
                    if let g = CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1]) {
                        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
                    }
                    ctx.restoreGState()
                }
            case let .stroke(path, color, width):
                ctx.addPath(path)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(width)
                ctx.strokePath()
            case let .gloss(r):
                ctx.saveGState()
                ctx.translateBy(x: r.midX, y: r.midY)
                ctx.scaleBy(x: 1, y: r.height / max(r.width, 0.01))
                let colors = [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r.width / 2, options: [])
                }
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    /// Stickers of a page for the PDF export and thumbnails (turned stickers included).
    static func drawAll(_ stickers: [Sticker], in ctx: CGContext) {
        for s in stickers {
            ctx.saveGState()
            ctx.translateBy(x: s.rect.midX, y: s.rect.midY)
            ctx.rotate(by: s.rotation)
            if s.isMirrored { ctx.scaleBy(x: -1, y: 1) }
            draw(s.symbol, in: CGRect(x: -s.rect.width / 2, y: -s.rect.height / 2, width: s.rect.width, height: s.rect.height), context: ctx)
            ctx.restoreGState()
        }
    }

    private static let imageCache = NSCache<NSString, UIImage>()

    /// A square picture for menus.
    static func image(_ symbol: String, side: CGFloat) -> UIImage {
        let key = "\(symbol)#\(Int(side))" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            draw(symbol, in: CGRect(x: 0, y: 0, width: side, height: side), context: ctx.cgContext)
        }
        imageCache.setObject(image, forKey: key)
        return image
    }

    // MARK: Parsing

    private static func parse(_ source: String) -> [String: Art] {
        var out: [String: Art] = [:]
        var name: String?
        var title = ""
        var layers: [Layer] = []
        var bodies: [CGPath] = []
        func finish() {
            if let name { out[name] = Art(name: name, title: title, layers: layers, bodies: bodies) }
            layers = []
            bodies = []
        }
        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("@") {
                finish()
                let parts = line.dropFirst().split(separator: " ", maxSplits: 1)
                name = parts.first.map(String.init)
                title = parts.count > 1 ? String(parts[1]) : ""
                continue
            }
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 3 else { continue }
            let op = tokens[0]
            let paintToken = tokens[1]
            let rest = Array(tokens[2...])
            switch op {
            case "F", "F*":
                guard let fill = Self.paint(paintToken) else { continue }
                let path = svgPath(rest.joined(separator: " "))
                layers.append(.fill(path, fill, shadow: op == "F*"))
                if op == "F*" { bodies.append(path) }
            case "S":
                guard let p = Self.pen(paintToken) else { continue }
                layers.append(.stroke(svgPath(rest.joined(separator: " ")), p.0, p.1))
            case "E":
                guard let fill = Self.paint(paintToken), let r = ellipseRect(rest) else { continue }
                layers.append(.fill(CGPath(ellipseIn: r, transform: nil), fill, shadow: false))
            case "O":
                guard let p = Self.pen(paintToken), let r = ellipseRect(rest) else { continue }
                layers.append(.stroke(CGPath(ellipseIn: r, transform: nil), p.0, p.1))
            case "G":
                guard let r = ellipseRect(rest) else { continue }
                layers.append(.gloss(r))
            default:
                continue
            }
        }
        finish()
        return out
    }

    private static func ellipseRect(_ v: [String]) -> CGRect? {
        let n = v.compactMap { Double($0) }
        guard n.count >= 4 else { return nil }
        return CGRect(x: n[0] - n[2], y: n[1] - n[3], width: n[2] * 2, height: n[3] * 2)
    }

    private static func color(_ hex: String) -> CGColor? {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func paint(_ token: String) -> Paint? {
        if token.hasPrefix("lin(") || token.hasPrefix("rad(") {
            let inner = token.dropFirst(4).dropLast()
            let parts = inner.split(separator: ",").map(String.init)
            guard parts.count >= 5, let a = color(parts[0]), let b = color(parts[1]) else { return nil }
            let n = parts.dropFirst(2).compactMap { Double($0) }.map { CGFloat($0) }
            if token.hasPrefix("lin("), n.count >= 4 {
                return .linear(a, b, CGPoint(x: n[0], y: n[1]), CGPoint(x: n[2], y: n[3]))
            }
            if n.count >= 3 {
                return .radial(a, b, CGPoint(x: n[0], y: n[1]), n[2])
            }
            return nil
        }
        return color(token).map { Paint.solid($0) }
    }

    private static func pen(_ token: String) -> (CGColor, CGFloat)? {
        let parts = token.split(separator: "/")
        guard parts.count == 2, let c = color(String(parts[0])), let w = Double(parts[1]) else { return nil }
        return (c, CGFloat(w))
    }

    /// SVG path data with absolute M L H V C Q Z.
    private static func svgPath(_ d: String) -> CGPath {
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty {
                tokens.append(number)
                number = ""
            }
        }
        for ch in d {
            if ch.isLetter {
                flush()
                tokens.append(String(ch))
            } else if ch == "-" {
                flush()
                number = "-"
            } else if ch.isNumber || ch == "." {
                number.append(ch)
            } else {
                flush()
            }
        }
        flush()
        let path = CGMutablePath()
        var i = 0
        var command = ""
        var current = CGPoint.zero
        func next() -> CGFloat? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                command = tokens[i]
                i += 1
                if command == "Z" {
                    path.closeSubpath()
                    continue
                }
            }
            switch command {
            case "M":
                guard let x = next(), let y = next() else { i += 1; continue }
                current = CGPoint(x: x, y: y)
                path.move(to: current)
                command = "L"
            case "L":
                guard let x = next(), let y = next() else { i += 1; continue }
                current = CGPoint(x: x, y: y)
                path.addLine(to: current)
            case "H":
                guard let x = next() else { i += 1; continue }
                current = CGPoint(x: x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = next() else { i += 1; continue }
                current = CGPoint(x: current.x, y: y)
                path.addLine(to: current)
            case "C":
                guard let x1 = next(), let y1 = next(), let x2 = next(), let y2 = next(), let x = next(), let y = next() else {
                    i += 1
                    continue
                }
                current = CGPoint(x: x, y: y)
                path.addCurve(to: current, control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case "Q":
                guard let x1 = next(), let y1 = next(), let x = next(), let y = next() else { i += 1; continue }
                current = CGPoint(x: x, y: y)
                path.addQuadCurve(to: current, control: CGPoint(x: x1, y: y1))
            default:
                i += 1
            }
        }
        return path
    }

    /// Points along a path (curves subdivided).
    static func flatten(_ path: CGPath) -> [CGPoint] {
        var out: [CGPoint] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        // Typed closure and one weight per term: the long Bézier sums otherwise exceed the compiler's
        // type-checking time limit.
        path.applyWithBlock { (element: UnsafePointer<CGPathElement>) -> Void in
            let e = element.pointee
            let pts = e.points
            switch e.type {
            case .moveToPoint:
                current = pts[0]
                start = current
                out.append(current)
            case .addLineToPoint:
                current = pts[0]
                out.append(current)
            case .addQuadCurveToPoint:
                let c = pts[0]
                let p = pts[1]
                for k in 1...10 {
                    let s = CGFloat(k) / 10
                    let u: CGFloat = 1 - s
                    let w0: CGFloat = u * u
                    let w1: CGFloat = 2 * u * s
                    let w2: CGFloat = s * s
                    let x: CGFloat = w0 * current.x + w1 * c.x + w2 * p.x
                    let y: CGFloat = w0 * current.y + w1 * c.y + w2 * p.y
                    out.append(CGPoint(x: x, y: y))
                }
                current = p
            case .addCurveToPoint:
                let a = pts[0]
                let b = pts[1]
                let p = pts[2]
                for k in 1...12 {
                    let s = CGFloat(k) / 12
                    let u: CGFloat = 1 - s
                    let w0: CGFloat = u * u * u
                    let w1: CGFloat = 3 * u * u * s
                    let w2: CGFloat = 3 * u * s * s
                    let w3: CGFloat = s * s * s
                    let x: CGFloat = w0 * current.x + w1 * a.x + w2 * b.x + w3 * p.x
                    let y: CGFloat = w0 * current.y + w1 * a.y + w2 * b.y + w3 * p.y
                    out.append(CGPoint(x: x, y: y))
                }
                current = p
            case .closeSubpath:
                out.append(start)
                current = start
            @unknown default:
                break
            }
        }
        return out
    }
}

/// A sticker in SwiftUI menus.
struct StickerThumb: View {
    let symbol: String
    var side: CGFloat = 34

    var body: some View {
        if StickerArt.isArt(symbol) {
            Image(uiImage: StickerArt.image(symbol, side: side * 2))
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
        } else {
            Text(symbol)
                .font(.system(size: side * 0.82))
                .frame(width: side, height: side)
        }
    }
}

// MARK: - GPU

/// Draws stickers as textured quads under the ink, so notes can be written on top of them. Textures
/// follow the zoom (sharper ones are drawn in the background while a softer one fills in). Has its
/// own small shader library; the ink shaders are untouched.
final class StickerKit {
    private static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct FrameUniforms {
        float2 drawableSize;
        float2 viewOffset;
        float  scale;
        float  pixelSize;
        float  time;
        float  dryDuration;
        float  waveTime;
        float  coolDuration;
    };

    struct StickerUniforms {
        float4 rect;
        float4 tint;
        float4 turn;   // x: angle in radians, y: 1 when flipped left to right
    };

    struct StickerOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex StickerOut sticker_vertex(uint vid [[vertex_id]],
                                     constant FrameUniforms& fu [[buffer(0)]],
                                     constant StickerUniforms& su [[buffer(1)]])
    {
        float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
        float2 center = su.rect.xy + su.rect.zw * 0.5;
        float2 local = (corner - 0.5) * su.rect.zw;
        float c = cos(su.turn.x);
        float s = sin(su.turn.x);
        float2 doc = center + float2(local.x * c - local.y * s, local.x * s + local.y * c);
        float2 px = doc * fu.scale + fu.viewOffset;
        StickerOut o;
        o.position = float4(px.x / fu.drawableSize.x * 2.0 - 1.0, 1.0 - px.y / fu.drawableSize.y * 2.0, 0.0, 1.0);
        o.uv = float2(su.turn.y > 0.5 ? 1.0 - corner.x : corner.x, corner.y);
        return o;
    }

    fragment float4 sticker_fragment(StickerOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     sampler smp [[sampler(0)]],
                                     constant StickerUniforms& su [[buffer(1)]])
    {
        return tex.sample(smp, in.uv) * su.tint.a;
    }
    """#

    private struct Uniforms {
        var rect: SIMD4<Float>
        var tint: SIMD4<Float>
        var turn: SIMD4<Float>
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let onUpdate: () -> Void
    private let workQueue = DispatchQueue(label: "murekkep.stickers", qos: .userInitiated)
    /// symbol → side in pixels → texture.
    private var textures: [String: [Int: MTLTexture]] = [:]
    private var pending = Set<String>()

    init?(device: MTLDevice, queue: MTLCommandQueue, colorFormat: MTLPixelFormat, onUpdate: @escaping () -> Void) {
        self.device = device
        self.queue = queue
        self.onUpdate = onUpdate
        guard let library = try? device.makeLibrary(source: Self.source, options: nil),
              let vfn = library.makeFunction(name: "sticker_vertex"),
              let ffn = library.makeFunction(name: "sticker_fragment") else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vfn
        d.fragmentFunction = ffn
        d.depthAttachmentPixelFormat = .depth32Float
        let c = d.colorAttachments[0]!
        c.pixelFormat = colorFormat
        c.isBlendingEnabled = true
        c.rgbBlendOperation = .add
        c.alphaBlendOperation = .add
        c.sourceRGBBlendFactor = .one
        c.destinationRGBBlendFactor = .oneMinusSourceAlpha
        c.sourceAlphaBlendFactor = .one
        c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let state = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        pipeline = state
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let smp = device.makeSamplerState(descriptor: sd) else { return nil }
        sampler = smp
    }

    /// Texture side for a sticker drawn `pixels` wide: vector pictures go up to 2048 px, emoji (bitmaps
    /// of about 160 px) stay small.
    private static func side(for symbol: String, pixels: CGFloat) -> Int {
        guard StickerArt.isArt(symbol) else { return 320 }
        var side = 256
        while CGFloat(side) < pixels * 1.15 && side < 2048 { side *= 2 }
        return side
    }

    /// Renders a texture; any thread.
    private static func render(_ symbol: String, side: Int, device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        let bytesPerRow = side * 4
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        // UIKit coordinates: y down, so the first row in memory is the top of the picture.
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        StickerArt.draw(symbol, in: CGRect(x: 0, y: 0, width: side, height: side), context: ctx)
        guard let data = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: true)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
        if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: tex)
            blit.endEncoding()
            cb.commit()
        }
        return tex
    }

    /// The sharpest texture at hand; asks for a sharper one in the background when the zoom needs it.
    private func texture(_ symbol: String, pixels: CGFloat) -> MTLTexture? {
        let wanted = Self.side(for: symbol, pixels: pixels)
        let have = textures[symbol] ?? [:]
        if let exact = have[wanted] { return exact }
        let key = "\(symbol)#\(wanted)"
        if !pending.contains(key) {
            pending.insert(key)
            let device = device
            let queue = queue
            workQueue.async { [weak self] in
                let made = autoreleasepool { Self.render(symbol, side: wanted, device: device, queue: queue) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pending.remove(key)
                    guard let made else { return }
                    // Keep only the sharpest and the new one per picture.
                    var list = self.textures[symbol] ?? [:]
                    list[wanted] = made
                    if list.count > 2, let smallest = list.keys.min() { list.removeValue(forKey: smallest) }
                    self.textures[symbol] = list
                    if self.textures.count > 60, let drop = self.textures.keys.first(where: { $0 != symbol }) {
                        self.textures.removeValue(forKey: drop)
                    }
                    self.onUpdate()
                }
            }
        }
        if let best = have.max(by: { $0.key < $1.key })?.value { return best }
        // Nothing yet: a small one right away so the picture never blinks.
        let quick = Self.render(symbol, side: StickerArt.isArt(symbol) ? 256 : 320, device: device, queue: queue)
        if let quick {
            textures[symbol, default: [:]][StickerArt.isArt(symbol) ? 256 : 320] = quick
        }
        return quick
    }

    /// `frame` is the renderer's FrameUniforms; stickers are page-local and placed at `origin`.
    func draw<Frame>(_ stickers: [Sticker], origin: CGPoint, pixelsPerPoint: CGFloat, encoder enc: MTLRenderCommandEncoder,
                     depthOff: MTLDepthStencilState, frame: inout Frame) {
        guard !stickers.isEmpty else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depthOff)
        enc.setVertexBytes(&frame, length: MemoryLayout<Frame>.stride, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        for s in stickers {
            guard let tex = texture(s.symbol, pixels: max(s.rect.width, s.rect.height) * pixelsPerPoint) else { continue }
            var u = Uniforms(rect: SIMD4<Float>(Float(origin.x + s.rect.minX), Float(origin.y + s.rect.minY),
                                                Float(s.rect.width), Float(s.rect.height)),
                             tint: SIMD4<Float>(1, 1, 1, 1),
                             turn: SIMD4<Float>(Float(s.rotation), s.isMirrored ? 1 : 0, 0, 0))
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}

// MARK: - Suggestions

/// Offered after a held drawing was recognized.
struct SketchSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case heart
        case star(crossing: Bool)
        case kidney
        case spleen
        case lungs
        case face(happy: Bool)

        var title: String {
            switch self {
            case .heart: return Loc.t("Kalp")
            case .star: return Loc.t("Yıldız")
            case .kidney: return Loc.t("Böbrek")
            case .spleen: return Loc.t("Dalak")
            case .lungs: return Loc.t("Akciğerler")
            case let .face(happy): return happy ? Loc.t("Gülen yüz") : Loc.t("Üzgün yüz")
            }
        }

        var stickers: [String] {
            switch self {
            case .heart: return ["art:heart", "art:redheart", "art:pinkheart", "art:brokenheart"]
            case .star: return ["art:star"]
            case .kidney: return ["art:kidney"]
            case .spleen: return ["art:spleen"]
            case .lungs: return ["art:lungs"]
            case let .face(happy):
                return happy ? ["art:happy", "art:laugh", "art:wink", "art:love", "art:surprised"]
                             : ["art:sad", "art:cry", "art:surprised"]
            }
        }
    }

    let id = UUID()
    let kind: Kind
    /// The next most likely reading (a kidney can look like a spleen).
    var alternate: Kind? = nil
    let page: Int
    /// Strokes the choice replaces.
    let strokeIDs: Set<Int>
    /// Page-local bounds of the drawing.
    let bounds: CGRect
    /// Canvas-view position for the menu.
    let location: CGPoint

    var title: String { kind.title }

    var stickers: [String] {
        var out = kind.stickers
        if let alternate {
            out += alternate.stickers.filter { !out.contains($0) }.prefix(2)
        }
        return out
    }
}

/// A radial menu like the Apple Pencil palette: the drawing's picture versions around it, keep in the middle.
struct SuggestionPalette: View {
    @ObservedObject var editor: EditorModel
    let suggestion: SketchSuggestion
    let container: CGSize
    @State private var appeared = false
    @State private var showLibrary = false

    private let radius: CGFloat = 96

    private enum Item {
        case sticker(String)
        case cleanHeart
        case cleanStar(crossing: Bool)
        case more
    }

    private var items: [Item] {
        var out: [Item] = suggestion.stickers.map { .sticker($0) }
        if suggestion.kind == .heart { out.insert(.cleanHeart, at: 1) }
        // A held star is first offered as a neat star in the same ink, then as the picture.
        if case let .star(crossing) = suggestion.kind { out.insert(.cleanStar(crossing: crossing), at: 0) }
        out.append(.more)
        return out
    }

    var body: some View {
        let list = items
        let diameter = radius * 2 + 70
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
                .frame(width: diameter, height: diameter)
            ForEach(list.indices, id: \.self) { i in
                let angle = Double(i) / Double(list.count) * 2 * .pi - .pi / 2
                button(list[i], primary: i == 0)
                    .offset(x: CGFloat(cos(angle)) * radius * (appeared ? 1 : 0.4),
                            y: CGFloat(sin(angle)) * radius * (appeared ? 1 : 0.4))
            }
            Button {
                editor.suggestion = nil
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "scribble")
                        .font(.system(size: 18, weight: .semibold))
                    Text(Loc.t("Koru"))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Theme.ink))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Çizimi olduğu gibi bırak"))
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .top) {
            Text(suggestion.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .offset(y: -30)
        }
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .position(clamped(diameter))
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) { appeared = true }
        }
        .sheet(isPresented: $showLibrary) {
            StickerLibrary(editor: editor)
        }
    }

    @ViewBuilder
    private func button(_ item: Item, primary: Bool) -> some View {
        switch item {
        case let .sticker(symbol):
            Button {
                editor.applySuggestion(sticker: symbol)
            } label: {
                StickerThumb(symbol: symbol, side: primary ? 44 : 34)
                    .frame(width: primary ? 58 : 48, height: primary ? 58 : 48)
                    .background(Circle().fill(Color(uiColor: .systemBackground).opacity(0.94)))
                    .overlay(Circle().strokeBorder(primary ? Theme.ink.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: primary ? 2 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(StickerCatalog.title(symbol))
        case .cleanHeart:
            Button {
                editor.applySuggestionCleanHeart()
            } label: {
                Image(systemName: "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(editor.color(for: editor.activeBrush).swiftUIColor)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(uiColor: .systemBackground).opacity(0.94)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Mürekkeple düzgün kalp"))
        case let .cleanStar(crossing):
            Button {
                editor.applySuggestionCleanStar(crossing: crossing)
            } label: {
                Image(systemName: "star")
                    .font(.system(size: primary ? 24 : 20, weight: .semibold))
                    .foregroundStyle(editor.color(for: editor.activeBrush).swiftUIColor)
                    .frame(width: primary ? 58 : 48, height: primary ? 58 : 48)
                    .background(Circle().fill(Color(uiColor: .systemBackground).opacity(0.94)))
                    .overlay(Circle().strokeBorder(primary ? Theme.ink.opacity(0.6) : Color.primary.opacity(0.08),
                                                   lineWidth: primary ? 2 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Mürekkeple düzgün yıldız"))
        case .more:
            Button {
                showLibrary = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(uiColor: .systemBackground).opacity(0.94)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Loc.t("Tüm çıkartmalar"))
        }
    }

    private func clamped(_ d: CGFloat) -> CGPoint {
        let r = d / 2 + 10
        return CGPoint(x: min(max(suggestion.location.x, r), max(r, container.width - r)),
                       y: min(max(suggestion.location.y, r + 30), max(r + 30, container.height - r)))
    }
}

/// Every sticker, grouped. With a pending suggestion the choice replaces the drawing; otherwise it is
/// placed in the middle of the screen.
struct StickerLibrary: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(StickerCatalog.groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    Button {
                                        if editor.suggestion != nil {
                                            editor.applySuggestion(sticker: symbol)
                                        } else {
                                            editor.placeSticker(symbol)
                                        }
                                        dismiss()
                                    } label: {
                                        VStack(spacing: 4) {
                                            StickerThumb(symbol: symbol, side: 44)
                                            Text(StickerCatalog.title(symbol))
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(width: 64, height: 66)
                                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.primary.opacity(0.05)))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(StickerCatalog.title(symbol))
                                }
                            }
                        }
                    }
                    Label(Loc.t("Çizimler vektördür: büyütünce de keskin kalır. Mürekkebin altında durur, üzerine yazıp etiketleyebilirsin. Kementle seçip köşelerinden büyüt, üstteki tutamaçla döndür, silgiyle sil."),
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(Loc.t("Çıkartmalar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Loc.t("Kapat")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

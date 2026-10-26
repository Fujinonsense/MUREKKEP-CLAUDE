import Foundation
import Metal
import QuartzCore

// MARK: - GPU structs (layouts must match InkShaders.swift)

struct FrameUniforms {
    var drawableSize: SIMD2<Float>
    var viewOffset: SIMD2<Float>
    var scale: Float
    var pixelSize: Float
    var time: Float
    var dryDuration: Float
    var waveTime: Float
    var coolDuration: Float
}

struct SegUniforms {
    var pageOrigin: SIMD2<Float>
    var pointOffset: UInt32
    var orderOffset: UInt32
    var depthStep: Float
    /// 1: write depth with a transparent color (the pass before a blend-once pass).
    var depthOnly: Float = 0
    var pad1: SIMD2<Float> = .zero
}

/// A contiguous index range of committed ink; see-through brushes get a run of their own.
struct InkRun {
    var first: Int
    var count: Int
    var blendsOnce: Bool
}

struct QuadUniforms {
    var rect: SIMD4<Float>
    var uvRect: SIMD4<Float>
    var pageOrigin: SIMD2<Float>
    var pageSize: SIMD2<Float>
    var style: UInt32
    var shadowRadius: Float
    var pad: SIMD2<Float> = .zero
}

struct StrokeGPU {
    var color: SIMD4<Float>
    var brush: UInt32
    var birth: Float
    var width: Float
    var seed: Float
}

struct BladeGPU {
    var base: SIMD2<Float>
    var height: Float
    var width: Float
    var lean: Float
    var phase: Float
    var birth: Float
    var depth: Float
    var color: SIMD4<Float>
    var stroke: UInt32
    var kind: UInt32
    var stiffness: Float
    var pad: Float = 0
}

struct FlowerGPU {
    var stem: UInt32
    var radius: Float
    var bloom: Float
    var petals: Float
    var petal: SIMD4<Float>
    var core: SIMD4<Float>
    var spin: Float
    var style: Float
    var pad: SIMD2<Float> = .zero
}

/// The stroke currently being drawn (not yet committed to the model).
struct ActiveStroke {
    var page: Int
    var brush: Brush
    var color: InkColor
    var width: Float
    var seed: Float
    var points: [InkPoint]
    /// Reference-date seconds when the pencil touched down (grass sprouts in drawing order).
    var startTime: Double
}

struct RenderInput {
    /// View position (points) of document point (0, 0).
    var docOriginInView: CGPoint
    /// View points per document point.
    var zoom: CGFloat
    var viewSize: CGSize
    /// Pixels per page point when the widest page fills the view width.
    var fitPixelScale: CGFloat
    var dryDuration: Double
    var coolDuration: Double
    var animateWaves: Bool
    var background: MTLClearColor
}

struct RenderResult {
    /// 0 = nothing moves (render on demand), otherwise the frame rate the visible content needs.
    var animationFPS: Int
    var visiblePages: [Int]
}

enum RendererError: Error {
    case noQueue
    case missingFunction(String)
}

/// Ribbon mesh of one stroke, indices starting at 0. Kept per stroke id so that erasing or moving
/// a few strokes does not rebuild every other stroke on the page.
struct RibbonMesh {
    var vertices: [RibbonVertexGPU]
    var indices: [UInt32]
}

/// GPU geometry for one page's committed strokes.
final class PageGPU {
    var version = -1
    /// Meshes of the strokes currently on the page (stroke ids are never reused).
    var ribbons: [Int: RibbonMesh] = [:]
    /// Stroke ids in buffer order (highlighters first), so a new stroke can be appended.
    var order: [Int] = []
    /// Ribbon meshes of all strokes: highlighters first, then everything else. The buffers have room
    /// to spare; only `vertexCount` vertices, the counted indices and the counted strokes are in use.
    var vertices: MTLBuffer?
    var indices: MTLBuffer?
    var strokes: MTLBuffer?
    var vertexCount = 0
    var blades: MTLBuffer?
    var flowers: MTLBuffer?
    var highlighterIndexCount = 0
    var inkIndexCount = 0
    var inkRuns: [InkRun] = []
    var highlighterStrokes = 0
    var inkStrokes = 0
    var bladeCount = 0
    var flowerCount = 0
    var hasWave = false
    var hasAnimated = false
    var has3D = false
    var latestWetBirth = -Double.infinity
    /// End time of the newest grass stroke (its blades grow and flowers open for a few seconds).
    var latestGrassBirth = -Double.infinity
    /// When the last point of the newest lava starts cooling (lava cools from its first point to its
    /// last at `InkRenderer.lavaCoolSpeed`, then takes the cooling time).
    var latestLavaBirth = -Double.infinity
}

/// Draws pages, PDF textures and 3D ink in a single render pass.
///
/// Every stroke is one ribbon mesh. A per-stroke depth range makes the parts of a stroke that
/// fold over themselves merge (the fragment nearest the centerline wins) while later strokes always
/// land on top; shadows and see-through inks get a depth pass first so they blend only once.
/// Highlighters go first with multiply blending, then soft drop shadows of raised ink, then the ink.
final class InkRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let epoch = Date().timeIntervalSinceReferenceDate
    var pdfTextures: PDFTextureCache?
    var templateTextures: TemplateTextureCache?

    private let inkPipeline: MTLRenderPipelineState
    private let highlighterPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let bladePipeline: MTLRenderPipelineState
    private let flowerPipeline: MTLRenderPipelineState
    private let paperPipeline: MTLRenderPipelineState
    private let texturePipeline: MTLRenderPipelineState
    private let pageShadowPipeline: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthOff: MTLDepthStencilState
    /// Passes only the fragment a depth pass left nearest; writes nothing.
    private let depthNearestOnly: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private var depthTexture: MTLTexture?
    private let inflight = DispatchSemaphore(value: 3)
    private var activeBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var activeDecorBuffers: [MTLBuffer?] = [nil, nil, nil]
    private var frameIndex = 0
    /// A page's meshes were rebuilt during this frame (then no extra prewarming).
    private var rebuiltThisFrame = false
    /// Counts `render` calls; the live stroke's mesh is built once per call.
    private var renderCount = 0
    private var preparedActive: (frame: Int, buffer: MTLBuffer, first: Int, count: Int)?
    /// The committed ink drawn once while the pencil writes (see `InkLayer`).
    private var layerTexture: MTLTexture?
    private var layerKey: InkLayerKey?
    private var layerTime = 0.0
    private var layerFPS = 0
    /// nil until built (or if it cannot be built): frames are then drawn directly.
    private var layerPipeline: MTLRenderPipelineState?
    private var pageCache: [Int: PageGPU] = [:]
    /// Grass geometry per stroke id (strokes never change in place).
    private var grassCache: [Int: GrassField] = [:]
    /// Asks the view for a new frame (a sharper sticker texture is ready).
    var onStickerUpdate: (() -> Void)?
    /// Pictures on pages; built on first use.
    private lazy var stickerKit = StickerKit(device: device, queue: commandQueue, colorFormat: Self.colorFormat,
                                             onUpdate: { [weak self] in self?.onStickerUpdate?() })

    static let colorFormat: MTLPixelFormat = .bgra8Unorm
    private static let strokeSlot = 256 // byte offset of points inside the active-stroke buffer
    private static let bladeVertices = 16 // (BLADE_SEGS + 1) * 2 in the shader
    /// Points per second the cooling runs along a lava stroke (380.0 in the lava shader).
    static let lavaCoolSpeed: Double = 380

    private enum Blend {
        case opaque
        case alpha
        case premultiplied
        case multiply
    }

    init(device: MTLDevice) throws {
        assert(MemoryLayout<FrameUniforms>.stride == 40)
        assert(MemoryLayout<SegUniforms>.stride == 32)
        assert(MemoryLayout<QuadUniforms>.stride == 64)
        assert(MemoryLayout<RibbonVertexGPU>.stride == 48)
        assert(MemoryLayout<StrokeGPU>.stride == 32)
        assert(MemoryLayout<BladeGPU>.stride == 64)
        assert(MemoryLayout<FlowerGPU>.stride == 64)

        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RendererError.noQueue }
        commandQueue = queue
        let library = try Self.shaderLibrary(for: device)

        func pipeline(_ vertexName: String, _ fragmentName: String, _ blend: Blend) throws -> MTLRenderPipelineState {
            guard let vfn = library.makeFunction(name: vertexName) else { throw RendererError.missingFunction(vertexName) }
            guard let ffn = library.makeFunction(name: fragmentName) else { throw RendererError.missingFunction(fragmentName) }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vfn
            d.fragmentFunction = ffn
            d.depthAttachmentPixelFormat = .depth32Float
            let c = d.colorAttachments[0]!
            c.pixelFormat = InkRenderer.colorFormat
            switch blend {
            case .opaque:
                c.isBlendingEnabled = false
            case .alpha:
                c.isBlendingEnabled = true
                c.rgbBlendOperation = .add
                c.alphaBlendOperation = .add
                c.sourceRGBBlendFactor = .sourceAlpha
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .one
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .premultiplied:
                c.isBlendingEnabled = true
                c.rgbBlendOperation = .add
                c.alphaBlendOperation = .add
                c.sourceRGBBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .one
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .multiply:
                c.isBlendingEnabled = true
                c.rgbBlendOperation = .add
                c.alphaBlendOperation = .add
                c.sourceRGBBlendFactor = .destinationColor
                c.destinationRGBBlendFactor = .zero
                c.sourceAlphaBlendFactor = .zero
                c.destinationAlphaBlendFactor = .one
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }

        inkPipeline = try pipeline("ribbon_vertex", "ink_fragment", .premultiplied)
        highlighterPipeline = try pipeline("ribbon_vertex", "highlighter_fragment", .multiply)
        shadowPipeline = try pipeline("ribbon_shadow_vertex", "shadow_fragment", .premultiplied)
        bladePipeline = try pipeline("blade_vertex", "blade_fragment", .premultiplied)
        flowerPipeline = try pipeline("flower_vertex", "flower_fragment", .premultiplied)
        paperPipeline = try pipeline("quad_vertex", "paper_fragment", .opaque)
        texturePipeline = try pipeline("quad_vertex", "texture_fragment", .opaque)
        pageShadowPipeline = try pipeline("quad_vertex", "page_shadow_fragment", .alpha)

        let dw = MTLDepthStencilDescriptor()
        dw.depthCompareFunction = .less
        dw.isDepthWriteEnabled = true
        let off = MTLDepthStencilDescriptor()
        off.depthCompareFunction = .always
        off.isDepthWriteEnabled = false
        let nearest = MTLDepthStencilDescriptor()
        nearest.depthCompareFunction = .lessEqual
        nearest.isDepthWriteEnabled = false
        guard let s1 = device.makeDepthStencilState(descriptor: dw),
              let s2 = device.makeDepthStencilState(descriptor: off),
              let s3 = device.makeDepthStencilState(descriptor: nearest) else { throw RendererError.noQueue }
        depthWrite = s1
        depthOff = s2
        depthNearestOnly = s3

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let smp = device.makeSamplerState(descriptor: sd) else { throw RendererError.noQueue }
        sampler = smp

        // Compiling the layer's small shader takes a moment: done off the main thread, so the first
        // stroke never waits for it.
        DispatchQueue.global(qos: .utility).async { [weak self, device] in
            let pipeline = Self.makeLayerPipeline(device: device)
            DispatchQueue.main.async {
                self?.layerPipeline = pipeline
            }
        }
    }

    var now: Double { Date().timeIntervalSinceReferenceDate }

    /// Shaders are compiled once per app run and shared by every open note.
    private final class LibraryCache: @unchecked Sendable {
        let lock = NSLock()
        var library: MTLLibrary?
    }

    private static let libraryCache = LibraryCache()

    private static func shaderLibrary(for device: MTLDevice) throws -> MTLLibrary {
        let cache = libraryCache
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let lib = cache.library, lib.device === device {
            return lib
        }
        let lib = try device.makeLibrary(source: InkShaders.source, options: nil)
        cache.library = lib
        return lib
    }

    /// Main thread, before asking the view for a drawable. False while the GPU is still busy with
    /// three earlier frames: the caller skips this frame instead of blocking the main thread, so
    /// scrolling and the pencil stay smooth on heavy pages.
    func reserveFrame() -> Bool {
        inflight.wait(timeout: .now() + .milliseconds(4)) == .success
    }

    /// Gives back a reservation that did not lead to `render` (no drawable was available).
    func cancelReservation() {
        inflight.signal()
    }

    /// Encodes and presents one frame after `reserveFrame()` succeeded. `descriptor`/`drawable`
    /// come from the MTKView on the main thread.
    func render(descriptor rpd: MTLRenderPassDescriptor, drawable: CAMetalDrawable, input: RenderInput,
                layout: DocumentLayout, pages: [PageInk], paper: PaperStyle, isPDF: Bool,
                active: ActiveStroke?) -> RenderResult {
        let zoom = max(input.zoom, 0.0001)
        let viewSize = input.viewSize
        guard viewSize.width > 0, viewSize.height > 0 else {
            inflight.signal()
            return RenderResult(animationFPS: 0, visiblePages: [])
        }
        let docRect = CGRect(x: -input.docOriginInView.x / zoom, y: -input.docOriginInView.y / zoom,
                             width: viewSize.width / zoom, height: viewSize.height / zoom)
        let visible = layout.pages(intersecting: docRect.insetBy(dx: -8, dy: -8))
        pdfTextures?.setVisible(visible)

        guard let cb = commandQueue.makeCommandBuffer() else {
            inflight.signal()
            return RenderResult(animationFPS: 0, visiblePages: visible)
        }
        let semaphore = inflight
        cb.addCompletedHandler { _ in semaphore.signal() }

        let texW = drawable.texture.width
        let texH = drawable.texture.height
        let pxPerPoint = CGFloat(texW) / viewSize.width
        let scale = zoom * pxPerPoint
        let nowTime = now
        var frame = FrameUniforms(
            drawableSize: SIMD2<Float>(Float(texW), Float(texH)),
            viewOffset: SIMD2<Float>(Float(input.docOriginInView.x * pxPerPoint), Float(input.docOriginInView.y * pxPerPoint)),
            scale: Float(scale),
            pixelSize: Float(1 / scale),
            time: Float(nowTime - epoch),
            dryDuration: Float(input.dryDuration),
            waveTime: input.animateWaves ? Float(nowTime - epoch) : 0,
            coolDuration: Float(input.coolDuration))

        renderCount &+= 1
        ensureDepth(width: texW, height: texH)
        // While the pencil writes, the committed ink comes from the layer (see InkLayer); otherwise
        // every frame is drawn directly and no layer is kept.
        var layered = false
        if active != nil, layerPipeline != nil, ensureLayer(width: texW, height: texH) {
            layered = true
            let key = InkLayerKey(originX: Double(input.docOriginInView.x), originY: Double(input.docOriginInView.y),
                                  zoom: Double(zoom), width: texW, height: texH, pages: visible,
                                  versions: visible.map { $0 < pages.count ? pages[$0].version : 0 },
                                  animate: input.animateWaves, dry: input.dryDuration, cool: input.coolDuration)
            if !InkLayer.reuse(key: key, old: layerKey, contentFPS: layerFPS, age: nowTime - layerTime) {
                if drawLayer(cb, frame: &frame, visible: visible, layout: layout, pages: pages, input: input,
                             now: nowTime, width: texW, height: texH) {
                    layerKey = key
                    layerTime = nowTime
                } else {
                    layered = false
                    layerKey = nil
                }
            }
        } else {
            layerKey = nil
        }

        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = input.background
        rpd.depthAttachment.texture = depthTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1

        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else {
            cb.commit()
            return RenderResult(animationFPS: 0, visiblePages: visible)
        }
        let fullScissor = MTLScissorRect(x: 0, y: 0, width: texW, height: texH)
        var animationFPS = 0

        for index in visible {
            let rect = layout.pageRects[index]
            drawPageBackground(enc, frame: &frame, index: index, rect: rect, paper: paper, isPDF: isPDF, input: input)
            guard let scissor = scissorRect(for: rect, frame: frame, width: texW, height: texH) else { continue }
            enc.setScissorRect(scissor)
            if index < pages.count, !pages[index].stickers.isEmpty {
                stickerKit?.draw(pages[index].stickers, origin: rect.origin, pixelsPerPoint: CGFloat(frame.scale),
                                 encoder: enc, depthOff: depthOff, frame: &frame)
            }
            let gpu = cached(index: index, page: index < pages.count ? pages[index] : PageInk())
            let activeHere: ActiveStroke? = active?.page == index ? active : nil
            drawStrokes(enc, frame: &frame, gpu: gpu, rect: rect, active: activeHere, part: layered ? .underInk : .all)
            enc.setScissorRect(fullScissor)

            // Water, lava and lightning need smooth motion; sway, glitter and drying ink are fine at 30 fps.
            if input.animateWaves {
                if gpu.hasWave || activeHere?.brush.isFastAnimated == true { animationFPS = 60 }
                if gpu.hasAnimated || activeHere?.brush.isAnimated == true { animationFPS = max(animationFPS, 30) }
            }
            if nowTime - gpu.latestWetBirth < input.dryDuration + 0.3 { animationFPS = max(animationFPS, 30) }
            if nowTime - gpu.latestLavaBirth < input.coolDuration + 0.5 { animationFPS = 60 }
            if nowTime - gpu.latestGrassBirth < 3.4 || activeHere?.brush.growsFlowers == true || activeHere?.brush == .lava {
                animationFPS = 60
            }
        }

        if layered, let pipeline = layerPipeline, let texture = layerTexture {
            // The committed ink over the paper, then the live ink over everything.
            enc.setScissorRect(fullScissor)
            enc.setRenderPipelineState(pipeline)
            enc.setDepthStencilState(depthOff)
            enc.setFragmentTexture(texture, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            if let a = active, visible.contains(a.page), a.page < layout.pageRects.count {
                let rect = layout.pageRects[a.page]
                if let scissor = scissorRect(for: rect, frame: frame, width: texW, height: texH) {
                    enc.setScissorRect(scissor)
                    let gpu = cached(index: a.page, page: a.page < pages.count ? pages[a.page] : PageInk())
                    drawStrokes(enc, frame: &frame, gpu: gpu, rect: rect, active: a, part: .ink, committed: false)
                    enc.setScissorRect(fullScissor)
                }
            }
        }

        if isPDF, let last = visible.last, last + 1 < layout.count {
            _ = pdfTextures?.baseTexture(page: last + 1, desiredScale: input.fitPixelScale)
        }

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
        frameIndex = (frameIndex + 1) % 3
        trimCache(visible: visible)
        if !rebuiltThisFrame {
            prewarm(around: visible, pages: pages)
        }
        rebuiltThisFrame = false
        return RenderResult(animationFPS: animationFPS, visiblePages: visible)
    }

    // MARK: - Ink layer

    /// Draws the committed shadows, inks and grass of the visible pages into the layer, cleared to
    /// transparent (every ink pipeline blends premultiplied, so laying the layer over the paper gives
    /// the same pixels as drawing the ink there). Also notes how fast that ink moves.
    private func drawLayer(_ cb: MTLCommandBuffer, frame: inout FrameUniforms, visible: [Int], layout: DocumentLayout,
                           pages: [PageInk], input: RenderInput, now nowTime: Double, width: Int, height: Int) -> Bool {
        guard let texture = layerTexture else { return false }
        let lpd = MTLRenderPassDescriptor()
        lpd.colorAttachments[0].texture = texture
        lpd.colorAttachments[0].loadAction = .clear
        lpd.colorAttachments[0].storeAction = .store
        lpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        lpd.depthAttachment.texture = depthTexture
        lpd.depthAttachment.loadAction = .clear
        lpd.depthAttachment.storeAction = .dontCare
        lpd.depthAttachment.clearDepth = 1
        guard let enc = cb.makeRenderCommandEncoder(descriptor: lpd) else { return false }
        var fps = 0
        for index in visible where index < layout.pageRects.count {
            let rect = layout.pageRects[index]
            guard let scissor = scissorRect(for: rect, frame: frame, width: width, height: height) else { continue }
            enc.setScissorRect(scissor)
            let gpu = cached(index: index, page: index < pages.count ? pages[index] : PageInk())
            drawStrokes(enc, frame: &frame, gpu: gpu, rect: rect, active: nil, part: .ink)
            // The committed part of the frame-rate rule in `render`.
            if input.animateWaves {
                if gpu.hasWave { fps = 60 }
                if gpu.hasAnimated { fps = max(fps, 30) }
            }
            if nowTime - gpu.latestWetBirth < input.dryDuration + 0.3 { fps = max(fps, 30) }
            if nowTime - gpu.latestLavaBirth < input.coolDuration + 0.5 || nowTime - gpu.latestGrassBirth < 3.4 { fps = 60 }
        }
        enc.endEncoding()
        layerFPS = fps
        return true
    }

    /// A layer texture the size of the drawable; false when it cannot be made.
    private func ensureLayer(width: Int, height: Int) -> Bool {
        if let t = layerTexture, t.width == width, t.height == height { return true }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.colorFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        layerTexture = device.makeTexture(descriptor: d)
        layerKey = nil
        return layerTexture != nil
    }

    /// The pipeline that lays the layer over the frame (premultiplied, like the ink itself). Built
    /// off the main thread when the renderer starts; until then frames are drawn directly.
    private static func makeLayerPipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: InkLayer.shaderSource, options: nil),
              let vfn = library.makeFunction(name: "layer_vertex"),
              let ffn = library.makeFunction(name: "layer_fragment") else { return nil }
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
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    /// Builds the ink of the page just above or below the screen during a quiet frame, so scrolling
    /// onto it does not stall while its strokes are turned into meshes.
    private func prewarm(around visible: [Int], pages: [PageInk]) {
        guard let first = visible.first, let last = visible.last else { return }
        for index in [last + 1, first - 1, last + 2] where pages.indices.contains(index) {
            let page = pages[index]
            guard !page.strokes.isEmpty, pageCache[index]?.version != page.version else { continue }
            _ = cached(index: index, page: page)
            return
        }
    }

    func invalidateAll() {
        pageCache.removeAll()
        layerKey = nil
    }

    // MARK: - Pages

    private func drawPageBackground(_ enc: MTLRenderCommandEncoder, frame: inout FrameUniforms, index: Int, rect: CGRect,
                                    paper: PaperStyle, isPDF: Bool, input: RenderInput) {
        enc.setDepthStencilState(depthOff)
        let origin = SIMD2<Float>(Float(rect.minX), Float(rect.minY))
        let size = SIMD2<Float>(Float(rect.width), Float(rect.height))
        let fullUV = SIMD4<Float>(0, 0, 1, 1)
        let sr: Float = 12

        var shadow = QuadUniforms(rect: SIMD4<Float>(origin.x - sr, origin.y - sr, size.x + sr * 2, size.y + sr * 2 + 2),
                                  uvRect: fullUV, pageOrigin: origin, pageSize: size, style: 0, shadowRadius: sr)
        enc.setRenderPipelineState(pageShadowPipeline)
        enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setVertexBytes(&shadow, length: MemoryLayout<QuadUniforms>.stride, index: 1)
        enc.setFragmentBytes(&shadow, length: MemoryLayout<QuadUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        var quad = QuadUniforms(rect: SIMD4<Float>(origin.x, origin.y, size.x, size.y), uvRect: fullUV,
                                pageOrigin: origin, pageSize: size, style: isPDF ? 0 : paper.shaderIndex, shadowRadius: 0)
        if isPDF, let cache = pdfTextures, let base = cache.baseTexture(page: index, desiredScale: input.fitPixelScale) {
            enc.setRenderPipelineState(texturePipeline)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            enc.setVertexBytes(&quad, length: MemoryLayout<QuadUniforms>.stride, index: 1)
            enc.setFragmentTexture(base.texture, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            if let detail = cache.detailTexture(page: index), detail.scale > base.scale * 1.05 {
                let r = detail.rect
                var dq = QuadUniforms(rect: SIMD4<Float>(origin.x + Float(r.minX), origin.y + Float(r.minY), Float(r.width), Float(r.height)),
                                      uvRect: fullUV, pageOrigin: origin, pageSize: size, style: 0, shadowRadius: 0)
                enc.setVertexBytes(&dq, length: MemoryLayout<QuadUniforms>.stride, index: 1)
                enc.setFragmentTexture(detail.texture, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        } else if !isPDF, paper.usesTexture, let templates = templateTextures,
                  let tex = templates.texture(style: paper, size: rect.size, desiredScale: CGFloat(frame.scale)) {
            enc.setRenderPipelineState(texturePipeline)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            enc.setVertexBytes(&quad, length: MemoryLayout<QuadUniforms>.stride, index: 1)
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else {
            enc.setRenderPipelineState(paperPipeline)
            enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            enc.setVertexBytes(&quad, length: MemoryLayout<QuadUniforms>.stride, index: 1)
            enc.setFragmentBytes(&quad, length: MemoryLayout<QuadUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    private func scissorRect(for rect: CGRect, frame: FrameUniforms, width: Int, height: Int) -> MTLScissorRect? {
        let s = CGFloat(frame.scale)
        let ox = CGFloat(frame.viewOffset.x)
        let oy = CGFloat(frame.viewOffset.y)
        let fx0 = (rect.minX * s + ox).rounded(.down)
        let fy0 = (rect.minY * s + oy).rounded(.down)
        let fx1 = (rect.maxX * s + ox).rounded(.up)
        let fy1 = (rect.maxY * s + oy).rounded(.up)
        guard fx0.isFinite, fy0.isFinite, fx1.isFinite, fy1.isFinite else { return nil }
        let x0 = Int(max(0, min(CGFloat(width), fx0)))
        let y0 = Int(max(0, min(CGFloat(height), fy0)))
        let x1 = Int(max(0, min(CGFloat(width), fx1)))
        let y1 = Int(max(0, min(CGFloat(height), fy1)))
        guard x1 > x0, y1 > y0 else { return nil }
        return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // MARK: - Strokes

    /// Which strokes a call draws: everything (the direct path), or the part under the ink layer
    /// (highlighters, the live stroke's highlighter and shadow) or the part in and over it (shadows,
    /// inks and grass; the live ink).
    private enum StrokePart {
        case all
        case underInk
        case ink
    }

    private func drawStrokes(_ enc: MTLRenderCommandEncoder, frame: inout FrameUniforms, gpu: PageGPU,
                             rect: CGRect, active: ActiveStroke?, part: StrokePart = .all, committed: Bool = true) {
        // Depth slots: highlighters [0, H), active highlighter H, shadows H+1 (shared, the slots up to
        // H+I stay free), active shadow H+I+1, inks [H+I+2, H+2I+1], active ink H+2I+2.
        let h = gpu.highlighterStrokes
        let i = gpu.inkStrokes
        let total = h + 2 * i + 3
        let step = 0.9 / Float(total + 1)
        let origin = SIMD2<Float>(Float(rect.minX), Float(rect.minY))
        enc.setDepthStencilState(depthWrite)

        if committed, let vertices = gpu.vertices, let indices = gpu.indices, let strokes = gpu.strokes {
            enc.setVertexBuffer(vertices, offset: 0, index: 2)
            enc.setVertexBuffer(strokes, offset: 0, index: 3)
            enc.setFragmentBuffer(strokes, offset: 0, index: 3)
            if gpu.highlighterIndexCount > 0, part != .ink {
                var su = SegUniforms(pageOrigin: origin, pointOffset: 0, orderOffset: 0, depthStep: step)
                drawRibbon(enc, pipeline: highlighterPipeline, frame: &frame, seg: &su,
                           indices: indices, first: 0, count: gpu.highlighterIndexCount)
            }
            if gpu.inkIndexCount > 0, part != .underInk {
                var su = SegUniforms(pageOrigin: origin, pointOffset: 0, orderOffset: UInt32(h + 1), depthStep: step)
                if gpu.has3D {
                    drawOnce(enc, pipeline: shadowPipeline, frame: &frame, seg: &su,
                             indices: indices, first: gpu.highlighterIndexCount, count: gpu.inkIndexCount)
                }
                su.orderOffset = UInt32(i + 2)
                for run in gpu.inkRuns {
                    if run.blendsOnce {
                        drawOnce(enc, pipeline: inkPipeline, frame: &frame, seg: &su,
                                 indices: indices, first: run.first, count: run.count)
                    } else {
                        drawRibbon(enc, pipeline: inkPipeline, frame: &frame, seg: &su,
                                   indices: indices, first: run.first, count: run.count)
                    }
                }
            }
            if part != .underInk, let blades = gpu.blades, gpu.bladeCount > 0 {
                var su = SegUniforms(pageOrigin: origin, pointOffset: 0, orderOffset: UInt32(i + 2), depthStep: step)
                drawDecor(enc, frame: &frame, seg: &su, blades: blades, bladeOffset: 0, bladeCount: gpu.bladeCount,
                          flowers: gpu.flowers, flowerOffset: 0, flowerCount: gpu.flowerCount)
            }
        }

        guard let a = active, !a.points.isEmpty, let mesh = activeMesh(a, time: frame.time) else { return }
        let buffer = mesh.buffer
        let firstIndex = mesh.first
        let count = mesh.count
        enc.setVertexBuffer(buffer, offset: Self.strokeSlot, index: 2)
        enc.setVertexBuffer(buffer, offset: 0, index: 3)
        enc.setFragmentBuffer(buffer, offset: 0, index: 3)
        var su = SegUniforms(pageOrigin: origin, pointOffset: 0, orderOffset: 0, depthStep: step)
        if a.brush.isHighlighter {
            guard part != .ink else { return }
            su.orderOffset = UInt32(h)
            drawRibbon(enc, pipeline: highlighterPipeline, frame: &frame, seg: &su, indices: buffer, first: firstIndex, count: count)
            return
        }
        if a.brush.castsShadow, part != .ink {
            su.orderOffset = UInt32(h + i + 1)
            drawOnce(enc, pipeline: shadowPipeline, frame: &frame, seg: &su, indices: buffer, first: firstIndex, count: count)
        }
        guard part != .underInk else { return }
        su.orderOffset = UInt32(h + 2 * i + 2)
        if a.brush.blendsOnce {
            drawOnce(enc, pipeline: inkPipeline, frame: &frame, seg: &su, indices: buffer, first: firstIndex, count: count)
        } else {
            drawRibbon(enc, pipeline: inkPipeline, frame: &frame, seg: &su, indices: buffer, first: firstIndex, count: count)
        }

        if a.brush.growsFlowers {
            drawActiveGrass(enc, frame: &frame, seg: &su, stroke: a)
        }
    }

    /// The live stroke's mesh in this frame's buffer, built once per frame (the layered path draws
    /// it in two parts).
    private func activeMesh(_ a: ActiveStroke, time: Float) -> (buffer: MTLBuffer, first: Int, count: Int)? {
        if let prepared = preparedActive, prepared.frame == renderCount { return (prepared.buffer, prepared.first, prepared.count) }
        var verts: [RibbonVertexGPU] = []
        var idx: [UInt32] = []
        RibbonBuilder.append(a.points, stroke: 0, relax: a.brush.relaxesCorners, vertices: &verts, indices: &idx)
        guard !verts.isEmpty, !idx.isEmpty else { return nil }
        var info = StrokeGPU(color: a.color.simd, brush: UInt32(a.brush.shading), birth: time, width: a.width, seed: a.seed)
        let vertexBytes = verts.count * MemoryLayout<RibbonVertexGPU>.stride
        let indexOffset = Self.strokeSlot + (vertexBytes + 255) / 256 * 256
        let indexBytes = idx.count * MemoryLayout<UInt32>.stride
        guard let buffer = activeBuffer(length: indexOffset + indexBytes) else { return nil }
        withUnsafeBytes(of: &info) { raw in
            buffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        verts.withUnsafeBytes { raw in
            buffer.contents().advanced(by: Self.strokeSlot).copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        idx.withUnsafeBytes { raw in
            buffer.contents().advanced(by: indexOffset).copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        let first = indexOffset / MemoryLayout<UInt32>.stride
        preparedActive = (renderCount, buffer, first, idx.count)
        return (buffer, first, idx.count)
    }

    /// Blades of the stroke being drawn sprout where the pencil passed; flowers stay buds until it lifts.
    private func drawActiveGrass(_ enc: MTLRenderCommandEncoder, frame: inout FrameUniforms,
                                 seg su: inout SegUniforms, stroke a: ActiveStroke) {
        let field = GrassGenerator.field(for: a.brush, points: a.points, width: a.width, color: a.color, seed: a.seed)
        guard !field.blades.isEmpty else { return }
        let start = Float(a.startTime - epoch)
        let elapsed = max(frame.time - start, 0)
        var blades: [BladeGPU] = []
        var flowers: [FlowerGPU] = []
        Self.appendGPU(field, stroke: 0, color: a.color, birthStart: start, duration: elapsed,
                       bloomBase: 1e9, blades: &blades, flowers: &flowers)
        let bladeBytes = blades.count * MemoryLayout<BladeGPU>.stride
        let flowerOffset = (bladeBytes + 255) / 256 * 256
        let flowerBytes = flowers.count * MemoryLayout<FlowerGPU>.stride
        guard let buffer = activeDecorBuffer(length: flowerOffset + max(flowerBytes, 64)) else { return }
        blades.withUnsafeBytes { raw in
            buffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        if !flowers.isEmpty {
            flowers.withUnsafeBytes { raw in
                buffer.contents().advanced(by: flowerOffset).copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        drawDecor(enc, frame: &frame, seg: &su, blades: buffer, bladeOffset: 0, bladeCount: blades.count,
                  flowers: flowers.isEmpty ? nil : buffer, flowerOffset: flowerOffset, flowerCount: flowers.count)
    }

    private func drawDecor(_ enc: MTLRenderCommandEncoder, frame: inout FrameUniforms, seg: inout SegUniforms,
                           blades: MTLBuffer, bladeOffset: Int, bladeCount: Int,
                           flowers: MTLBuffer?, flowerOffset: Int, flowerCount: Int) {
        guard bladeCount > 0 else { return }
        enc.setRenderPipelineState(bladePipeline)
        enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setVertexBytes(&seg, length: MemoryLayout<SegUniforms>.stride, index: 1)
        enc.setVertexBuffer(blades, offset: bladeOffset, index: 5)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.bladeVertices, instanceCount: bladeCount)
        guard let flowers, flowerCount > 0 else { return }
        enc.setRenderPipelineState(flowerPipeline)
        enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setVertexBytes(&seg, length: MemoryLayout<SegUniforms>.stride, index: 1)
        enc.setVertexBuffer(blades, offset: bladeOffset, index: 5)
        enc.setVertexBuffer(flowers, offset: flowerOffset, index: 6)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: flowerCount)
    }

    /// Converts a grass field to GPU records. Blades sprout in drawing order between `birthStart`
    /// and `birthStart + duration`; flowers open `delay` seconds after `bloomBase`.
    private static func appendGPU(_ field: GrassField, stroke: UInt32, color: InkColor, birthStart: Float, duration: Float,
                                  bloomBase: Float, blades: inout [BladeGPU], flowers: inout [FlowerGPU]) {
        let offset = blades.count
        let n = Float(max(field.blades.count, 1))
        for (k, b) in field.blades.enumerated() {
            blades.append(BladeGPU(base: b.base,
                                   height: b.height,
                                   width: b.width,
                                   lean: b.lean,
                                   phase: b.phase,
                                   birth: birthStart + b.arc * duration,
                                   depth: 1 - (Float(k) + 1) / (n + 1),
                                   color: SIMD4<Float>(b.color.x, b.color.y, b.color.z, color.a),
                                   stroke: stroke,
                                   kind: b.kind.rawValue,
                                   stiffness: b.stiffness))
        }
        for f in field.flowers {
            let stemArc = field.blades.indices.contains(f.stem) ? field.blades[f.stem].arc : 0
            flowers.append(FlowerGPU(stem: UInt32(offset + f.stem),
                                     radius: f.radius,
                                     bloom: bloomBase + f.delay + stemArc * 0.3,
                                     petals: f.petals,
                                     petal: SIMD4<Float>(f.petal.x, f.petal.y, f.petal.z, 1),
                                     core: SIMD4<Float>(f.core.x, f.core.y, f.core.z, 1),
                                     spin: f.spin,
                                     style: f.style))
        }
    }

    /// A depth-only pass, then color for the nearest fragment only: where a ribbon folds over itself
    /// (or shadows overlap), see-through parts are blended exactly once. Both passes run the same
    /// pipeline, so the depth they compute is identical.
    private func drawOnce(_ enc: MTLRenderCommandEncoder, pipeline: MTLRenderPipelineState,
                          frame: inout FrameUniforms, seg su: inout SegUniforms,
                          indices: MTLBuffer, first: Int, count: Int) {
        guard count > 0 else { return }
        su.depthOnly = 1
        drawRibbon(enc, pipeline: pipeline, frame: &frame, seg: &su, indices: indices, first: first, count: count)
        su.depthOnly = 0
        enc.setDepthStencilState(depthNearestOnly)
        drawRibbon(enc, pipeline: pipeline, frame: &frame, seg: &su, indices: indices, first: first, count: count)
        enc.setDepthStencilState(depthWrite)
    }

    /// Draws `count` indices of ribbon triangles starting at index `first`.
    private func drawRibbon(_ enc: MTLRenderCommandEncoder, pipeline: MTLRenderPipelineState,
                            frame: inout FrameUniforms, seg: inout SegUniforms,
                            indices: MTLBuffer, first: Int, count: Int) {
        guard count > 0 else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setVertexBytes(&seg, length: MemoryLayout<SegUniforms>.stride, index: 1)
        enc.setFragmentBytes(&seg, length: MemoryLayout<SegUniforms>.stride, index: 1)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32,
                                  indexBuffer: indices, indexBufferOffset: first * MemoryLayout<UInt32>.stride)
    }

    private func activeBuffer(length: Int) -> MTLBuffer? {
        let slot = frameIndex % activeBuffers.count
        if let b = activeBuffers[slot], b.length >= length { return b }
        var capacity = 64 * 1024
        while capacity < length { capacity *= 2 }
        let b = device.makeBuffer(length: capacity, options: .storageModeShared)
        activeBuffers[slot] = b
        return b
    }

    private func activeDecorBuffer(length: Int) -> MTLBuffer? {
        let slot = frameIndex % activeDecorBuffers.count
        if let b = activeDecorBuffers[slot], b.length >= length { return b }
        var capacity = 64 * 1024
        while capacity < length { capacity *= 2 }
        let b = device.makeBuffer(length: capacity, options: .storageModeShared)
        activeDecorBuffers[slot] = b
        return b
    }

    private func cached(index: Int, page: PageInk) -> PageGPU {
        let gpu: PageGPU
        if let existing = pageCache[index] {
            gpu = existing
        } else {
            gpu = PageGPU()
            pageCache[index] = gpu
        }
        if gpu.version != page.version {
            let strokes = page.strokes.map { (id: $0.id, highlighter: $0.brush.isHighlighter, grass: $0.brush.growsFlowers) }
            switch InkMeshPlan.plan(old: gpu.order, new: strokes) {
            case .same:
                gpu.version = page.version
            case let .append(from):
                // The new strokes are the last non-highlighters of the page (InkMeshPlan checked it).
                let added = Array(page.strokes.filter { !$0.brush.isHighlighter }.suffix(strokes.count - from))
                if !append(added, to: gpu, version: page.version) {
                    rebuild(gpu, from: page)
                }
                rebuiltThisFrame = true
            case .rebuild:
                rebuild(gpu, from: page)
                rebuiltThisFrame = true
            }
        }
        return gpu
    }

    /// Writes new strokes' meshes after the page's existing geometry (the GPU only ever reads the
    /// counted part, so frames still in flight are untouched). False when the buffers are full.
    private func append(_ added: [Stroke], to gpu: PageGPU, version: Int) -> Bool {
        guard !added.isEmpty, let vb = gpu.vertices, let ib = gpu.indices, let sb = gpu.strokes else { return false }
        var verts: [RibbonVertexGPU] = []
        var idxs: [UInt32] = []
        var infos: [StrokeGPU] = []
        var runs = gpu.inkRuns
        let firstInfo = gpu.highlighterStrokes + gpu.inkStrokes
        let firstIndex = gpu.highlighterIndexCount + gpu.inkIndexCount
        var meshes: [(Int, RibbonMesh)] = []
        for s in added {
            var v: [RibbonVertexGPU] = []
            var i: [UInt32] = []
            RibbonBuilder.append(s.points, stroke: 0, relax: s.brush.relaxesCorners, vertices: &v, indices: &i)
            let mesh = RibbonMesh(vertices: v, indices: i)
            meshes.append((s.id, mesh))
            let info = UInt32(firstInfo + infos.count)
            infos.append(StrokeGPU(color: s.color.simd, brush: UInt32(s.brush.shading),
                                   birth: Float(s.birth - epoch), width: s.width, seed: s.seed))
            let base = UInt32(gpu.vertexCount + verts.count)
            let start = firstIndex + idxs.count
            for var vertex in mesh.vertices {
                vertex.stroke = info
                verts.append(vertex)
            }
            for index in mesh.indices {
                idxs.append(index + base)
            }
            let count = mesh.indices.count
            if count > 0 {
                if !s.brush.blendsOnce, let last = runs.last, !last.blendsOnce, last.first + last.count == start {
                    runs[runs.count - 1].count += count
                } else {
                    runs.append(InkRun(first: start, count: count, blendsOnce: s.brush.blendsOnce))
                }
            }
        }
        let vStride = MemoryLayout<RibbonVertexGPU>.stride
        let iStride = MemoryLayout<UInt32>.stride
        let sStride = MemoryLayout<StrokeGPU>.stride
        guard vb.length >= (gpu.vertexCount + verts.count) * vStride,
              ib.length >= (firstIndex + idxs.count) * iStride,
              sb.length >= (firstInfo + infos.count) * sStride else { return false }
        verts.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                vb.contents().advanced(by: gpu.vertexCount * vStride).copyMemory(from: base, byteCount: raw.count)
            }
        }
        idxs.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                ib.contents().advanced(by: firstIndex * iStride).copyMemory(from: base, byteCount: raw.count)
            }
        }
        infos.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                sb.contents().advanced(by: firstInfo * sStride).copyMemory(from: base, byteCount: raw.count)
            }
        }
        for (id, mesh) in meshes {
            gpu.ribbons[id] = mesh
            gpu.order.append(id)
        }
        for s in added {
            if s.brush.castsShadow { gpu.has3D = true }
            if s.brush.isAnimated { gpu.hasAnimated = true }
            if s.brush.isFastAnimated { gpu.hasWave = true }
            if s.brush == .lava { gpu.latestLavaBirth = max(gpu.latestLavaBirth, Self.lavaCoolEnd(s)) }
            if s.brush == .wet { gpu.latestWetBirth = max(gpu.latestWetBirth, s.birth) }
        }
        gpu.vertexCount += verts.count
        gpu.inkIndexCount += idxs.count
        gpu.inkStrokes += infos.count
        gpu.inkRuns = runs
        gpu.version = version
        return true
    }

    /// When the last point of a lava stroke starts cooling.
    private static func lavaCoolEnd(_ s: Stroke) -> Double {
        var length: Float = 0
        for i in s.points.indices.dropFirst() {
            let step = s.points[i].position - s.points[i - 1].position
            length += (step * step).sum().squareRoot()
        }
        return s.birth + Double(length) / lavaCoolSpeed
    }

    /// A shared buffer with half as much room again, so the next strokes can be appended in place.
    private func roomyBuffer<T>(_ items: [T]) -> MTLBuffer? {
        guard !items.isEmpty else { return nil }
        return items.withUnsafeBytes { raw -> MTLBuffer? in
            guard let base = raw.baseAddress,
                  let buffer = device.makeBuffer(length: raw.count + raw.count / 2 + 4096, options: .storageModeShared) else { return nil }
            buffer.contents().copyMemory(from: base, byteCount: raw.count)
            return buffer
        }
    }

    private func rebuild(_ gpu: PageGPU, from page: PageInk) {
        var verts: [RibbonVertexGPU] = []
        var idxs: [UInt32] = []
        var infos: [StrokeGPU] = []
        let pointTotal = page.strokes.reduce(0) { $0 + $1.points.count }
        verts.reserveCapacity(pointTotal * 6 + page.strokes.count * 24)
        idxs.reserveCapacity(pointTotal * 24 + page.strokes.count * 60)
        var hasWave = false
        var hasAnimated = false
        var has3D = false
        var latestWet = -Double.infinity
        var latestGrass = -Double.infinity
        var latestLava = -Double.infinity
        var bladeRecords: [BladeGPU] = []
        var flowerRecords: [FlowerGPU] = []
        let previous = gpu.ribbons
        var ribbons: [Int: RibbonMesh] = [:]
        ribbons.reserveCapacity(page.strokes.count)

        func append(_ s: Stroke) -> UInt32 {
            let idx = UInt32(infos.count)
            infos.append(StrokeGPU(color: s.color.simd, brush: UInt32(s.brush.shading),
                                   birth: Float(s.birth - epoch), width: s.width, seed: s.seed))
            let mesh: RibbonMesh
            if let known = previous[s.id] {
                mesh = known
            } else {
                var v: [RibbonVertexGPU] = []
                var i: [UInt32] = []
                RibbonBuilder.append(s.points, stroke: 0, relax: s.brush.relaxesCorners, vertices: &v, indices: &i)
                mesh = RibbonMesh(vertices: v, indices: i)
            }
            ribbons[s.id] = mesh
            let base = UInt32(verts.count)
            for var v in mesh.vertices {
                v.stroke = idx
                verts.append(v)
            }
            for i in mesh.indices {
                idxs.append(i + base)
            }
            return idx
        }

        for s in page.strokes where s.brush.isHighlighter {
            _ = append(s)
        }
        let hlIndices = idxs.count
        let hlStrokes = infos.count
        var usedGrass = Set<Int>()
        var runs: [InkRun] = []
        for s in page.strokes where !s.brush.isHighlighter {
            let start = idxs.count
            let idx = append(s)
            let count = idxs.count - start
            if count > 0 {
                // Consecutive ordinary strokes share one draw; see-through ones get their own.
                if !s.brush.blendsOnce, let last = runs.last, !last.blendsOnce, last.first + last.count == start {
                    runs[runs.count - 1].count += count
                } else {
                    runs.append(InkRun(first: start, count: count, blendsOnce: s.brush.blendsOnce))
                }
            }
            if s.brush.castsShadow { has3D = true }
            if s.brush.isAnimated { hasAnimated = true }
            if s.brush.isFastAnimated { hasWave = true }
            switch s.brush {
            case .lava:
                latestLava = max(latestLava, Self.lavaCoolEnd(s))
            case .wet:
                latestWet = max(latestWet, s.birth)
            case .grass, .bloom:
                latestGrass = max(latestGrass, s.birth)
                usedGrass.insert(s.id)
                let field: GrassField
                if let cached = grassCache[s.id] {
                    field = cached
                } else {
                    field = GrassGenerator.field(for: s.brush, points: s.points, width: s.width, color: s.color, seed: s.seed)
                    grassCache[s.id] = field
                }
                let end = Float(s.birth - epoch)
                let duration = Float(max(0, min(s.duration, 60)))
                Self.appendGPU(field, stroke: idx, color: s.color, birthStart: end - duration, duration: duration,
                               bloomBase: end, blades: &bladeRecords, flowers: &flowerRecords)
            default:
                break
            }
        }
        if grassCache.count > 600 {
            grassCache = grassCache.filter { usedGrass.contains($0.key) }
        }

        gpu.vertices = roomyBuffer(verts)
        gpu.indices = roomyBuffer(idxs)
        gpu.strokes = roomyBuffer(infos)
        gpu.vertexCount = verts.count
        gpu.order = page.strokes.filter(\.brush.isHighlighter).map(\.id) + page.strokes.filter { !$0.brush.isHighlighter }.map(\.id)
        gpu.blades = bladeRecords.isEmpty ? nil : bladeRecords.withUnsafeBytes { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }
        gpu.flowers = flowerRecords.isEmpty ? nil : flowerRecords.withUnsafeBytes { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }
        gpu.highlighterIndexCount = hlIndices
        gpu.inkIndexCount = idxs.count - hlIndices
        gpu.inkRuns = runs
        gpu.highlighterStrokes = hlStrokes
        gpu.inkStrokes = infos.count - hlStrokes
        gpu.bladeCount = bladeRecords.count
        gpu.flowerCount = flowerRecords.count
        gpu.hasWave = hasWave
        gpu.hasAnimated = hasAnimated
        gpu.has3D = has3D
        gpu.latestWetBirth = latestWet
        gpu.latestGrassBirth = latestGrass
        gpu.latestLavaBirth = latestLava
        gpu.ribbons = ribbons
        gpu.version = page.version
    }

    private func trimCache(visible: [Int]) {
        guard pageCache.count > 24, let first = visible.first, let last = visible.last else { return }
        let keep = (first - 6)...(last + 6)
        for key in pageCache.keys where !keep.contains(key) {
            pageCache.removeValue(forKey: key)
        }
    }

    private func ensureDepth(width: Int, height: Int) {
        if let t = depthTexture, t.width == width, t.height == height { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]
        #if targetEnvironment(simulator)
        d.storageMode = .private
        #else
        d.storageMode = .memoryless
        #endif
        depthTexture = device.makeTexture(descriptor: d)
    }
}

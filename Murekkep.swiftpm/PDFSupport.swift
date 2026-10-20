import CoreGraphics
import Foundation
import Metal

/// Page geometry helpers shared by the GPU rasterizer, thumbnails and PDF export.
enum PDFGeometry {
    static func rotation(of page: CGPDFPage) -> Int {
        ((Int(page.rotationAngle) % 360) + 360) % 360
    }

    /// Size of the page as it is displayed (rotation applied), in points.
    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let rot = rotation(of: page)
        if rot == 90 || rot == 270 {
            return CGSize(width: box.height, height: box.width)
        }
        return box.size
    }

    /// Call while the current user space is page-local display space (origin top-left, y down).
    /// Afterwards the user space is the PDF's own space, ready for `drawPDFPage`.
    static func concatPageTransform(_ ctx: CGContext, page: CGPDFPage) {
        let box = page.getBoxRect(.cropBox)
        let cw = box.width
        let ch = box.height
        let t: CGAffineTransform
        switch rotation(of: page) {
        case 90:
            t = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 180:
            t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: cw, ty: 0)
        case 270:
            t = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: ch, ty: cw)
        default:
            t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: ch)
        }
        ctx.concatenate(t)
        ctx.translateBy(x: -box.minX, y: -box.minY)
    }

    /// Draws a page into a y-down context whose user space is page-local points.
    static func draw(page: CGPDFPage, in ctx: CGContext) {
        ctx.saveGState()
        let size = displaySize(of: page)
        ctx.clip(to: CGRect(origin: .zero, size: size))
        concatPageTransform(ctx, page: page)
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }

    /// Renders `region` (page-local points) at `scale` pixels per point into a BGRA bitmap.
    static func renderBitmap(page: CGPDFPage, region: CGRect, scale: CGFloat) -> CGContext? {
        let w = max(1, Int((region.width * scale).rounded(.up)))
        let h = max(1, Int((region.height * scale).rounded(.up)))
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: CGFloat(w) / region.width, y: CGFloat(h) / region.height)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        draw(page: page, in: ctx)
        return ctx
    }

    static func openDocument(at url: URL) -> CGPDFDocument? {
        guard let doc = CGPDFDocument(url as CFURL) else { return nil }
        if !doc.isUnlocked {
            _ = doc.unlockWithPassword("")
        }
        return doc.isUnlocked ? doc : nil
    }
}

/// Rasterizes PDF pages into Metal textures on a background queue.
/// Base textures cover a whole page at "fit width" resolution, detail textures cover
/// the visible part of a page at the current zoom once scrolling settles.
final class PDFTextureCache {
    struct BaseTexture {
        let texture: MTLTexture
        let scale: CGFloat
    }

    struct DetailTexture {
        let texture: MTLTexture
        let rect: CGRect
        let scale: CGFloat
    }

    static let maxDimension: CGFloat = 4096
    static let maxBaseTextures = 6

    var onUpdate: (() -> Void)?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let url: URL
    private let rasterQueue = DispatchQueue(label: "murekkep.pdf.raster", qos: .userInitiated)
    private var rasterDocument: CGPDFDocument? // raster queue only

    // Main thread state
    private var base: [Int: BaseTexture] = [:]
    private var detail: [Int: DetailTexture] = [:]
    private var pendingBase: Set<Int> = []
    private var lastUse: [Int: Int] = [:]
    private var clock = 0
    private var detailGeneration = 0

    // Shared with the raster queue
    private let lock = NSLock()
    private var wanted: Set<Int> = []
    private var latestDetailGeneration = 0

    init(device: MTLDevice, commandQueue: MTLCommandQueue, url: URL) {
        self.device = device
        self.commandQueue = commandQueue
        self.url = url
    }

    func setVisible(_ pages: [Int]) {
        var set = Set<Int>()
        for p in pages {
            set.insert(p)
            set.insert(p - 1)
            set.insert(p + 1)
        }
        lock.lock()
        wanted = set
        lock.unlock()
    }

    private func isWanted(_ page: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return wanted.contains(page)
    }

    private func isCurrentDetail(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == latestDetailGeneration
    }

    func baseTexture(page: Int, desiredScale: CGFloat) -> BaseTexture? {
        clock += 1
        lastUse[page] = clock
        let current = base[page]
        let needsBetter = current.map { $0.scale < desiredScale * 0.8 } ?? true
        if needsBetter && !pendingBase.contains(page) {
            requestBase(page: page, scale: desiredScale)
        }
        return current
    }

    func detailTexture(page: Int) -> DetailTexture? {
        detail[page]
    }

    var hasDetail: Bool { !detail.isEmpty }

    private func requestBase(page: Int, scale: CGFloat) {
        pendingBase.insert(page)
        rasterQueue.async { [weak self] in
            guard let self else { return }
            let result: (MTLTexture, CGFloat)?
            if self.isWanted(page) {
                result = autoreleasepool { self.makeTexture(page: page, region: nil, scale: scale, mipmapped: true) }
            } else {
                result = nil
            }
            DispatchQueue.main.async {
                self.pendingBase.remove(page)
                guard let made = result else { return }
                self.base[page] = BaseTexture(texture: made.0, scale: made.1)
                self.evictIfNeeded()
                self.onUpdate?()
            }
        }
    }

    func requestDetail(_ items: [(page: Int, rect: CGRect)], scale: CGFloat) {
        detailGeneration += 1
        let generation = detailGeneration
        lock.lock()
        latestDetailGeneration = generation
        lock.unlock()
        for item in items {
            rasterQueue.async { [weak self] in
                guard let self, self.isCurrentDetail(generation) else { return }
                let result = autoreleasepool {
                    self.makeTexture(page: item.page, region: item.rect, scale: scale, mipmapped: false)
                }
                DispatchQueue.main.async {
                    guard generation == self.detailGeneration, let made = result else { return }
                    self.detail[item.page] = DetailTexture(texture: made.0, rect: item.rect, scale: made.1)
                    self.onUpdate?()
                }
            }
        }
    }

    func clearDetail() {
        guard !detail.isEmpty else { return }
        detailGeneration += 1
        lock.lock()
        latestDetailGeneration = detailGeneration
        lock.unlock()
        detail.removeAll()
    }

    func purge(keeping visible: [Int]) {
        let keep = Set(visible)
        base = base.filter { keep.contains($0.key) }
        detail.removeAll()
        detailGeneration += 1
        lock.lock()
        latestDetailGeneration = detailGeneration
        lock.unlock()
    }

    private func evictIfNeeded() {
        guard base.count > Self.maxBaseTextures else { return }
        lock.lock()
        let keep = wanted
        lock.unlock()
        let candidates = base.keys.filter { !keep.contains($0) }.sorted { (lastUse[$0] ?? 0) < (lastUse[$1] ?? 0) }
        var excess = base.count - Self.maxBaseTextures
        for page in candidates where excess > 0 {
            base.removeValue(forKey: page)
            excess -= 1
        }
    }

    /// Raster queue only.
    private func makeTexture(page index: Int, region: CGRect?, scale: CGFloat, mipmapped: Bool) -> (MTLTexture, CGFloat)? {
        if rasterDocument == nil {
            rasterDocument = PDFGeometry.openDocument(at: url)
        }
        guard let doc = rasterDocument, let page = doc.page(at: index + 1) else { return nil }
        let size = PDFGeometry.displaySize(of: page)
        let rect = (region ?? CGRect(origin: .zero, size: size)).intersection(CGRect(origin: .zero, size: size))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return nil }
        var s = max(scale, 0.05)
        let longest = max(rect.width, rect.height)
        if longest * s > Self.maxDimension {
            s = Self.maxDimension / longest
        }
        guard let ctx = PDFGeometry.renderBitmap(page: page, region: rect, scale: s), let bytes = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: ctx.width,
                                                            height: ctx.height, mipmapped: mipmapped)
        desc.usage = mipmapped ? [.shaderRead, .renderTarget] : [.shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, ctx.width, ctx.height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: ctx.bytesPerRow)
        if mipmapped, texture.mipmapLevelCount > 1,
           let cb = commandQueue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        return (texture, s)
    }
}

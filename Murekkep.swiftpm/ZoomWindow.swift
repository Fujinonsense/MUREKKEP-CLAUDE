import MetalKit
import UIKit

/// What the zoom panel draws: the canvas's own pages and live stroke, seen through the box.
struct ZoomFrame {
    var pages: [PageInk]
    var layout: DocumentLayout
    var paper: PaperStyle
    var isPDF: Bool
    var active: ActiveStroke?
    /// The box in document points.
    var box: CGRect
    var dryDuration: Double
    var coolDuration: Double
    var animate: Bool
    var background: MTLClearColor
}

/// The zoom window (like Notability's): a panel along the bottom of the canvas that shows the box on
/// the page magnified. The pencil writes large in the panel and the canvas lays the stroke down at page
/// size inside the box (the canvas owns the stroke; the panel only maps its touches). Writing past the
/// dashed line moves the box on along the line; the buttons move it back, to a new line or on.
final class ZoomPanelView: UIView {
    let inkView: MTKView
    let gesture = InkGestureRecognizer()
    var source: (() -> ZoomFrame?)?
    var onBack: (() -> Void)?
    var onNewLine: (() -> Void)?
    var onForward: (() -> Void)?
    var onClose: (() -> Void)?

    /// Writing that reaches this share of the panel's width moves the box on.
    static let advanceShare: CGFloat = 0.8

    private let renderer: InkRenderer?
    private let proxy = RenderLoopProxy()
    private let advanceLine = CAShapeLayer()
    private let buttons = UIStackView()
    private static let buttonColumn: CGFloat = 52

    init(device: MTLDevice?, pdfURL: URL?, isPDF: Bool) {
        inkView = MTKView(frame: .zero, device: device)
        var made: InkRenderer?
        if let device {
            made = try? InkRenderer(device: device)
        }
        renderer = made
        super.init(frame: .zero)

        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 4)

        inkView.colorPixelFormat = InkRenderer.colorFormat
        inkView.depthStencilPixelFormat = .invalid
        inkView.framebufferOnly = true
        inkView.autoResizeDrawable = true
        inkView.enableSetNeedsDisplay = true
        inkView.isPaused = true
        inkView.accessibilityIgnoresInvertColors = true
        inkView.layer.cornerRadius = 14
        inkView.layer.cornerCurve = .continuous
        inkView.layer.masksToBounds = true
        inkView.delegate = proxy
        inkView.addGestureRecognizer(gesture)
        addSubview(inkView)
        proxy.onDraw = { [weak self] _ in self?.draw() }
        proxy.onResize = { [weak self] in self?.requestRender() }

        if let renderer, isPDF, let url = pdfURL {
            let cache = PDFTextureCache(device: renderer.device, commandQueue: renderer.commandQueue, url: url)
            cache.onUpdate = { [weak self] in self?.requestRender() }
            renderer.pdfTextures = cache
        }
        if let renderer, !isPDF {
            let templates = TemplateTextureCache(device: renderer.device, commandQueue: renderer.commandQueue)
            templates.onUpdate = { [weak self] in self?.requestRender() }
            renderer.templateTextures = templates
        }
        renderer?.onStickerUpdate = { [weak self] in self?.requestRender() }

        advanceLine.strokeColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        advanceLine.lineWidth = 1.5
        advanceLine.lineDashPattern = [6, 5]
        advanceLine.fillColor = nil
        inkView.layer.addSublayer(advanceLine)

        buttons.axis = .vertical
        buttons.distribution = .equalSpacing
        buttons.alignment = .center
        for (symbol, label, action) in [
            ("chevron.left", Loc.t("Kutuyu geri al"), #selector(back)),
            ("arrow.turn.down.left", Loc.t("Alt satıra geç"), #selector(newLine)),
            ("chevron.right", Loc.t("Kutuyu ilerlet"), #selector(forward)),
            ("xmark", Loc.t("Yakın yazmayı kapat"), #selector(close)),
        ] {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
            b.accessibilityLabel = label
            b.addTarget(self, action: action, for: .touchUpInside)
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            b.heightAnchor.constraint(equalToConstant: 40).isActive = true
            buttons.addArrangedSubview(b)
        }
        addSubview(buttons)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        inkView.frame = CGRect(x: 6, y: 6, width: max(bounds.width - Self.buttonColumn - 6, 1), height: max(bounds.height - 12, 1))
        buttons.frame = CGRect(x: bounds.width - Self.buttonColumn, y: 10, width: Self.buttonColumn - 4, height: bounds.height - 20)
        let x = (inkView.bounds.width * Self.advanceShare).rounded()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: 8))
        path.addLine(to: CGPoint(x: x, y: inkView.bounds.height - 8))
        advanceLine.path = path.cgPath
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 18).cgPath
    }

    /// Width over height of the writing area (the box takes the same shape).
    var aspect: CGFloat { inkView.bounds.width / max(inkView.bounds.height, 1) }

    /// Panel points per page point when showing `box`.
    func scale(for box: CGRect) -> CGFloat { inkView.bounds.width / max(box.width, 1) }

    func requestRender() {
        guard !isHidden else { return }
        inkView.setNeedsDisplay()
    }

    private func draw() {
        guard let renderer, let frame = source?(), inkView.bounds.width > 1, inkView.bounds.height > 1 else { return }
        guard renderer.reserveFrame() else {
            DispatchQueue.main.async { [weak self] in self?.requestRender() }
            return
        }
        guard let descriptor = inkView.currentRenderPassDescriptor, let drawable = inkView.currentDrawable else {
            renderer.cancelReservation()
            return
        }
        let s = scale(for: frame.box)
        let pixels = inkView.drawableSize.width / max(inkView.bounds.width, 1)
        let input = RenderInput(docOriginInView: CGPoint(x: -frame.box.minX * s, y: -frame.box.minY * s),
                                zoom: s,
                                viewSize: inkView.bounds.size,
                                fitPixelScale: min(s * pixels, 3),
                                dryDuration: frame.dryDuration,
                                coolDuration: frame.coolDuration,
                                animateWaves: frame.animate,
                                background: frame.background)
        let result = renderer.render(descriptor: descriptor, drawable: drawable, input: input, layout: frame.layout,
                                     pages: frame.pages, paper: frame.paper, isPDF: frame.isPDF, active: frame.active)
        if result.animationFPS > 0 {
            // Moving ink (water, lava, a drying stroke) keeps the panel alive like the canvas.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / Double(result.animationFPS)) { [weak self] in
                self?.requestRender()
            }
        }
    }

    @objc private func back() { onBack?() }
    @objc private func newLine() { onNewLine?() }
    @objc private func forward() { onForward?() }
    @objc private func close() { onClose?() }
}

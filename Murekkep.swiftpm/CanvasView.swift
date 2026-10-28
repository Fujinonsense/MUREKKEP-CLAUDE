import MetalKit
import UIKit

/// Forwards MTKView callbacks; keeps the MetalKit delegate protocol away from UIKit views.
final class RenderLoopProxy: NSObject, MTKViewDelegate {
    var onDraw: ((MTKView) -> Void)?
    var onResize: (() -> Void)?

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        onResize?()
    }

    func draw(in view: MTKView) {
        onDraw?(view)
    }
}

/// The note canvas: a Metal view that draws pages and ink, driven by an invisible scroll view.
/// Everything that belongs to the page sits in `rotationHost`, which turns as a whole when the
/// user tilts the page to write at a comfortable angle.
final class CanvasView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    let model: EditorModel

    private let rotationHost = UIView()
    private let metalView: MTKView
    private let renderer: InkRenderer?
    private let proxy = RenderLoopProxy()
    private let scrollView = PageScrollView()
    private let zoomContainer = UIView()
    private let inkGesture = InkGestureRecognizer()
    private let overlay = CanvasOverlayView(frame: .zero)
    private let eraserRing = UIView()
    private let messageLabel = UILabel()
    /// Hover preview: tool cursor and a soft "tool shadow" like Apple Pencil Pro apps show.
    private let cursorView = UIView()
    private let hoverCursor = CAShapeLayer()
    private let toolShadow = CAShapeLayer()

    private let pageRotation = UIRotationGestureRecognizer()
    private let instrumentPan = UIPanGestureRecognizer()
    private let instrumentTurn = UIRotationGestureRecognizer()

    private var builder: StrokeBuilder?
    private var activeStroke: ActiveStroke?
    private var strokeStart: Double = 0
    private var eraserPage: Int?
    private var lastEraserPoint: CGPoint?
    private var didInitialLayout = false
    /// One page at a time (see `applyPageMode`), and the page on screen when a drag began.
    private var singlePage = false
    private var dragStartPage = 0
    private var lastViewWidth: CGFloat = 0
    private var lastCanvasSize: CGSize = .zero
    private var lastReportedPage = -1
    private var pencilOnly = true
    private var inputConfigured = false
    private var holdWork: DispatchWorkItem?
    private var holdAnchor: CGPoint?
    private var detailWork: DispatchWorkItem?
    private var lastPencilTap: CFTimeInterval = 0
    private var lastHover: CGPoint?
    /// UICanvasFeedbackGenerator on iPadOS 17.5+ (plays on Apple Pencil Pro).
    private var canvasFeedback: AnyObject?
    /// Only used before iPadOS 17.5.
    private lazy var fallbackFeedback = UISelectionFeedbackGenerator()
    /// The window scene that drives saving and the render loop. With several windows of the app open,
    /// each canvas follows its own window instead of the whole app.
    private weak var observedScene: UIWindowScene?
    /// Frame rate the visible ink asked for in the last frame (0 = nothing moves).
    private var requestedFPS = 0

    // Page rotation
    private var pageAngle: CGFloat = 0
    private var lastLayoutAngle: CGFloat = 0
    private var rotationLocked = true
    private var rotationStartAngle: CGFloat = 0
    private var lastRotationSnap: Int?
    private var lastViewportChange: CFTimeInterval = 0

    /// The tool the current touch started with. A squeeze in the middle of a stroke changes
    /// `model.tool`, but the stroke under the pencil still finishes as it began.
    private var gestureTool: ToolKind = .brush(.pen)
    /// A held drawing recognized as a heart or face; its suggestions open when the pencil lifts.
    private var pendingSketch: PendingSketch?
    /// Name of the shape the held stroke snapped to (for the live size/turn label).
    private var snappedTitle: String?

    // Drafting tools
    private var snap: EdgeSnap?
    private var snapStart: CGPoint?
    private var instrumentStart: Instrument?
    private var lastInstrumentSnap: Int?
    private var shapeStart: (page: Int, point: CGPoint)?
    private var lassoPage: Int?
    private var lassoPoints: [CGPoint] = []
    /// Length of the lasso loop on screen so far, and when the pencil last ticked along it.
    private var lassoTravel: CGFloat = 0
    private var lastLassoTick: CFTimeInterval = 0
    /// The Aa tool's box on the page, where it was opened, and the font size it was last set to.
    private var textBox: UITextView?
    private var textBoxRequest: TextRequest?
    private var textBoxFontSize: CGFloat = 0
    private enum SelectionDrag {
        case move(start: CGPoint)
        case scale(anchor: CGPoint, startDistance: CGFloat)
        case rotate(center: CGPoint, startAngle: CGFloat)
    }
    private var selectionDrag: SelectionDrag?
    /// Index of the shape handle under the pencil (see `EditorModel.shapeEdit`).
    private var shapeHandleDrag: Int?
    /// From the touch to the dragged handle (page space), so a shape grabbed anywhere moves with
    /// the touch instead of jumping its handle under it.
    private var shapeHandleOffset = CGPoint.zero
    private var lastShapeSnapped = false
    private var lassoZoom: CGFloat = 1
    private var compassDraft: (page: Int, center: CGPoint)?
    private var compassArc: (page: Int, last: CGFloat, points: [CGPoint])?
    private var tapStart: (page: Int, point: CGPoint, view: CGPoint)?

    // Apple Pencil Pro squeeze-and-hold eraser
    private var squeezeHeld = false
    private var erasedDuringSqueeze = false
    /// When the squeeze being held started, and whether it put the eraser in the hand.
    private var squeezeStart: CFTimeInterval = 0
    private var squeezeTookEraser = false
    /// When the last squeeze was let go (a late duplicate of its end must not switch again).
    private var lastSqueezeEnd: CFTimeInterval = 0
    private let pencilGestures = UIPencilInteraction()

    // Zoom window (see ZoomPanelView)
    private var zoomPanel: ZoomPanelView?
    /// Room the pen bar takes along the bottom or the right side (applyPaletteClearance).
    private var paletteClearance = UIEdgeInsets.zero
    private var zoomBox: ZoomBox?
    /// The touch being handled came from the zoom panel: its points map through the box.
    private var zoomInput = false
    /// What the overlay last painted (see `CanvasOverlayView.signature`).
    private var lastOverlaySignature: Int?

    init(model: EditorModel) {
        self.model = model
        let device = MTLCreateSystemDefaultDevice()
        metalView = MTKView(frame: .zero, device: device)
        var made: InkRenderer?
        if let device {
            do {
                made = try InkRenderer(device: device)
            } catch {
                print("Mürekkep renderer error: \(error)")
            }
        }
        renderer = made
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setUp() {
        backgroundColor = .systemGray6
        clipsToBounds = true
        addSubview(rotationHost)

        metalView.colorPixelFormat = InkRenderer.colorFormat
        // The renderer attaches its own depth buffer, so the view does not allocate a second one.
        metalView.depthStencilPixelFormat = .invalid
        metalView.framebufferOnly = true
        metalView.autoResizeDrawable = true
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.isUserInteractionEnabled = false
        // Smart Invert would turn the paper black and the ink into its complementary colors.
        metalView.accessibilityIgnoresInvertColors = true
        metalView.delegate = proxy
        rotationHost.addSubview(metalView)

        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = false
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        // With free margins on every side, keep a vertical scroll from drifting sideways.
        scrollView.isDirectionalLockEnabled = true
        scrollView.isInking = { [weak self] in self?.inkGesture.isTracking == true }
        scrollView.startsOnInstrument = { [weak self] g in self?.gestureStartsOnInstrument(g) == true }
        zoomContainer.backgroundColor = .clear
        zoomContainer.isUserInteractionEnabled = false
        scrollView.addSubview(zoomContainer)
        rotationHost.addSubview(scrollView)
        rotationHost.addSubview(overlay)

        inkGesture.delegate = self
        inkGesture.onBegan = { [weak self] touch, event in self?.touchBegan(touch, event) }
        inkGesture.onMoved = { [weak self] touch, event in self?.touchMoved(touch, event) }
        inkGesture.onEnded = { [weak self] touch, event in self?.touchEnded(touch, event) }
        inkGesture.onCancelled = { [weak self] in self?.touchCancelled() }
        inkGesture.onEstimatesUpdated = { [weak self] touches in self?.estimatesUpdated(touches) }
        scrollView.addGestureRecognizer(inkGesture)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
        hover.delegate = self
        addGestureRecognizer(hover)

        // Two fingers tap to undo, three to redo. A pinch also starts with two fingers down, so the
        // taps wait until zooming and scrolling have failed; otherwise a short pinch undid the last
        // stroke or brought an erased one back.
        let undoTap = UITapGestureRecognizer(target: self, action: #selector(twoFingerTap))
        undoTap.numberOfTouchesRequired = 2
        undoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        undoTap.delegate = self
        scrollView.addGestureRecognizer(undoTap)
        let redoTap = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap))
        redoTap.numberOfTouchesRequired = 3
        redoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        redoTap.delegate = self
        scrollView.addGestureRecognizer(redoTap)
        // One finger tapping the page puts away a shape's handles or a sticker's box (in pencil-only
        // mode such a finger never reaches the ink gesture).
        let finishTap = UITapGestureRecognizer(target: self, action: #selector(fingerTapped(_:)))
        finishTap.numberOfTouchesRequired = 1
        finishTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        finishTap.cancelsTouchesInView = false
        finishTap.delegate = self
        scrollView.addGestureRecognizer(finishTap)
        for tap in [undoTap, redoTap, finishTap] {
            if let pinch = scrollView.pinchGestureRecognizer {
                tap.require(toFail: pinch)
            }
            tap.require(toFail: scrollView.panGestureRecognizer)
        }

        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pageRotation.addTarget(self, action: #selector(pageRotated(_:)))
        pageRotation.allowedTouchTypes = fingers
        pageRotation.delegate = self
        pageRotation.isEnabled = false
        addGestureRecognizer(pageRotation)

        instrumentPan.addTarget(self, action: #selector(instrumentPanned(_:)))
        instrumentPan.allowedTouchTypes = fingers
        instrumentPan.maximumNumberOfTouches = 2
        instrumentPan.delegate = self
        rotationHost.addGestureRecognizer(instrumentPan)
        instrumentTurn.addTarget(self, action: #selector(instrumentTurned(_:)))
        instrumentTurn.allowedTouchTypes = fingers
        instrumentTurn.delegate = self
        rotationHost.addGestureRecognizer(instrumentTurn)

        pencilGestures.delegate = self
        addInteraction(pencilGestures)

        eraserRing.isUserInteractionEnabled = false
        eraserRing.isHidden = true
        eraserRing.layer.borderWidth = 1.5
        eraserRing.layer.borderColor = UIColor.systemGray.cgColor
        eraserRing.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        rotationHost.addSubview(eraserRing)

        cursorView.isUserInteractionEnabled = false
        cursorView.backgroundColor = .clear
        toolShadow.fillColor = UIColor.black.withAlphaComponent(0.10).cgColor
        toolShadow.shadowColor = UIColor.black.cgColor
        // The shadow follows its path (set with it on every hover), so Core Animation no longer renders
        // the layer off screen to find its shape; 0.035 is the old 0.35 times the fill's 0.10 alpha.
        toolShadow.shadowOpacity = 0.035
        toolShadow.shadowRadius = 6
        toolShadow.shadowOffset = .zero
        hoverCursor.lineWidth = 1.2
        cursorView.layer.addSublayer(toolShadow)
        cursorView.layer.addSublayer(hoverCursor)
        rotationHost.addSubview(cursorView)

        if #available(iOS 17.5, *) {
            canvasFeedback = UICanvasFeedbackGenerator(view: self)
        }
        model.onHaptic = { [weak self] kind in self?.playHaptic(kind, at: nil) }

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.isHidden = true
        addSubview(messageLabel)

        proxy.onDraw = { [weak self] _ in self?.drawFrame() }
        proxy.onResize = { [weak self] in self?.setNeedsRender() }

        if let renderer, model.isPDF, let url = model.pdfURL {
            let cache = PDFTextureCache(device: renderer.device, commandQueue: renderer.commandQueue, url: url)
            cache.onUpdate = { [weak self] in self?.setNeedsRender() }
            renderer.pdfTextures = cache
        }
        if let renderer, !model.isPDF {
            let templates = TemplateTextureCache(device: renderer.device, commandQueue: renderer.commandQueue)
            templates.onUpdate = { [weak self] in self?.setNeedsRender() }
            renderer.templateTextures = templates
        }
        if renderer == nil {
            messageLabel.text = Loc.t("Bu cihazda Metal başlatılamadı.")
            messageLabel.isHidden = false
        }

        model.onInkChange = { [weak self] in self?.setNeedsRender() }
        renderer?.onStickerUpdate = { [weak self] in self?.setNeedsRender() }
        model.onLayoutChange = { [weak self] in self?.documentSizeChanged() }
        model.onScrollRequest = { [weak self] page in self?.scrollToPage(page, animated: true) }
        singlePage = model.singlePage
        scrollView.decelerationRate = singlePage ? .fast : .normal

        // Window lifecycle is observed per scene in `didMoveToWindow`; these concern the whole device.
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        nc.addObserver(self, selector: #selector(memoryWarning), name: BrainRuntime.needsMemory, object: nil)
        nc.addObserver(self, selector: #selector(powerConditionsChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        nc.addObserver(self, selector: #selector(powerConditionsChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CanvasView, _: UITraitCollection) in
            view.updateClearColor()
            view.setNeedsRender()
        }

        applyInputSettings(pencilOnly: model.settings.pencilOnly)
        applyRotation(degrees: model.settings.pageAngle, locked: model.settings.pageAngleLocked)
        updateClearColor()
    }

    /// Pencil-only: one finger scrolls, the pencil draws (a finger still drags the handles of a
    /// recognized shape and the box of a sticker being placed, see `fingerTakesEditHandle`).
    /// Otherwise fingers draw and two fingers scroll.
    func applyInputSettings(pencilOnly requested: Bool) {
        let effective = requested && UIDevice.current.userInterfaceIdiom == .pad
        guard !inputConfigured || effective != pencilOnly else { return }
        inputConfigured = true
        pencilOnly = effective
        let pencilType = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let fingerType = NSNumber(value: UITouch.TouchType.direct.rawValue)
        if effective {
            inkGesture.allowedTouchTypes = [pencilType, fingerType]
            scrollView.panGestureRecognizer.allowedTouchTypes = [fingerType]
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        } else {
            inkGesture.allowedTouchTypes = [pencilType, fingerType]
            scrollView.panGestureRecognizer.allowedTouchTypes = [fingerType]
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        }
    }

    private var renderSettings: (animations: Bool, batterySaver: Bool)?

    /// Redraws once when animation settings change so the loop can start or stop.
    func applyRenderSettings(animations: Bool, batterySaver: Bool) {
        if let current = renderSettings, current.animations == animations, current.batterySaver == batterySaver {
            return
        }
        renderSettings = (animations, batterySaver)
        refreshLoop()
        setNeedsRender()
    }

    /// Turns the page to `degrees` (the whole canvas rotates, writing stays aligned with the page).
    /// While unlocked, two fingers can turn it too.
    func applyRotation(degrees: Double, locked: Bool) {
        rotationLocked = locked
        pageRotation.isEnabled = !locked
        let radians = CGFloat(degrees) * .pi / 180
        guard abs(radians - pageAngle) > 0.0001 else { return }
        pageAngle = radians
        setNeedsLayout()
    }

    // MARK: - Window and scene

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observeScene(window?.windowScene)
        if window == nil {
            stopLoop()
            // Leaving the note with the text box open keeps what was typed.
            if textBox != nil {
                finishTextBox()
                model.saveNow()
            }
        } else {
            // Back on screen (after a sheet, another window, the app switcher): double tap and
            // squeeze must reach this page again.
            if !interactions.contains(where: { $0 === pencilGestures }) {
                addInteraction(pencilGestures)
            }
            pencilGestures.isEnabled = true
            updateDrawableScale()
            setNeedsRender()
            // A keyboard case types on the page from the start.
            becomeFirstResponder()
        }
    }

    /// Renders at the screen's full native resolution (2 or 3 pixels per point), never at 1×, so
    /// ink, paper and PDFs stay razor sharp.
    private func updateDrawableScale() {
        let scale = window?.windowScene?.screen.nativeScale ?? traitCollection.displayScale
        guard scale > 0 else { return }
        if metalView.contentScaleFactor != scale {
            metalView.contentScaleFactor = scale
            setNeedsRender()
        }
        if overlay.contentScaleFactor != scale {
            overlay.contentScaleFactor = scale
        }
    }

    private func observeScene(_ scene: UIWindowScene?) {
        guard scene !== observedScene else { return }
        let nc = NotificationCenter.default
        if let old = observedScene {
            nc.removeObserver(self, name: UIScene.willDeactivateNotification, object: old)
            nc.removeObserver(self, name: UIScene.didEnterBackgroundNotification, object: old)
            nc.removeObserver(self, name: UIScene.willEnterForegroundNotification, object: old)
        }
        observedScene = scene
        guard let scene else { return }
        nc.addObserver(self, selector: #selector(sceneWillDeactivate), name: UIScene.willDeactivateNotification, object: scene)
        nc.addObserver(self, selector: #selector(sceneDidEnterBackground), name: UIScene.didEnterBackgroundNotification, object: scene)
        nc.addObserver(self, selector: #selector(sceneWillEnterForeground), name: UIScene.willEnterForegroundNotification, object: scene)
    }

    /// False while this window is in the background or the canvas is not on screen.
    private var isOnScreen: Bool {
        guard let scene = window?.windowScene else { return false }
        return scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
    }

    // MARK: - Layout and zoom

    /// Size of the rotated canvas (it covers the whole view at any angle).
    private var canvasSize: CGSize { rotationHost.bounds.size }

    private var fitZoom: CGFloat {
        canvasSize.width / max(model.layout.contentSize.width, 1)
    }

    /// Render-space position of document point (0, 0) and view points per document point.
    private var docTransform: (origin: CGPoint, zoom: CGFloat) {
        let origin = zoomContainer.convert(CGPoint.zero, to: rotationHost)
        let probe = zoomContainer.convert(CGPoint(x: 100, y: 0), to: rotationHost)
        return (origin, max(hypot(probe.x - origin.x, probe.y - origin.y) / 100, 0.0001))
    }

    /// The part of the document this view shows, in document points.
    private func visibleDocRect(origin: CGPoint, zoom: CGFloat) -> CGRect {
        CGRect(x: -origin.x / zoom, y: -origin.y / zoom, width: canvasSize.width / zoom, height: canvasSize.height / zoom)
    }

    private var pixelsPerPoint: CGFloat {
        metalView.drawableSize.width / max(metalView.bounds.width, 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableScale()
        messageLabel.frame = bounds.insetBy(dx: 40, dy: 40)
        let w = bounds.width
        let h = bounds.height
        guard w > 1, h > 1 else { return }
        let c = abs(cos(pageAngle))
        let s = abs(sin(pageAngle))
        let size = CGSize(width: (w * c + h * s).rounded(.up), height: (w * s + h * c).rounded(.up))
        let centerDoc = didInitialLayout ? zoomContainer.convert(CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                                                                  from: rotationHost) : nil
        rotationHost.bounds = CGRect(origin: .zero, size: size)
        rotationHost.center = CGPoint(x: bounds.midX, y: bounds.midY)
        rotationHost.transform = CGAffineTransform(rotationAngle: pageAngle)
        let inner = rotationHost.bounds
        metalView.frame = inner
        scrollView.frame = inner
        overlay.frame = inner
        cursorView.frame = inner
        if !didInitialLayout {
            didInitialLayout = true
            configureDocumentSize()
            fit(initial: true)
            // Back where the note was left; in single-page mode, that whole page.
            let resume = model.resumePage
            if singlePage {
                fitWholePage(resume)
            } else if resume > 0 {
                scrollToPage(resume)
            }
        } else if abs(w - lastViewWidth) > 0.5 {
            fit(initial: false)
        } else if abs(pageAngle - lastLayoutAngle) > 0.0001, let centerDoc {
            // Only the angle changed: keep the zoom and the point in the middle of the screen.
            scrollView.minimumZoomScale = fitZoom * 0.5
            scrollView.maximumZoomScale = fitZoom * 8
            centerContent()
            let zoom = scrollView.zoomScale
            var offset = CGPoint(x: centerDoc.x * zoom - size.width / 2, y: centerDoc.y * zoom - size.height / 2)
            clamp(&offset)
            scrollView.contentOffset = offset
        }
        lastViewWidth = w
        lastCanvasSize = size
        lastLayoutAngle = pageAngle
        centerContent()
        layoutZoomPanel()
        setNeedsRender()
    }

    private func configureDocumentSize() {
        let size = model.layout.contentSize
        let zoom = scrollView.zoomScale
        let offset = scrollView.contentOffset
        let minZoom = scrollView.minimumZoomScale
        let maxZoom = scrollView.maximumZoomScale
        scrollView.minimumZoomScale = min(minZoom, 1)
        scrollView.maximumZoomScale = max(maxZoom, 1)
        scrollView.zoomScale = 1
        zoomContainer.transform = .identity
        zoomContainer.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        scrollView.zoomScale = zoom
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.contentOffset = offset
    }

    /// Pixels per page point for whole-page PDF textures (capped to keep memory low; zoom uses detail tiles).
    private var basePixelScale: CGFloat {
        min(fitZoom * pixelsPerPoint, 3.0)
    }

    private func fit(initial: Bool) {
        let docWidth = max(model.layout.contentSize.width, 1)
        let width = canvasSize.width
        let fit = width / docWidth
        let oldFit = lastCanvasSize.width > 0 ? lastCanvasSize.width / docWidth : fit
        let relative = initial ? 1 : scrollView.zoomScale / max(oldFit, 0.0001)
        let anchor = initial ? CGPoint.zero : zoomContainer.convert(CGPoint(x: width / 2, y: 0), from: rotationHost)
        scrollView.minimumZoomScale = fit * 0.5
        scrollView.maximumZoomScale = fit * 8
        let zoom = min(max(fit * relative, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        scrollView.zoomScale = zoom
        centerContent()
        var offset: CGPoint
        if initial {
            // The page at the top, centered; the free margins stay off screen until pulled in.
            let m = workMargins
            offset = CGPoint(x: -(scrollView.contentInset.left - m.side), y: -(scrollView.contentInset.top - m.top))
        } else {
            offset = CGPoint(x: anchor.x * zoom - width / 2, y: anchor.y * zoom)
        }
        clamp(&offset)
        scrollView.contentOffset = offset
    }

    private func clamp(_ offset: inout CGPoint) {
        let inset = scrollView.contentInset
        let size = scrollView.contentSize
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, size.width - scrollView.bounds.width + inset.right)
        let maxY = max(minY, size.height - scrollView.bounds.height + inset.bottom)
        offset.x = min(max(offset.x, minX), maxX)
        offset.y = min(max(offset.y, minY), maxY)
    }

    /// Free working room around the pages: any corner (also the top right, under the toolbar) can be
    /// pulled to the middle of the screen at any zoom or page angle.
    private var workMargins: (side: CGFloat, top: CGFloat) {
        (max(scrollView.bounds.width * 0.35, 220), max(scrollView.bounds.height * 0.35, 240))
    }

    /// Centers pages narrower than the view and adds the free margins on every side.
    private func centerContent() {
        let size = scrollView.contentSize
        let x = max(0, (scrollView.bounds.width - size.width) / 2)
        let y = max(0, (scrollView.bounds.height - size.height) / 2)
        let m = workMargins
        let inset = UIEdgeInsets(top: y + m.top, left: x + m.side, bottom: y + m.side, right: x + m.side)
        if scrollView.contentInset != inset {
            scrollView.contentInset = inset
        }
    }

    private func documentSizeChanged() {
        configureDocumentSize()
        scrollView.minimumZoomScale = fitZoom * 0.5
        scrollView.maximumZoomScale = fitZoom * 8
        centerContent()
        setNeedsRender()
    }

    /// Scrolls so that `page` is at the top (in the middle in single-page mode). Only a nearby page
    /// slides into view; a far one is jumped to, so the pages in between are not all drawn.
    func scrollToPage(_ page: Int, animated: Bool = false) {
        guard model.layout.pageRects.indices.contains(page) else { return }
        let rect = model.layout.pageRects[page]
        var offset: CGPoint
        if singlePage {
            offset = singlePageOffset(page)
        } else {
            offset = CGPoint(x: scrollView.contentOffset.x, y: (rect.minY - DocumentLayout.gap / 2) * scrollView.zoomScale)
            clamp(&offset)
        }
        scrollView.setContentOffset(offset, animated: animated && abs(page - model.currentPage) <= 2)
        setNeedsRender()
    }

    // MARK: - Single page

    /// A drag faster than this (points per millisecond) goes on to the next page.
    private static let pageFlick: CGFloat = 0.3

    /// One page at a time (see `EditorModel.singlePage`).
    func applyPageMode(single: Bool) {
        guard single != singlePage else { return }
        singlePage = single
        scrollView.decelerationRate = single ? .fast : .normal
        guard didInitialLayout else { return }
        let page = model.currentPage
        if single {
            fitWholePage(page)
        } else {
            scrollView.zoomScale = fitZoom
            centerContent()
            scrollToPage(page)
        }
    }

    /// Zooms so the whole page fits on screen (never past the page width) and shows it.
    private func fitWholePage(_ page: Int) {
        guard model.layout.pageRects.indices.contains(page) else { return }
        let rect = model.layout.pageRects[page]
        let zoom = min(fitZoom, canvasSize.height / (rect.height + DocumentLayout.gap))
        scrollView.zoomScale = min(max(zoom, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        centerContent()
        scrollView.setContentOffset(singlePageOffset(page), animated: false)
        setNeedsRender()
    }

    /// Content offset that shows `page` in the middle of the screen.
    private func singlePageOffset(_ page: Int) -> CGPoint {
        let rect = model.layout.pageRects[page]
        var offset = CGPoint(x: scrollView.contentOffset.x, y: rect.midY * scrollView.zoomScale - scrollView.bounds.height / 2)
        clamp(&offset)
        return offset
    }

    /// The page a drag settles on in single-page mode: a flick goes one page on or back, a slow
    /// drag settles on the page nearest the middle of the screen. Nil while the page is zoomed
    /// larger than the screen (it scrolls freely then).
    private func singlePageTarget(velocity: CGFloat) -> Int? {
        let rects = model.layout.pageRects
        guard !rects.isEmpty else { return nil }
        let zoom = scrollView.zoomScale
        let start = min(max(dragStartPage, 0), rects.count - 1)
        guard rects[start].height * zoom <= scrollView.bounds.height + 1 else { return nil }
        if velocity > Self.pageFlick { return min(start + 1, rects.count - 1) }
        if velocity < -Self.pageFlick { return max(start - 1, 0) }
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / zoom
        return rects.indices.min { abs(rects[$0].midY - centerY) < abs(rects[$1].midY - centerY) }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dragStartPage = model.currentPage
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard singlePage, let page = singlePageTarget(velocity: velocity.y) else { return }
        targetContentOffset.pointee = singlePageOffset(page)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomContainer
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isTracking || scrollView.isDecelerating || scrollView.isZooming {
            lastViewportChange = CACurrentMediaTime()
        }
        setNeedsRender()
        scheduleDetail()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        lastViewportChange = CACurrentMediaTime()
        centerContent()
        setNeedsRender()
        scheduleDetail()
    }

    // MARK: - Rendering

    func setNeedsRender() {
        if metalView.isPaused {
            metalView.setNeedsDisplay()
        }
        zoomPanel?.requestRender()
    }

    private func updateClearColor() {
        let dark = traitCollection.userInterfaceStyle == .dark
        metalView.clearColor = dark ? MTLClearColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                                    : MTLClearColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)
    }

    private func drawFrame() {
        guard let renderer, canvasSize.width > 1, canvasSize.height > 1 else { return }
        // GPU still busy: skip this frame and try again on the next screen refresh rather than
        // making the scroll view wait.
        guard renderer.reserveFrame() else {
            if metalView.isPaused {
                DispatchQueue.main.async { [weak self] in self?.setNeedsRender() }
            }
            return
        }
        guard let descriptor = metalView.currentRenderPassDescriptor, let drawable = metalView.currentDrawable else {
            renderer.cancelReservation()
            return
        }
        let (origin, zoom) = docTransform
        let input = RenderInput(docOriginInView: origin,
                                zoom: zoom,
                                viewSize: metalView.bounds.size,
                                fitPixelScale: basePixelScale,
                                dryDuration: model.settings.dryDuration,
                                coolDuration: model.settings.lavaCoolDuration,
                                animateWaves: model.settings.animations,
                                background: metalView.clearColor)
        let result = renderer.render(descriptor: descriptor, drawable: drawable, input: input,
                                     layout: model.layout, pages: model.renderPages, paper: model.meta.paper,
                                     isPDF: model.isPDF, active: activeStroke)
        requestedFPS = result.animationFPS
        refreshLoop()
        reportCurrentPage(origin: origin, zoom: zoom)
        updateOverlay(origin: origin, zoom: zoom)
        zoomPanel?.requestRender()
    }

    /// Runs the display loop while ink on screen moves (sea, lava, grass, drying ink); otherwise the
    /// view redraws only when something changes. While the pencil writes on an animated page, the
    /// loop runs at the display's full rate (120 Hz on ProMotion) so the line keeps up with the tip.
    /// Low Power Mode, the battery saver setting and a hot device cap the rate.
    private func refreshLoop() {
        guard requestedFPS > 0, isOnScreen else {
            stopLoop()
            return
        }
        let maxFPS = max(window?.windowScene?.screen.maximumFramesPerSecond ?? 60, 30)
        let info = ProcessInfo.processInfo
        let hot = info.thermalState == .serious || info.thermalState == .critical
        let saver = model.settings.batterySaver || info.isLowPowerModeEnabled || hot
        let inking = activeStroke != nil || eraserPage != nil
        var fps = inking ? maxFPS : requestedFPS
        if saver {
            fps = min(fps, inking ? 60 : 30)
        }
        fps = min(fps, maxFPS)
        if metalView.isPaused || metalView.preferredFramesPerSecond != fps {
            metalView.preferredFramesPerSecond = fps
            metalView.enableSetNeedsDisplay = false
            metalView.isPaused = false
        }
    }

    private func stopLoop() {
        guard !metalView.isPaused else { return }
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
    }

    private func reportCurrentPage(origin: CGPoint, zoom: CGFloat) {
        let visible = visibleDocRect(origin: origin, zoom: zoom)
        let page = model.layout.dominantPage(in: visible)
        if model.layout.pageRects.indices.contains(page) {
            let rect = model.layout.pageRects[page]
            let mid = CGPoint(x: min(max(visible.midX, rect.minX + 40), rect.maxX - 40),
                              y: min(max(visible.midY, rect.minY + 60), rect.maxY - 60))
            model.viewCenter = (page: page, point: CGPoint(x: mid.x - rect.minX, y: mid.y - rect.minY))
        }
        guard page != lastReportedPage else { return }
        lastReportedPage = page
        // Published after the frame, never while SwiftUI is updating views.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.currentPage != self.lastReportedPage else { return }
            self.model.currentPage = self.lastReportedPage
        }
    }

    // MARK: - Overlay

    private func pageOrigin(_ page: Int) -> CGPoint {
        model.layout.pageRects.indices.contains(page) ? model.layout.pageRects[page].origin : .zero
    }

    /// Instruments, previews and the selection frame follow scrolling and zooming.
    private func updateOverlay(origin: CGPoint, zoom: CGFloat) {
        overlay.origin = origin
        overlay.zoom = zoom
        layoutTextBox()
        overlay.instrument = model.instrument
        if let sel = model.displayedSelection, model.tool == .lasso || model.placingSticker != nil {
            overlay.selection = sel.bounds.offsetBy(dx: pageOrigin(sel.page).x, dy: pageOrigin(sel.page).y)
        } else {
            overlay.selection = nil
        }
        if let edit = model.shapeEdit {
            let o = pageOrigin(edit.page)
            overlay.shapeHandles = edit.shape.handles.map { CGPoint(x: $0.x + o.x, y: $0.y + o.y) }
        } else {
            overlay.shapeHandles = []
        }
        overlay.zoomBox = zoomBox.map { $0.rect.offsetBy(dx: pageOrigin($0.page).x, dy: pageOrigin($0.page).y) }
        if let c = model.compass, model.tool == .compass {
            let o = pageOrigin(c.page)
            overlay.compass = (center: CGPoint(x: c.center.x + o.x, y: c.center.y + o.y), radius: c.radius)
        } else if compassDraft == nil {
            overlay.compass = nil
        }
        overlayChanged()
    }

    /// Redraws the overlay only while it shows something; an empty overlay is hidden so scrolling
    /// does not repaint a full-screen layer every frame.
    private func overlayChanged() {
        let empty = overlay.isEmpty
        overlay.isHidden = empty
        guard !empty else {
            lastOverlaySignature = nil
            return
        }
        let signature = overlay.signature
        if signature != lastOverlaySignature {
            lastOverlaySignature = signature
            overlay.setNeedsDisplay()
        }
    }

    private func refreshOverlay() {
        let (origin, zoom) = docTransform
        updateOverlay(origin: origin, zoom: zoom)
    }

    // MARK: - PDF detail textures

    /// Asks for sharp tiles of the visible PDF area once scrolling or zooming pauses.
    private func scheduleDetail() {
        guard model.isPDF else { return }
        detailWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.requestDetail() }
        detailWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func requestDetail() {
        guard let cache = renderer?.pdfTextures, canvasSize.width > 1 else { return }
        let (origin, zoom) = docTransform
        let scale = zoom * pixelsPerPoint
        guard scale > basePixelScale * 1.15 else {
            cache.clearDetail()
            setNeedsRender()
            return
        }
        let visible = visibleDocRect(origin: origin, zoom: zoom)
        var items: [(page: Int, rect: CGRect)] = []
        for index in model.layout.pages(intersecting: visible) {
            let pageRect = model.layout.pageRects[index]
            var local = visible.intersection(pageRect).offsetBy(dx: -pageRect.minX, dy: -pageRect.minY)
            local = local.insetBy(dx: -local.width * 0.15, dy: -local.height * 0.15)
                .intersection(CGRect(origin: .zero, size: pageRect.size))
            if !local.isNull, local.width > 1, local.height > 1 {
                items.append((page: index, rect: local))
            }
        }
        cache.requestDetail(items, scale: scale)
    }

    // MARK: - Drawing input

    private func samples(_ touch: UITouch, _ event: UIEvent?, origin: CGPoint) -> [InputSample] {
        let touches = event?.coalescedTouches(for: touch) ?? [touch]
        return touches.map { sample($0, origin: origin) }
    }

    private func predicted(_ touch: UITouch, _ event: UIEvent?, origin: CGPoint) -> [InputSample] {
        (event?.predictedTouches(for: touch) ?? []).map { sample($0, origin: origin) }
    }

    private func sample(_ t: UITouch, origin: CGPoint) -> InputSample {
        var p = docLocation(t)
        if let snap { p = snap.project(p) }
        let force: CGFloat = (t.type == .pencil || t.maximumPossibleForce > 0) ? t.force : 0
        var s = InputSample(location: CGPoint(x: p.x - origin.x, y: p.y - origin.y), force: force, timestamp: t.timestamp)
        if t.type == .pencil {
            s.isPencil = true
            s.altitude = t.altitudeAngle
            let azimuthView: UIView? = zoomInput ? zoomPanel?.inkView : zoomContainer
            s.azimuth = t.azimuthAngle(in: azimuthView)
            if #available(iOS 17.5, *) {
                s.roll = t.rollAngle
                if abs(s.roll) > 0.02 && !model.pencilProDetected {
                    model.pencilProDetected = true
                }
            }
            if t.estimatedPropertiesExpectingUpdates.contains(.force), let index = t.estimationUpdateIndex {
                s.estimationIndex = index.intValue
            }
        }
        return s
    }

    private func touchBegan(_ touch: UITouch, _ event: UIEvent) {
        // Stop any pan a resting palm may have started.
        if touch.type == .pencil {
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.panGestureRecognizer.isEnabled = true
        }
        hideCursor()
        if model.palette != nil {
            model.palette = nil
        }
        if model.suggestion != nil {
            model.suggestion = nil
        }
        pendingSketch = nil
        // Writing or drawing with another tool sets the open text box on the page first.
        if textBox != nil && model.tool != .text {
            finishTextBox()
        }
        // The page takes the keyboard back (from the assistant's field, say) once it is touched.
        if textBox == nil, !isFirstResponder {
            becomeFirstResponder()
        }
        let docPoint = docLocation(touch)
        let zoom = docTransform.zoom
        // A finger on the ruler moves the ruler; it never draws.
        if touch.type == .direct, model.instrument?.contains(docPoint) == true {
            inkGesture.abandon()
            return
        }
        let finger = touch.type == .direct
        // A recognized shape shows handles on its corners: a handle is dragged, any other touch
        // puts them away (and then does what the tool does).
        if let edit = model.shapeEdit {
            if let index = shapeHandle(at: docPoint, in: edit, zoom: zoom, reach: finger ? Self.fingerReach : 16) {
                shapeHandleDrag = index
                let o = pageOrigin(edit.page)
                let handle = edit.shape.handles[index]
                shapeHandleOffset = CGPoint(x: handle.x + o.x - docPoint.x, y: handle.y + o.y - docPoint.y)
                lastShapeSnapped = false
                model.beginShapeHandleDrag()
                return
            }
            model.finishShapeEdit()
        }
        // A sticker being placed: its box moves, resizes and turns it; a touch anywhere else
        // settles it on the page.
        if model.placingSticker != nil {
            if beginPlacementDrag(docPoint, zoom: zoom, reach: finger ? Self.fingerReach : 24) {
                gestureTool = .lasso
                return
            }
            model.finishPlacing()
        }
        // Pencil only: past the handles and the box a finger never draws.
        if pencilOnly && finger {
            inkGesture.abandon()
            return
        }
        gestureTool = model.tool
        switch gestureTool {
        case .eraser:
            guard let page = model.layout.page(containing: docPoint, tolerance: 24) else {
                inkGesture.abandon()
                return
            }
            if squeezeIsHeld { erasedDuringSqueeze = true }
            eraserPage = page
            lastEraserPoint = docPoint
            preparePaperSound(brush: nil)
            model.beginErase(page: page)
            erase(from: docPoint, to: docPoint)
            if !zoomInput { showEraserRing(at: touch.location(in: rotationHost)) }
        case .brush, .textPen:
            let brush = model.activeBrush
            guard let page = model.layout.page(containing: docPoint) else {
                inkGesture.abandon()
                return
            }
            if gestureTool == .textPen {
                model.textPenTouched()
            } else {
                snap = model.instrument.flatMap { EdgeSnap.find(for: $0, at: docPoint, tolerance: 18 / zoom) }
            }
            snapStart = snap.map { $0.project(docPoint) }
            let origin = model.layout.pageRects[page].origin
            let random = Float.random(in: 0..<1)
            let seed = brush == .grass ? GrassGenerator.seed(level: model.settings.flowerLevel, random: random) : random
            var b = StrokeBuilder(brush: brush, color: model.color(for: brush), width: model.width(for: brush), seed: seed)
            b.nibAngle = Float(model.settings.nibAngle * .pi / 180)
            b.useRoll = model.settings.rollRotatesNib
            for s in samples(touch, event, origin: origin) {
                b.add(s)
            }
            builder = b
            preparePaperSound(brush: brush)
            strokeStart = Date().timeIntervalSinceReferenceDate
            activeStroke = ActiveStroke(page: page, brush: brush, color: b.color, width: b.width, seed: b.seed,
                                        points: b.preview(predicted: predicted(touch, event, origin: origin)),
                                        startTime: strokeStart)
            holdAnchor = nil
            if snap == nil {
                trackHold(touch.location(in: self))
            }
            updateSnapLabel(docPoint)
        case .shape:
            guard let page = model.layout.page(containing: docPoint) else {
                inkGesture.abandon()
                return
            }
            let o = pageOrigin(page)
            shapeStart = (page: page, point: CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y))
            updateShapePreview(docPoint)
        case .compass:
            compassBegan(docPoint)
        case .lasso:
            lassoBegan(docPoint, zoom: zoom)
        case .text:
            guard let page = model.layout.page(containing: docPoint) else {
                inkGesture.abandon()
                return
            }
            let o = pageOrigin(page)
            tapStart = (page: page, point: CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y), view: touch.location(in: self))
        }
        refreshLoop()
        setNeedsRender()
    }

    private func touchMoved(_ touch: UITouch, _ event: UIEvent) {
        let docPoint = docLocation(touch)
        if let index = shapeHandleDrag {
            dragShapeHandle(index, to: docPoint)
            return
        }
        switch gestureTool {
        case .eraser:
            guard eraserPage != nil else { return }
            let coalesced = event.coalescedTouches(for: touch) ?? [touch]
            for t in coalesced {
                let p = docLocation(t)
                erase(from: lastEraserPoint ?? p, to: p)
                lastEraserPoint = p
            }
            if !zoomInput { showEraserRing(at: touch.location(in: rotationHost)) }
            paperSound(touch, event, brush: nil)
        case .brush, .textPen:
            guard var b = builder, var active = activeStroke else { return }
            let origin = model.layout.pageRects[active.page].origin
            for s in samples(touch, event, origin: origin) {
                b.add(s)
            }
            builder = b
            active.points = b.preview(predicted: predicted(touch, event, origin: origin))
            activeStroke = active
            paperSound(touch, event, brush: active.brush)
            // A snapped shape follows the pencil: show its size and turn.
            if let title = snappedTitle, let adjustment = b.shapeAdjustment, let tip = b.tip {
                let o = model.layout.pageRects[active.page].origin
                overlay.liveLabel = (point: CGPoint(x: CGFloat(tip.x) + o.x, y: CGFloat(tip.y) + o.y),
                                     text: "\(title) · %\(Int((adjustment.scale * 100).rounded())) · \(adjustment.degrees)°")
                overlayChanged()
            }
            if snap == nil {
                trackHold(touch.location(in: self))
            }
            if snap != nil {
                updateSnapLabel(docPoint)
            }
            setNeedsRender()
        case .shape:
            updateShapePreview(docPoint)
        case .compass:
            compassMoved(docPoint)
        case .lasso:
            lassoMoved(docPoint)
        case .text:
            break
        }
    }

    private func touchEnded(_ touch: UITouch, _ event: UIEvent) {
        cancelHold()
        stopPaperSound()
        if shapeHandleDrag != nil {
            shapeHandleDrag = nil
            model.endShapeHandleDrag()
            endGestureState()
            return
        }
        let docPoint = docLocation(touch)
        switch gestureTool {
        case .eraser:
            if eraserPage != nil { finishErasing() }
            return
        case .brush, .textPen:
            guard var b = builder, let active = activeStroke else { break }
            let origin = model.layout.pageRects[active.page].origin
            for s in samples(touch, event, origin: origin) {
                b.add(s)
            }
            let straight = b.isStraight
            let points = b.finish()
            builder = nil
            activeStroke = nil
            if !points.isEmpty {
                let now = Date().timeIntervalSinceReferenceDate
                let stroke = Stroke(brush: active.brush, color: active.color, width: active.width,
                                    birth: now, seed: active.seed, points: points,
                                    duration: max(0, now - active.startTime))
                model.addStroke(stroke, toPage: active.page)
                // A held text-pen stroke that became a shape or a picture stays a drawing.
                let isSymbol = b.editable != nil || pendingSketch != nil || snappedTitle != nil || straight
                if gestureTool == .textPen && !isSymbol {
                    model.queueTextStroke(stroke.id, page: active.page)
                } else if gestureTool == .textPen && b.editable == nil {
                    model.resumeTextBatch()
                } else if let shape = b.editable {
                    if gestureTool == .textPen { model.resumeTextBatch() }
                    // The shape keeps handles on its corners until the next touch elsewhere.
                    model.startShapeEdit(page: active.page, strokeID: stroke.id, shape: shape)
                }
                if straight || snap != nil {
                    playHaptic(.completed, at: touch.location(in: self))
                }
                if let sketch = pendingSketch {
                    let ids = sketch.others.union([stroke.id])
                    var box = CGRect.null
                    for s in model.strokes(on: active.page) where ids.contains(s.id) {
                        box = box.union(CGRect(ink: s.bounds))
                    }
                    if !box.isNull {
                        model.suggestion = SketchSuggestion(kind: sketch.kind, alternate: sketch.alternate, page: active.page, strokeIDs: ids,
                                                            bounds: box, location: touch.location(in: self))
                    }
                }
            }
            pendingSketch = nil
        case .shape:
            if let start = shapeStart {
                let o = pageOrigin(start.page)
                let end = snappedShapeEnd(CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y), from: start.point)
                model.addShape(page: start.page, from: start.point, to: end)
                playHaptic(.completed, at: touch.location(in: self))
            }
        case .compass:
            compassEnded(docPoint)
        case .lasso:
            lassoEnded()
        case .text:
            if let tap = tapStart {
                let v = touch.location(in: self)
                if hypot(v.x - tap.view.x, v.y - tap.view.y) < 12 {
                    // A tap outside the open box writes it; the next tap opens a new one.
                    if textBox != nil {
                        finishTextBox()
                    } else {
                        openTextBox(TextRequest(page: tap.page, point: tap.point))
                    }
                }
            }
        }
        endGestureState()
    }

    private func touchCancelled() {
        cancelHold()
        stopPaperSound()
        if shapeHandleDrag != nil {
            shapeHandleDrag = nil
            model.endShapeHandleDrag()
            endGestureState()
            return
        }
        if eraserPage != nil {
            // A second finger (a pinch) or a palm took over: what this touch erased comes back.
            cancelErasing()
            return
        }
        if case .lasso = gestureTool, selectionDrag != nil {
            model.endSelectionEdit()
        }
        builder = nil
        activeStroke = nil
        compassDraft = nil
        compassArc = nil
        lassoPage = nil
        lassoPoints = []
        endGestureState()
    }

    // MARK: - Paper sound

    /// Feeds every sample of the pencil (the coalesced ones too: the turns of letters are in them) to
    /// the pen sound (off when the setting is off).
    private func paperSound(_ touch: UITouch, _ event: UIEvent, brush: Brush?) {
        guard model.settings.paperSound else { return }
        let level = model.settings.paperSoundLevel
        for t in event.coalescedTouches(for: touch) ?? [touch] {
            let pressure: CGFloat = t.type == .pencil ? t.force : 1
            PaperSound.shared.write(point: t.location(in: self), time: t.timestamp, force: pressure, brush: brush, level: level)
        }
    }

    /// Pencil down: the pen's sound is readied before the line starts, so it is heard from its start.
    private func preparePaperSound(brush: Brush?) {
        guard model.settings.paperSound else { return }
        PaperSound.shared.prepare(brush: brush, level: model.settings.paperSoundLevel)
    }

    private func stopPaperSound() {
        PaperSound.shared.lift()
    }

    private func endGestureState() {
        snappedTitle = nil
        snap = nil
        snapStart = nil
        shapeStart = nil
        tapStart = nil
        selectionDrag = nil
        overlay.liveLabel = nil
        overlay.previewPaths = []
        overlay.lasso = []
        overlay.compassPen = nil
        refreshLoop()
        refreshOverlay()
        setNeedsRender()
    }

    /// Apple Pencil sends the real force a moment after the estimate; fold it into the stroke.
    private func estimatesUpdated(_ touches: Set<UITouch>) {
        guard var b = builder, var active = activeStroke else { return }
        var changed = false
        for t in touches where t.type == .pencil {
            guard let index = t.estimationUpdateIndex, !t.estimatedPropertiesExpectingUpdates.contains(.force) else { continue }
            b.refine(estimationIndex: index.intValue, force: t.force, altitude: t.altitudeAngle)
            changed = true
        }
        guard changed else { return }
        builder = b
        active.points = b.preview(predicted: [])
        activeStroke = active
        setNeedsRender()
    }

    // MARK: - Instruments: snapping and measuring

    /// Length along the ruler / set square, or the angle on the protractor, next to the pencil.
    private func updateSnapLabel(_ docPoint: CGPoint) {
        guard let snap, let start = snapStart, let instrument = model.instrument else {
            overlay.liveLabel = nil
            return
        }
        let p = snap.project(docPoint)
        if snap.isRay {
            let local = instrument.toLocal(p)
            var deg = atan2(-local.y, local.x) * 180 / .pi
            if deg < 0 { deg += 360 }
            overlay.liveLabel = (point: p, text: "\(Int(deg.rounded()))°")
        } else {
            let length = hypot(p.x - start.x, p.y - start.y)
            overlay.liveLabel = (point: p, text: ShapeBuilder.mm(length / pointsPerMillimetre))
        }
        overlayChanged()
    }

    private func gestureStartsOnInstrument(_ g: UIGestureRecognizer) -> Bool {
        guard let instrument = model.instrument else { return false }
        let n = g.numberOfTouches
        guard n > 0 else { return instrument.contains(g.location(in: zoomContainer)) }
        for i in 0..<n where instrument.contains(g.location(ofTouch: i, in: zoomContainer)) {
            return true
        }
        return false
    }

    @objc private func instrumentPanned(_ g: UIPanGestureRecognizer) {
        guard var instrument = model.instrument else { return }
        switch g.state {
        case .began:
            instrumentStart = instrument
        case .changed:
            guard let start = instrumentStart else { return }
            let t = g.translation(in: zoomContainer)
            instrument.center = CGPoint(x: start.center.x + t.x, y: start.center.y + t.y)
            model.instrument = instrument
            refreshOverlay()
        default:
            instrumentStart = nil
        }
    }

    @objc private func instrumentTurned(_ g: UIRotationGestureRecognizer) {
        guard var instrument = model.instrument else { return }
        switch g.state {
        case .began:
            instrumentStart = instrumentStart ?? instrument
            lastInstrumentSnap = nil
        case .changed:
            let base = instrumentStart?.angle ?? instrument.angle
            var angle = base + g.rotation
            let degrees = angle * 180 / .pi
            let nearest = (degrees / 15).rounded() * 15
            if abs(degrees - nearest) < 1.6 {
                angle = nearest * .pi / 180
                if lastInstrumentSnap != Int(nearest) {
                    lastInstrumentSnap = Int(nearest)
                    playHaptic(.alignment, at: nil)
                }
            } else {
                lastInstrumentSnap = nil
            }
            instrument.angle = angle
            model.instrument = instrument
            overlay.instrumentLabel = "\(instrument.degrees)°"
            refreshOverlay()
        default:
            overlay.instrumentLabel = nil
            instrumentStart = nil
            refreshOverlay()
        }
    }

    // MARK: - Page rotation

    @objc private func pageRotated(_ g: UIRotationGestureRecognizer) {
        switch g.state {
        case .began:
            rotationStartAngle = pageAngle
            lastRotationSnap = nil
        case .changed:
            lastViewportChange = CACurrentMediaTime()
            var degrees = Double((rotationStartAngle + g.rotation) * 180 / .pi)
            let nearest = (degrees / 15).rounded() * 15
            if abs(degrees - nearest) < 2.5 {
                degrees = nearest
                if lastRotationSnap != Int(nearest) {
                    lastRotationSnap = Int(nearest)
                    playHaptic(.alignment, at: nil)
                }
            } else {
                lastRotationSnap = nil
            }
            degrees = min(max(degrees, -90), 90)
            applyRotation(degrees: degrees, locked: rotationLocked)
            model.settings.pageAngle = degrees
        default:
            break
        }
    }

    // MARK: - Shapes

    private func updateShapePreview(_ docPoint: CGPoint) {
        guard let start = shapeStart else { return }
        let o = pageOrigin(start.page)
        let end = snappedShapeEnd(CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y), from: start.point)
        overlay.previewPaths = model.shapePaths(from: start.point, to: end).map { path in
            path.map { CGPoint(x: CGFloat($0.x) + o.x, y: CGFloat($0.y) + o.y) }
        }
        overlay.liveLabel = (point: CGPoint(x: end.x + o.x, y: end.y + o.y),
                             text: ShapeBuilder.measurement(model.shapeKind, from: start.point, to: end))
        overlayChanged()
    }

    /// Lines, arrows and dimensions click to 15° steps; boxes to squares when nearly square.
    private func snappedShapeEnd(_ p: CGPoint, from a: CGPoint) -> CGPoint {
        let dx = p.x - a.x
        let dy = p.y - a.y
        switch model.shapeKind {
        case .line, .arrow, .doubleArrow, .dimension:
            let len = hypot(dx, dy)
            let angle = atan2(dy, dx)
            let step = CGFloat.pi / 12
            let nearest = (angle / step).rounded() * step
            if abs(angle - nearest) < 0.05 {
                return CGPoint(x: a.x + cos(nearest) * len, y: a.y + sin(nearest) * len)
            }
            return p
        case .rectangle, .ellipse:
            if abs(abs(dx) - abs(dy)) < max(abs(dx), abs(dy)) * 0.06 {
                let s = max(abs(dx), abs(dy))
                return CGPoint(x: a.x + (dx < 0 ? -s : s), y: a.y + (dy < 0 ? -s : s))
            }
            return p
        default:
            return p
        }
    }

    // MARK: - Compass

    private func compassBegan(_ docPoint: CGPoint) {
        guard let page = model.layout.page(containing: docPoint, tolerance: 8) else {
            inkGesture.abandon()
            return
        }
        let o = pageOrigin(page)
        let p = CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y)
        let zoom = docTransform.zoom
        if let c = model.compass, c.page == page, hypot(p.x - c.center.x, p.y - c.center.y) > 14 / zoom {
            // Armed: the pencil swings around the center and draws an arc of the set radius.
            let angle = atan2(p.y - c.center.y, p.x - c.center.x)
            let first = CGPoint(x: c.center.x + cos(angle) * c.radius, y: c.center.y + sin(angle) * c.radius)
            compassArc = (page: page, last: angle, points: [first])
            overlay.compassPen = CGPoint(x: first.x + o.x, y: first.y + o.y)
            updateArcPreview()
        } else {
            // New center (also when the pencil starts on the old one).
            model.compass = nil
            compassDraft = (page: page, center: p)
            overlay.compass = (center: docPoint, radius: 0)
            overlay.compassPen = docPoint
            overlayChanged()
        }
    }

    private func compassMoved(_ docPoint: CGPoint) {
        if let draft = compassDraft {
            let o = pageOrigin(draft.page)
            let center = CGPoint(x: draft.center.x + o.x, y: draft.center.y + o.y)
            let r = hypot(docPoint.x - center.x, docPoint.y - center.y)
            overlay.compass = (center: center, radius: r)
            overlay.compassPen = docPoint
            overlay.liveLabel = (point: docPoint, text: "r = " + ShapeBuilder.mm(r / pointsPerMillimetre))
            overlayChanged()
            return
        }
        guard var arc = compassArc, let c = model.compass else { return }
        let o = pageOrigin(arc.page)
        let p = CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y)
        let angle = atan2(p.y - c.center.y, p.x - c.center.x)
        var delta = angle - arc.last
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let steps = max(1, Int((abs(delta) / (2 * .pi / 180)).rounded(.up)))
        for i in 1...steps {
            let a = arc.last + delta * CGFloat(i) / CGFloat(steps)
            arc.points.append(CGPoint(x: c.center.x + cos(a) * c.radius, y: c.center.y + sin(a) * c.radius))
        }
        arc.last = angle
        compassArc = arc
        if let lastPoint = arc.points.last {
            overlay.compassPen = CGPoint(x: lastPoint.x + o.x, y: lastPoint.y + o.y)
        }
        updateArcPreview()
    }

    private func updateArcPreview() {
        guard let arc = compassArc else { return }
        let brush = model.activeBrush
        let r = model.width(for: brush) * 0.5
        activeStroke = ActiveStroke(page: arc.page, brush: brush, color: model.color(for: brush), width: model.width(for: brush),
                                    seed: 0.5, points: arc.points.map { InkPoint(x: Float($0.x), y: Float($0.y), r: r, ink: 0.55) },
                                    startTime: Date().timeIntervalSinceReferenceDate)
        refreshOverlay()
        setNeedsRender()
    }

    private func compassEnded(_ docPoint: CGPoint) {
        if let draft = compassDraft {
            compassDraft = nil
            let o = pageOrigin(draft.page)
            let p = CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y)
            let r = hypot(p.x - draft.center.x, p.y - draft.center.y)
            model.compass = r > 3 ? CompassState(page: draft.page, center: draft.center, radius: r) : nil
            if r > 3 { playHaptic(.alignment, at: nil) }
            return
        }
        if let arc = compassArc {
            compassArc = nil
            activeStroke = nil
            model.addArc(page: arc.page, points: arc.points)
        }
    }

    // MARK: - Lasso

    private func lassoBegan(_ docPoint: CGPoint, zoom: CGFloat) {
        guard let page = model.layout.page(containing: docPoint, tolerance: 16) else {
            inkGesture.abandon()
            return
        }
        let o = pageOrigin(page)
        let p = CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y)
        lassoZoom = zoom
        if let sel = model.displayedSelection, sel.page == page, beginSelectionDrag(p, in: sel, zoom: zoom) {
            return
        }
        model.clearSelection()
        lassoPage = page
        lassoPoints = [docPoint]
        lassoTravel = 0
        overlay.lasso = lassoPoints
        overlayChanged()
    }

    /// Starts moving, resizing or turning the selection when `p` (page space) is on its frame or a
    /// handle. False when the touch is somewhere else.
    private func beginSelectionDrag(_ p: CGPoint, in sel: InkSelection, zoom: CGFloat, reach: CGFloat = 24) -> Bool {
        guard let drag = selectionGrab(at: p, in: sel, zoom: zoom, reach: reach) else { return false }
        selectionDrag = drag
        if case .rotate = drag {
            // It starts settled at 0°: no click until it leaves and comes back.
            lastRotationSnap = 0
        }
        model.beginSelectionEdit()
        return true
    }

    /// What a touch at `p` (page space) does to the selection: turn it (the handle above the
    /// frame), resize it (any corner; the opposite one stays put), move it (inside), or nothing.
    /// `reach` is in screen points.
    private func selectionGrab(at p: CGPoint, in sel: InkSelection, zoom: CGFloat, reach: CGFloat) -> SelectionDrag? {
        let frame = sel.bounds.insetBy(dx: -8 / zoom, dy: -8 / zoom)
        let reach = reach / zoom
        let turnHandle = CGPoint(x: frame.midX, y: frame.minY - CanvasOverlayView.turnHandleOffset / zoom)
        if hypot(p.x - turnHandle.x, p.y - turnHandle.y) < reach {
            let center = CGPoint(x: sel.bounds.midX, y: sel.bounds.midY)
            return .rotate(center: center, startAngle: atan2(p.y - center.y, p.x - center.x))
        }
        let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)]
        let fixed = [CGPoint(x: sel.bounds.maxX, y: sel.bounds.maxY), CGPoint(x: sel.bounds.minX, y: sel.bounds.maxY),
                     CGPoint(x: sel.bounds.minX, y: sel.bounds.minY), CGPoint(x: sel.bounds.maxX, y: sel.bounds.minY)]
        for (i, c) in corners.enumerated() where hypot(p.x - c.x, p.y - c.y) < reach {
            let anchor = fixed[i]
            return .scale(anchor: anchor, startDistance: max(hypot(p.x - anchor.x, p.y - anchor.y), 1))
        }
        if frame.contains(p) {
            return .move(start: p)
        }
        return nil
    }

    /// The box of a sticker being placed works like the lasso's frame, whatever tool is in the hand.
    private func beginPlacementDrag(_ docPoint: CGPoint, zoom: CGFloat, reach: CGFloat = 24) -> Bool {
        guard let sel = model.displayedSelection else { return false }
        let o = pageOrigin(sel.page)
        lassoZoom = zoom
        return beginSelectionDrag(CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y), in: sel, zoom: zoom, reach: reach)
    }

    // MARK: - Shape handles

    /// The handle of the recognized shape under the pencil (or finger), if any. `reach` is in
    /// screen points. With `inside`, a touch within a closed shape (or along an open one) that
    /// misses the corner handles takes the move handle, so the shape moves from anywhere on it.
    private func shapeHandle(at docPoint: CGPoint, in edit: ShapeEditState, zoom: CGFloat, reach: CGFloat = 16,
                             inside: Bool = true) -> Int? {
        let o = pageOrigin(edit.page)
        let p = CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y)
        let handles = edit.shape.handles
        var best: Int?
        var bestDistance = reach / max(zoom, 0.01)
        for (i, h) in handles.enumerated() {
            let d = hypot(p.x - h.x, p.y - h.y)
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        if best != nil || !inside || handles.isEmpty { return best }
        let outline = edit.shape.path()
        guard outline.count >= 2 else { return nil }
        switch edit.shape.kind {
        case .polygon, .oval:
            let path = CGMutablePath()
            path.addLines(between: outline)
            path.closeSubpath()
            if path.contains(p) { return handles.count - 1 }
        case .polyline, .curve:
            let tolerance = 14 / max(zoom, 0.01)
            for i in 1..<outline.count where Geo.segmentDistance(p, outline[i - 1], outline[i]) <= tolerance {
                return handles.count - 1
            }
        }
        return nil
    }

    private func dragShapeHandle(_ index: Int, to docPoint: CGPoint) {
        guard let edit = model.shapeEdit else { return }
        let o = pageOrigin(edit.page)
        let zoom = docTransform.zoom
        let p = CGPoint(x: docPoint.x - o.x + shapeHandleOffset.x, y: docPoint.y - o.y + shapeHandleOffset.y)
        guard let feedback = model.moveShapeHandle(index, to: p, snap: 9 / max(zoom, 0.01)) else { return }
        if feedback.snapped && !lastShapeSnapped {
            playHaptic(.alignment, at: nil)
        }
        lastShapeSnapped = feedback.snapped
        if let label = feedback.label {
            overlay.liveLabel = (point: docPoint, text: label)
        } else {
            overlay.liveLabel = nil
        }
        overlayChanged()
    }

    private func lassoMoved(_ docPoint: CGPoint) {
        if let drag = selectionDrag, let sel = model.displayedSelection {
            let o = pageOrigin(sel.page)
            let p = CGPoint(x: docPoint.x - o.x, y: docPoint.y - o.y)
            switch drag {
            case let .move(start):
                model.transformSelection(offset: CGVector(dx: p.x - start.x, dy: p.y - start.y), scale: 1, anchor: .zero)
            case let .scale(anchor, startDistance):
                let k = hypot(p.x - anchor.x, p.y - anchor.y) / startDistance
                model.transformSelection(offset: .zero, scale: k, anchor: anchor)
                overlay.liveLabel = (point: docPoint, text: "%\(Int((k * 100).rounded()))")
            case let .rotate(center, startAngle):
                var angle = Geo.wrap(atan2(p.y - center.y, p.x - center.x) - startAngle)
                // Settles at right angles (0°, 90°, 180°, 270°) with a click; free in between.
                let step = CGFloat.pi / 2
                let nearest = (angle / step).rounded() * step
                if abs(angle - nearest) < 7 * .pi / 180 {
                    angle = nearest
                    let degrees = Int((nearest * 180 / .pi).rounded())
                    if lastRotationSnap != degrees {
                        lastRotationSnap = degrees
                        playHaptic(.alignment, at: nil)
                    }
                } else {
                    lastRotationSnap = nil
                }
                model.transformSelection(offset: .zero, scale: 1, anchor: center, rotation: angle)
                overlay.liveLabel = (point: docPoint, text: "\(Int((-angle * 180 / .pi).rounded()))°")
            }
            overlayChanged()
            return
        }
        guard lassoPage != nil else { return }
        if let last = lassoPoints.last, hypot(docPoint.x - last.x, docPoint.y - last.y) < 2 { return }
        if let last = lassoPoints.last {
            // The pencil ticks each time the loop grows by one dash and gap of its outline.
            let period = CanvasOverlayView.lassoDash.reduce(0, +)
            let before = Int(lassoTravel / period)
            lassoTravel += hypot(docPoint.x - last.x, docPoint.y - last.y) * lassoZoom
            let now = CACurrentMediaTime()
            if Int(lassoTravel / period) > before, now - lastLassoTick > 0.025 {
                lastLassoTick = now
                playHaptic(.alignment, at: nil)
            }
        }
        lassoPoints.append(docPoint)
        overlay.lasso = lassoPoints
        overlayChanged()
    }

    private func lassoEnded() {
        if selectionDrag != nil {
            model.endSelectionEdit()
            return
        }
        guard let page = lassoPage else { return }
        let o = pageOrigin(page)
        let polygon = lassoPoints.map { CGPoint(x: $0.x - o.x, y: $0.y - o.y) }
        lassoPage = nil
        lassoPoints = []
        // A tap (no loop drawn) picks the stroke or picture under the pencil.
        if Geo.length(polygon) < 10 / max(lassoZoom, 0.01), let tap = polygon.first {
            model.selectItem(page: page, at: tap, tolerance: 8 / max(lassoZoom, 0.01))
            return
        }
        model.selectStrokes(page: page, lasso: polygon)
    }
    // MARK: - Text box

    /// Symbols one tap away above the keyboard.
    private static let textSymbols = ["×", "÷", "±", "√", "π", "≈", "≠", "≤", "≥", "∞", "°", "²", "³", "→", "∫", "Δ", "Σ",
                                      "α", "β", "θ", "λ", "μ", "σ", "ω", "ρ", "τ", "φ", "ε", "Ω"]
    private static let accentColor = UIColor(red: 0.10, green: 0.33, blue: 0.80, alpha: 1)

    /// Opens a box where the Aa tool tapped. It sits on the lines the text will be written on and
    /// follows scrolling, zooming and the page angle.
    private func openTextBox(_ request: TextRequest) {
        finishTextBox()
        let box = UITextView()
        box.backgroundColor = Self.accentColor.withAlphaComponent(0.06)
        box.layer.cornerRadius = 4
        box.textContainerInset = .zero
        box.textContainer.lineFragmentPadding = 0
        box.isScrollEnabled = false
        box.tintColor = Self.accentColor
        box.delegate = self
        box.inputAccessoryView = textBoxBar()
        textBox = box
        textBoxRequest = request
        textBoxFontSize = 0
        rotationHost.addSubview(box)
        layoutTextBox()
        box.becomeFirstResponder()
    }

    /// Writes what was typed onto the page and closes the box.
    private func finishTextBox() {
        guard let box = textBox, let request = textBoxRequest else { return }
        textBox = nil
        textBoxRequest = nil
        let text = box.text ?? ""
        box.delegate = nil
        box.resignFirstResponder()
        box.removeFromSuperview()
        model.insertText(text, request: request)
        // The keyboard comes back to the page: the next key starts a box under this text.
        if window != nil {
            becomeFirstResponder()
        }
    }

    // MARK: - Keyboard

    /// The page takes a keyboard case's keys (it is no text field, so no on-screen keyboard shows).
    /// With the Aa tool or the text pen, typing opens a box by itself (KeyboardSpot); in the box,
    /// Esc, ⌘. or ⌘↩ writes it on the page.
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard textBox != nil else { return nil }
        let write = UIKeyCommand(title: Loc.t("Yazıyı sayfaya koy"), action: #selector(writeTextBox), input: "\r", modifierFlags: .command)
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(writeTextBox))
        escape.wantsPriorityOverSystemBehavior = true
        return [write, escape, UIKeyCommand(input: ".", modifierFlags: .command, action: #selector(writeTextBox))]
    }

    @objc private func writeTextBox() {
        finishTextBox()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard model.tool == .text || model.tool == .textPen, textBox == nil,
              let key = presses.first?.key, Self.types(key), let request = keyboardRequest() else {
            super.pressesBegan(presses, with: event)
            return
        }
        openTextBox(request)
        textBox?.insertText(key.characters)
    }

    /// A key that writes something: not a shortcut, not Return, Tab, Esc, an arrow or a function key
    /// (those come as control or private-use characters), and not a lone space.
    private static func types(_ key: UIKey) -> Bool {
        guard key.modifierFlags.isDisjoint(with: [.command, .control]) else { return false }
        let text = key.characters
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { s in
            !CharacterSet.controlCharacters.contains(s) && s.properties.generalCategory != .privateUse
        }
    }

    /// Where a box opened from the keyboard goes: on the page in view, under its ink (KeyboardSpot).
    private func keyboardRequest() -> TextRequest? {
        let (origin, zoom) = docTransform
        let visible = visibleDocRect(origin: origin, zoom: zoom)
        let page = model.layout.dominantPage(in: visible)
        guard model.layout.pageRects.indices.contains(page),
              let lines = model.typedLayout(page: page, at: .zero) else { return nil }
        let rect = model.layout.pageRects[page]
        let view = visible.offsetBy(dx: -rect.minX, dy: -rect.minY)
        let ink = model.strokes(on: page).filter { !$0.points.isEmpty }.map { CGRect(ink: $0.bounds) }
        let last = model.lastTyped.flatMap { $0.page == page ? $0.rect : nil }
        let point = KeyboardSpot.start(lastTyped: last, ink: ink, viewTop: max(view.minY, 0), viewBottom: min(view.maxY, rect.height),
                                       left: lines.left > 0 ? lines.left : 40, spacing: lines.spacing)
        return TextRequest(page: page, point: point)
    }

    /// Keeps the box on its lines at the current zoom, its capitals as tall as the written ones.
    private func layoutTextBox() {
        guard let box = textBox, let request = textBoxRequest,
              let lines = model.typedLayout(page: request.page, at: request.point) else { return }
        let (origin, zoom) = docTransform
        let o = pageOrigin(request.page)
        // San Francisco's capitals are about 0.7 of its point size.
        let size = max(lines.cap * zoom / 0.7, 4)
        let lineHeight = lines.spacing * zoom
        let font = UIFont.systemFont(ofSize: size)
        if abs(size - textBoxFontSize) > 0.05 {
            textBoxFontSize = size
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            let ink = model.typedColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraph,
                .foregroundColor: UIColor(red: CGFloat(ink.r), green: CGFloat(ink.g), blue: CGFloat(ink.b), alpha: 1),
            ]
            box.typingAttributes = attributes
            box.textStorage.setAttributes(attributes, range: NSRange(location: 0, length: box.textStorage.length))
        }
        let width = max((lines.right - lines.left) * zoom, 40)
        // TextKit puts a line's extra height above the letters: the baseline sits one descender
        // above the bottom of the line.
        let firstBaseline = origin.y + (o.y + lines.baseline) * zoom
        let top = firstBaseline - (lineHeight + font.descender)
        let fit = box.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let frame = CGRect(x: origin.x + (o.x + lines.left) * zoom, y: top, width: width, height: max(fit.height, lineHeight))
        if box.frame != frame {
            box.frame = frame
        }
    }

    /// Symbols and the ✓ that writes the text, above the keyboard.
    private func textBoxBar() -> UIView {
        let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 50), inputViewStyle: .keyboard)
        bar.autoresizingMask = .flexibleWidth
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        for symbol in Self.textSymbols {
            let button = UIButton(type: .system)
            button.setTitle(symbol, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .title3)
            button.tintColor = .label
            button.addAction(UIAction { [weak self] _ in self?.textBox?.insertText(symbol) }, for: .touchUpInside)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            stack.addArrangedSubview(button)
        }
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let done = UIButton(type: .system)
        done.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26)),
                      for: .normal)
        done.tintColor = Self.accentColor
        done.accessibilityLabel = Loc.t("Sayfaya yaz")
        done.addAction(UIAction { [weak self] _ in self?.finishTextBox() }, for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(scroll)
        bar.addSubview(done)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: bar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -8),
            done.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            done.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            done.widthAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return bar
    }

    /// Moves the page up when the keyboard would cover the text box.
    @objc private func keyboardWillShow(_ note: Notification) {
        guard let box = textBox, let window = box.window, let screen = window.windowScene?.screen,
              let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboard = window.convert(end, from: screen.coordinateSpace)
        let boxBottom = box.convert(CGPoint(x: box.bounds.midX, y: box.bounds.maxY), to: window).y
        let overlap = boxBottom + 24 - keyboard.minY
        guard overlap > 0 else { return }
        // "Up" on screen in the scrolling directions of the turned page.
        var offset = scrollView.contentOffset
        offset.x += overlap * sin(pageAngle)
        offset.y += overlap * cos(pageAngle)
        clamp(&offset)
        scrollView.setContentOffset(offset, animated: true)
    }

    // MARK: - Hold to straighten

    private func trackHold(_ viewPoint: CGPoint) {
        guard model.settings.straightLine, let b = builder, !b.isStraight, pendingSketch == nil else { return }
        if let anchor = holdAnchor, hypot(viewPoint.x - anchor.x, viewPoint.y - anchor.y) < 4 {
            return
        }
        holdAnchor = viewPoint
        holdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.holdFired()
        }
        holdWork = work
        // The text pen waits a little longer: a pen resting while thinking mid-word is not a request.
        DispatchQueue.main.asyncAfter(deadline: .now() + (gestureTool == .textPen ? 0.75 : 0.55), execute: work)
    }

    /// With the text pen only drawings larger than handwriting (a heart, a circle round a word)
    /// become shapes or pictures; letters stay letters.
    private static func textPenSymbolSize(penWidth: CGFloat) -> CGFloat {
        // Thick pens write bigger letters; they must stay letters too.
        max(28, 4 * penWidth)
    }

    private func cancelHold() {
        holdWork?.cancel()
        holdWork = nil
        holdAnchor = nil
    }

    /// The pencil rested: a heart or a face gets picture suggestions when the pencil lifts; anything
    /// else that looks like a line, circle, ellipse, curve, rectangle or polygon becomes one.
    private func holdFired() {
        guard inkGesture.isTracking, var b = builder, var active = activeStroke else { return }
        let path = b.drawnPath
        if gestureTool == .textPen {
            let box = Geo.bounds(path)
            let penWidth = CGFloat(model.width(for: model.activeBrush))
            guard max(box.width, box.height) >= Self.textPenSymbolSize(penWidth: penWidth) else { return }
        }
        if model.settings.sketchSuggestions, let sketch = recognizeSketch(path, page: active.page) {
            pendingSketch = sketch
            playHaptic(.alignment, at: holdAnchor)
            showHint(Loc.t("{0} · kaldırınca seçenekler", "\(sketch.kind.title)"), near: path.last, page: active.page)
            return
        }
        guard let title = b.snapToShape() else { return }
        builder = b
        active.points = b.preview(predicted: [])
        activeStroke = active
        snappedTitle = title
        playHaptic(.alignment, at: holdAnchor)
        showHint(b.shapeAdjustment == nil ? title : Loc.t("{0} · kalemi kaydır: boyut ve yön", "\(title)"), near: path.last, page: active.page)
        setNeedsRender()
    }

    private struct PendingSketch {
        let kind: SketchSuggestion.Kind
        let alternate: SketchSuggestion.Kind?
        /// Earlier strokes that belong to the drawing (a face's outline and eyes, the other lung).
        let others: Set<Int>
    }

    /// Hearts, kidneys, spleens, lungs and faces: the held stroke together with the recent strokes
    /// around it (a face or a pair of lungs takes several strokes).
    private func recognizeSketch(_ path: [CGPoint], page: Int) -> PendingSketch? {
        let now = Date().timeIntervalSinceReferenceDate
        let recent = Array(model.strokes(on: page).suffix(12).filter { now - $0.birth < 90 })
        let candidates = recent.map { s in s.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } } + [path]
        guard let match = SketchRecognizer.recognize(candidates) else { return nil }
        let ids = Set(match.members.filter { $0 < recent.count }.map { recent[$0].id })
        return PendingSketch(kind: match.kind, alternate: match.alternate, others: ids)
    }
    /// A short label next to the pencil ("Daire", "Parabol"…).
    private func showHint(_ text: String, near point: CGPoint?, page: Int) {
        guard let point else { return }
        let o = pageOrigin(page)
        overlay.liveLabel = (point: CGPoint(x: point.x + o.x, y: point.y + o.y), text: text)
        overlayChanged()
    }

    // MARK: - Eraser

    private func erase(from a: CGPoint, to b: CGPoint) {
        guard let page = eraserPage else { return }
        let origin = model.layout.pageRects[page].origin
        model.erase(page: page,
                    from: SIMD2<Float>(Float(a.x - origin.x), Float(a.y - origin.y)),
                    to: SIMD2<Float>(Float(b.x - origin.x), Float(b.y - origin.y)))
    }

    private func finishErasing() {
        eraserPage = nil
        lastEraserPoint = nil
        eraserRing.isHidden = true
        model.endErase()
        // A borrowed eraser goes back to the pen (or highlighter…) as soon as the erasing is done,
        // unless the squeeze is still held.
        if model.isTemporaryEraser && !squeezeIsHeld {
            model.endTemporaryEraser()
            playHaptic(.selection, at: nil)
        }
        refreshLoop()
        setNeedsRender()
    }

    private func cancelErasing() {
        eraserPage = nil
        lastEraserPoint = nil
        eraserRing.isHidden = true
        model.cancelErase()
        refreshLoop()
        setNeedsRender()
    }

    private func showEraserRing(at point: CGPoint) {
        let d = max(8, CGFloat(model.eraserSize) * docTransform.zoom)
        eraserRing.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        eraserRing.center = point
        eraserRing.layer.cornerRadius = d / 2
        eraserRing.isHidden = false
    }

    // MARK: - Gestures

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Pencil only: the only finger the ink gesture takes is one on a handle or a sticker's box;
        // every other finger is left to scrolling.
        if gestureRecognizer === inkGesture, pencilOnly, touch.type == .direct {
            return fingerTakesEditHandle(touch)
        }
        return true
    }

    /// A finger (not a resting palm) on a handle of the recognized shape or on the box of the
    /// sticker being placed.
    private func fingerTakesEditHandle(_ touch: UITouch) -> Bool {
        guard model.shapeEdit != nil || model.placingSticker != nil, touch.majorRadius < 34 else { return false }
        let p = touch.location(in: zoomContainer)
        let zoom = docTransform.zoom
        if let edit = model.shapeEdit, shapeHandle(at: p, in: edit, zoom: zoom, reach: Self.fingerReach) != nil {
            return true
        }
        if model.placingSticker != nil, let sel = model.displayedSelection {
            let o = pageOrigin(sel.page)
            return selectionGrab(at: CGPoint(x: p.x - o.x, y: p.y - o.y), in: sel, zoom: zoom, reach: Self.fingerReach) != nil
        }
        return false
    }

    /// How far from a handle (screen points) a fingertip still takes it; the pencil needs less.
    private static let fingerReach: CGFloat = 34

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === instrumentPan || gestureRecognizer === instrumentTurn {
            return gestureStartsOnInstrument(gestureRecognizer)
        }
        if gestureRecognizer === pageRotation {
            return !rotationLocked && !gestureStartsOnInstrument(gestureRecognizer)
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// True right after the page moved, zoomed or turned: fingers that land then are stopping or
    /// steering the page, not tapping.
    private var viewportJustMoved: Bool {
        CACurrentMediaTime() - lastViewportChange < 0.4
    }

    /// A finger tap anywhere but on a corner handle (or the sticker box's corner and turn handles)
    /// settles the shape or the sticker.
    @objc private func fingerTapped(_ g: UITapGestureRecognizer) {
        // In pencil-only mode a finger tap on the page is how the text box is closed.
        if g.state == .ended, textBox != nil, pencilOnly {
            finishTextBox()
            return
        }
        // With a lecture take open, a finger tap on ink plays from when it was written.
        if g.state == .ended, let seek = model.onInkTap,
           let birth = model.strokeBirth(near: g.location(in: zoomContainer), reach: 18 / max(docTransform.zoom, 0.01)) {
            seek(birth)
            playHaptic(.selection, at: nil)
            return
        }
        guard g.state == .ended, model.shapeEdit != nil || model.placingSticker != nil else { return }
        let p = g.location(in: zoomContainer)
        let zoom = docTransform.zoom
        if let edit = model.shapeEdit, shapeHandle(at: p, in: edit, zoom: zoom, reach: Self.fingerReach, inside: false) != nil {
            return
        }
        if model.placingSticker != nil, let sel = model.displayedSelection {
            let o = pageOrigin(sel.page)
            switch selectionGrab(at: CGPoint(x: p.x - o.x, y: p.y - o.y), in: sel, zoom: zoom, reach: Self.fingerReach) {
            case .scale?, .rotate?: return
            default: break
            }
        }
        if model.shapeEdit != nil { model.finishShapeEdit() }
        if model.placingSticker != nil { model.finishPlacing() }
        playHaptic(.selection, at: nil)
        setNeedsRender()
    }

    @objc private func twoFingerTap() {
        guard model.settings.fingerTapUndo, !inkGesture.isTracking, !viewportJustMoved, model.canUndo else { return }
        model.undo()
        model.banner = Loc.t("Geri alındı (iki parmakla dokunma)")
    }

    @objc private func threeFingerTap() {
        guard model.settings.fingerTapUndo, !inkGesture.isTracking, !viewportJustMoved, model.canRedo else { return }
        model.redo()
        model.banner = Loc.t("Yinelendi (üç parmakla dokunma)")
    }

    // MARK: - Apple Pencil double tap and squeeze

    /// iPadOS 17.0–17.4. Newer systems call `pencilInteraction(_:didReceiveTap:)` instead.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        handlePencilTap(at: nil)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        handlePencilTap(at: tap.hoverPose?.location)
    }

    /// Apple Pencil Pro squeeze. With the temporary eraser, squeezing (and holding) switches to the
    /// eraser; when the erasing is done, the tool you had returns by itself.
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if let pose = squeeze.hoverPose {
            lastHover = pose.location
        }
        // A held squeeze sends a stream of changes; publishing on each one redrew the whole editor.
        if !model.pencilProDetected { model.pencilProDetected = true }
        let configured = model.settings.squeezeAction
        let action = configured == .system ? Self.mapPreferred(UIPencilInteraction.preferredSqueezeAction) : configured
        if action == .holdToErase {
            // The squeeze's own time, not the moment it is handled: a late end on a busy main thread
            // made a quick squeeze look held, and letting go took the eraser straight back.
            let now = squeeze.timestamp > 0 ? squeeze.timestamp : CACurrentMediaTime()
            switch squeeze.phase {
            case .began:
                startSqueeze(at: now)
            case .changed:
                // The start of this squeeze went missing.
                if !squeezeIsHeld && now - lastSqueezeEnd > 0.3 { startSqueeze(at: now) }
            case .ended, .cancelled:
                if !squeezeIsHeld {
                    // A quick squeeze can arrive as its end alone: it still switches. An end right
                    // after one already handled belongs to that same squeeze.
                    guard now - lastSqueezeEnd > 0.3 else { return }
                    startSqueeze(at: now)
                }
                endSqueeze(at: now)
            default:
                break
            }
            return
        }
        guard squeeze.phase == .ended else { return }
        run(action, at: squeeze.hoverPose?.location)
    }

    /// A squeeze that was never let go (its end lost) stops counting as held after a while, so the
    /// borrowed eraser can still go back by itself.
    private var squeezeIsHeld: Bool {
        squeezeHeld && CACurrentMediaTime() - squeezeStart < 20
    }

    /// Squeezing switches between the eraser and the tool before it, wherever the eraser came
    /// from (a squeeze, a double tap, the toolbar).
    private func startSqueeze(at time: CFTimeInterval) {
        if model.palette != nil { model.palette = nil }
        squeezeHeld = true
        squeezeStart = time
        erasedDuringSqueeze = false
        if model.tool == .eraser {
            squeezeTookEraser = false
            model.leaveEraser()
        } else {
            squeezeTookEraser = true
            model.beginTemporaryEraser()
        }
    }

    /// A squeeze held at least this long (seconds) is a hold, not a click.
    private static let squeezeHold: CFTimeInterval = 0.5

    /// Letting go of a held squeeze gives the previous tool back (erased or not); a short squeeze
    /// leaves the eraser in the hand until the next erase is done (or the next squeeze).
    private func endSqueeze(at time: CFTimeInterval) {
        let heldLong = time - squeezeStart >= Self.squeezeHold
        squeezeHeld = false
        lastSqueezeEnd = time
        if squeezeTookEraser && (erasedDuringSqueeze || heldLong) && eraserPage == nil && model.isTemporaryEraser {
            model.endTemporaryEraser()
        }
        squeezeTookEraser = false
    }

    private func handlePencilTap(at location: CGPoint?) {
        // Guards against both callbacks arriving for one tap.
        let now = CACurrentMediaTime()
        guard now - lastPencilTap > 0.25 else { return }
        lastPencilTap = now
        let configured = model.settings.tapAction
        let action = configured == .system ? Self.mapPreferred(UIPencilInteraction.preferredTapAction) : configured
        run(action, at: location)
    }

    private static func mapPreferred(_ preferred: UIPencilPreferredAction) -> PencilAction {
        switch preferred {
        case .ignore: return .nothing
        case .switchEraser: return .holdToErase
        case .switchPrevious: return .previous
        case .showColorPalette: return .colors
        default: return .palette
        }
    }

    private func run(_ action: PencilAction, at location: CGPoint?) {
        switch action {
        case .system, .palette:
            togglePalette(.tools, at: location)
        case .colors:
            togglePalette(.colors, at: location)
        case .holdToErase:
            model.palette = nil
            // From any eraser (borrowed or picked from the toolbar) back to the tool before it.
            if model.tool == .eraser {
                model.leaveEraser()
            } else {
                model.beginTemporaryEraser()
            }
        case .eraser:
            model.palette = nil
            model.toggleEraser()
        case .previous:
            model.palette = nil
            model.switchToPrevious()
        case .nothing:
            break
        }
    }

    private func togglePalette(_ mode: PaletteRequest.Mode, at location: CGPoint?) {
        // An open ring closes, whichever page of it shows: picking a pen turns the tools into
        // colors inside the ring, so the request's mode no longer says what is on screen.
        if model.palette != nil {
            model.palette = nil
            playHaptic(.selection, at: location)
            return
        }
        let p = location ?? lastHover ?? CGPoint(x: bounds.midX, y: bounds.midY)
        model.palette = PaletteRequest(location: p, mode: mode)
        playHaptic(.selection, at: p)
    }

    // MARK: - Haptics

    private func playHaptic(_ kind: CanvasHaptic, at point: CGPoint?) {
        let p = point ?? lastHover ?? CGPoint(x: bounds.midX, y: bounds.midY)
        if #available(iOS 17.5, *), let feedback = canvasFeedback as? UICanvasFeedbackGenerator {
            switch kind {
            case .selection, .alignment:
                feedback.alignmentOccurred(at: p)
            case .completed:
                feedback.pathCompleted(at: p)
            }
            return
        }
        fallbackFeedback.selectionChanged()
    }

    // MARK: - Hover preview

    @objc private func hovered(_ g: UIHoverGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            let z = g.zOffset
            // zOffset is 0 for a trackpad pointer; only the pencil gets the preview.
            guard z > 0 else {
                hideCursor()
                return
            }
            lastHover = g.location(in: self)
            // Follows the system "Show hover preview" Apple Pencil setting as well as the app's own.
            var systemAllows = true
            if #available(iOS 17.5, *) {
                systemAllows = UIPencilInteraction.prefersHoverToolPreview
            }
            guard model.settings.hoverPreview, systemAllows, !inkGesture.isTracking else {
                hideCursor()
                return
            }
            var roll: CGFloat = 0
            if #available(iOS 17.5, *) {
                roll = g.rollAngle
                if abs(roll) > 0.02 && !model.pencilProDetected {
                    model.pencilProDetected = true
                }
            }
            showCursor(at: g.location(in: rotationHost), z: z, altitude: g.altitudeAngle,
                       azimuth: g.azimuthAngle(in: rotationHost), roll: roll)
        default:
            hideCursor()
        }
    }

    private func showCursor(at p: CGPoint, z: CGFloat, altitude: CGFloat, azimuth: CGFloat, roll: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let zoom = docTransform.zoom
        let fade = Float(max(0.25, 1 - z * 0.7))
        let path: UIBezierPath
        switch model.tool {
        case .eraser:
            let d = max(8, CGFloat(model.eraserSize) * zoom)
            path = UIBezierPath(ovalIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
            hoverCursor.fillColor = UIColor.white.withAlphaComponent(0.25).cgColor
            hoverCursor.strokeColor = UIColor.systemGray.cgColor
        case .lasso, .text:
            path = UIBezierPath(ovalIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            hoverCursor.fillColor = UIColor(red: 0.10, green: 0.33, blue: 0.80, alpha: 0.8).cgColor
            hoverCursor.strokeColor = UIColor.white.cgColor
        case .brush, .shape, .compass, .textPen:
            let brush = model.activeBrush
            let w = max(3, CGFloat(model.width(for: brush)) * zoom)
            let c = model.color(for: brush)
            let ui = UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
            if brush == .calligraphy && model.tool == .brush(.calligraphy) {
                // The flat nib, turned by the barrel roll of Apple Pencil Pro.
                let angle = CGFloat(model.settings.nibAngle) * .pi / 180 + (model.settings.rollRotatesNib ? roll : 0)
                let rect = UIBezierPath(roundedRect: CGRect(x: -w / 2, y: -max(1.5, w * 0.08), width: w, height: max(3, w * 0.16)),
                                        cornerRadius: 1.5)
                rect.apply(CGAffineTransform(rotationAngle: angle))
                rect.apply(CGAffineTransform(translationX: p.x, y: p.y))
                path = rect
            } else {
                path = UIBezierPath(ovalIn: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
            }
            hoverCursor.fillColor = ui.withAlphaComponent(brush == .highlighter ? 0.35 : 0.55).cgColor
            hoverCursor.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        }
        hoverCursor.path = path.cgPath
        hoverCursor.opacity = fade

        // Tool shadow: the pencil's silhouette falls away from the tip along the barrel direction.
        let lean = cos(min(max(altitude, 0.1), .pi / 2))
        let length = 26 + 150 * lean
        let lift = z * 22
        let dir = CGPoint(x: cos(azimuth), y: sin(azimuth))
        let normal = CGPoint(x: -dir.y, y: dir.x)
        let tip = CGPoint(x: p.x + dir.x * lift + 4, y: p.y + dir.y * lift + 6)
        let end = CGPoint(x: tip.x + dir.x * length, y: tip.y + dir.y * length)
        let shadow = UIBezierPath()
        shadow.move(to: tip)
        shadow.addLine(to: CGPoint(x: tip.x + dir.x * 14 + normal.x * 4.5, y: tip.y + dir.y * 14 + normal.y * 4.5))
        shadow.addLine(to: CGPoint(x: end.x + normal.x * 4.5, y: end.y + normal.y * 4.5))
        shadow.addLine(to: CGPoint(x: end.x - normal.x * 4.5, y: end.y - normal.y * 4.5))
        shadow.addLine(to: CGPoint(x: tip.x + dir.x * 14 - normal.x * 4.5, y: tip.y + dir.y * 14 - normal.y * 4.5))
        shadow.close()
        toolShadow.path = shadow.cgPath
        toolShadow.shadowPath = shadow.cgPath
        toolShadow.opacity = fade * 0.9
        CATransaction.commit()
        cursorView.isHidden = false
    }

    private func hideCursor() {
        cursorView.isHidden = true
    }

    // MARK: - Lifecycle

    @objc private func sceneWillDeactivate() {
        model.saveNow()
        // The end of a squeeze held while the app goes away never arrives.
        squeezeHeld = false
    }

    @objc private func sceneDidEnterBackground() {
        stopLoop()
    }

    @objc private func sceneWillEnterForeground() {
        setNeedsRender()
    }

    /// Low Power Mode and thermal state changes arrive on a background queue.
    @objc private nonisolated func powerConditionsChanged() {
        Task { @MainActor [weak self] in
            self?.refreshLoop()
        }
    }

    @objc private func memoryWarning() {
        let (origin, zoom) = docTransform
        let visible = model.layout.pages(intersecting: visibleDocRect(origin: origin, zoom: zoom))
        renderer?.pdfTextures?.purge(keeping: visible)
        setNeedsRender()
    }
}

extension CanvasView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        layoutTextBox()
    }

    /// The keyboard went away some other way (hidden, another field took it): what was typed is
    /// written all the same.
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView === textBox {
            finishTextBox()
        }
    }
}

// MARK: - Zoom window

extension CanvasView {
    /// The left and right margin the zoom box keeps on the page.
    private static let zoomMargin: CGFloat = 36

    /// Where a touch lands in the document: through the zoom box when it came from the zoom panel.
    private func docLocation(_ t: UITouch) -> CGPoint {
        if zoomInput, let panel = zoomPanel, let box = zoomBox {
            let p = t.preciseLocation(in: panel.inkView)
            let s = panel.scale(for: box.rect)
            let o = pageOrigin(box.page)
            return CGPoint(x: o.x + box.rect.minX + p.x / s, y: o.y + box.rect.minY + p.y / s)
        }
        return t.preciseLocation(in: zoomContainer)
    }

    /// Opens or closes the zoom window (EditorModel.zoomWindowOn).
    func applyZoomWindow(on: Bool) {
        guard on != (zoomPanel != nil) else { return }
        if !on {
            zoomPanel?.removeFromSuperview()
            zoomPanel = nil
            zoomBox = nil
            refreshOverlay()
            return
        }
        let panel = ZoomPanelView(device: metalView.device, pdfURL: model.pdfURL, isPDF: model.isPDF)
        panel.source = { [weak self] in self?.zoomFrame() }
        panel.gesture.onBegan = { [weak self] touch, event in self?.zoomTouchBegan(touch, event) }
        panel.gesture.onMoved = { [weak self] touch, event in
            guard let self, self.zoomInput else { return }
            self.touchMoved(touch, event)
        }
        panel.gesture.onEnded = { [weak self] touch, event in self?.zoomTouchEnded(touch, event) }
        panel.gesture.onCancelled = { [weak self] in
            guard let self, self.zoomInput else { return }
            self.touchCancelled()
            self.zoomInput = false
        }
        panel.onBack = { [weak self] in self?.moveZoomBox { box, _ in box.back(margin: Self.zoomMargin) } }
        panel.onNewLine = { [weak self] in
            self?.moveZoomBox(turnsPage: true) { box, size in box.newLine(pageSize: size, margin: Self.zoomMargin) }
        }
        panel.onForward = { [weak self] in
            self?.moveZoomBox(turnsPage: true) { box, size in box.advanced(pageSize: size, margin: Self.zoomMargin) }
        }
        panel.onClose = { [weak self] in self?.model.zoomWindowOn = false }
        addSubview(panel)
        zoomPanel = panel
        layoutZoomPanel()
        panel.layoutIfNeeded()
        let page = min(max(model.currentPage, 0), max(model.layout.pageRects.count - 1, 0))
        if model.layout.pageRects.indices.contains(page) {
            zoomBox = ZoomBox.initial(page: page, pageSize: model.layout.pageRects[page].size, margin: Self.zoomMargin,
                                      aspect: panel.aspect)
        }
        refreshOverlay()
        setNeedsRender()
    }

    /// Keeps the zoom window clear of the pen bar when the bar stands along the bottom or the right side.
    func applyPaletteClearance(_ insets: UIEdgeInsets) {
        guard insets != paletteClearance else { return }
        paletteClearance = insets
        layoutZoomPanel()
        refreshOverlay()
        setNeedsRender()
    }

    /// The panel along the bottom, a third of the canvas tall, clear of the page badge below it.
    private func layoutZoomPanel() {
        guard let panel = zoomPanel else { return }
        let height = min(max(bounds.height * 0.3, 180), 320)
        let clear = paletteClearance
        panel.frame = CGRect(x: 12, y: bounds.height - height - 64 - clear.bottom,
                             width: bounds.width - 24 - clear.right, height: height)
        panel.layoutIfNeeded()
        // The box keeps the panel's shape (its height follows a new width or turn of the iPad).
        if var box = zoomBox {
            box.rect.size.height = (box.rect.width / max(panel.aspect, 1)).rounded()
            zoomBox = box
        }
    }

    private func zoomFrame() -> ZoomFrame? {
        guard let box = zoomBox else { return nil }
        let o = pageOrigin(box.page)
        return ZoomFrame(pages: model.renderPages, layout: model.layout, paper: model.meta.paper, isPDF: model.isPDF,
                         active: activeStroke, box: box.rect.offsetBy(dx: o.x, dy: o.y),
                         dryDuration: model.settings.dryDuration, coolDuration: model.settings.lavaCoolDuration,
                         animate: model.settings.animations, background: metalView.clearColor)
    }

    private func zoomTouchBegan(_ touch: UITouch, _ event: UIEvent) {
        // The panel writes and erases; other tools work on the page itself.
        switch model.tool {
        case .brush, .textPen, .eraser:
            break
        default:
            return
        }
        if pencilOnly && touch.type == .direct { return }
        zoomInput = true
        touchBegan(touch, event)
    }

    private func zoomTouchEnded(_ touch: UITouch, _ event: UIEvent) {
        guard zoomInput else { return }
        let inked = gestureTool.inks
        touchEnded(touch, event)
        zoomInput = false
        // Writing that reached the dashed line moves the box on along the line.
        guard inked, let box = zoomBox, model.pages.indices.contains(box.page),
              let last = model.pages[box.page].strokes.last else { return }
        let reach = box.rect.minX + box.rect.width * ZoomPanelView.advanceShare
        if CGFloat(last.bounds.maxX) > reach {
            moveZoomBox(turnsPage: true) { b, size in b.advanced(pageSize: size, margin: Self.zoomMargin) }
        }
    }

    /// `turnsPage`: at the bottom of a page the box goes on to the next page's first line.
    private func moveZoomBox(turnsPage: Bool = false, _ change: (ZoomBox, CGSize) -> ZoomBox) {
        guard let box = zoomBox, model.layout.pageRects.indices.contains(box.page) else { return }
        var next = change(box, model.layout.pageRects[box.page].size)
        if next == box, turnsPage, model.layout.pageRects.indices.contains(box.page + 1) {
            var first = ZoomBox.initial(page: box.page + 1, pageSize: model.layout.pageRects[box.page + 1].size,
                                        margin: Self.zoomMargin, aspect: zoomPanel?.aspect ?? 4)
            first.rect.size = box.rect.size
            next = first
        }
        guard next != box else {
            playHaptic(.alignment, at: nil)
            return
        }
        zoomBox = next
        // Keep the box in view on the page.
        let o = pageOrigin(next.page)
        let (origin, zoom) = docTransform
        let visible = visibleDocRect(origin: origin, zoom: zoom)
        let target = next.rect.offsetBy(dx: o.x, dy: o.y)
        if !visible.insetBy(dx: 0, dy: visible.height * 0.1).contains(target) {
            scrollToPage(next.page, animated: true)
        }
        refreshOverlay()
        setNeedsRender()
    }
}

#if DEMO
// MARK: - Ad recordings (tools/demo)

/// Recording builds only (the DEMO flag; never the App Store edition): a scripted pencil goes the way
/// a real one does, through the stroke builder, the live stroke and the page (see DemoPlayer).
extension CanvasView {
    func demoPenDown(page: Int, _ sample: InputSample) {
        guard model.layout.pageRects.indices.contains(page) else { return }
        gestureTool = model.tool
        switch gestureTool {
        case .brush, .textPen:
            break
        default:
            return
        }
        if gestureTool == .textPen { model.textPenTouched() }
        let brush = model.activeBrush
        let random = Float.random(in: 0..<1)
        let seed = brush == .grass ? GrassGenerator.seed(level: model.settings.flowerLevel, random: random) : random
        var b = StrokeBuilder(brush: brush, color: model.color(for: brush), width: model.width(for: brush), seed: seed)
        b.nibAngle = Float(model.settings.nibAngle * .pi / 180)
        b.useRoll = model.settings.rollRotatesNib
        b.add(sample)
        builder = b
        strokeStart = Date().timeIntervalSinceReferenceDate
        activeStroke = ActiveStroke(page: page, brush: brush, color: b.color, width: b.width, seed: b.seed,
                                    points: b.preview(predicted: []), startTime: strokeStart)
        refreshLoop()
        setNeedsRender()
    }

    func demoPenMoved(_ samples: [InputSample]) {
        guard var b = builder, var active = activeStroke else { return }
        for s in samples {
            b.add(s)
        }
        builder = b
        active.points = b.preview(predicted: [])
        activeStroke = active
        if DemoStage.shared.holds, let last = samples.last {
            demoTrackHold(demoWindowPoint(page: active.page, last.location))
        }
        setNeedsRender()
    }

    func demoPenUp(_ samples: [InputSample]) {
        cancelHold()
        guard var b = builder, let active = activeStroke else { return }
        for s in samples {
            b.add(s)
        }
        let points = b.finish()
        builder = nil
        activeStroke = nil
        if !points.isEmpty {
            let now = Date().timeIntervalSinceReferenceDate
            let stroke = Stroke(brush: active.brush, color: active.color, width: active.width,
                                birth: now, seed: active.seed, points: points,
                                duration: max(0, now - active.startTime))
            model.addStroke(stroke, toPage: active.page)
            // As a lifted pencil does (touchEnded): a held text-pen drawing stays a drawing, a snapped
            // shape keeps its handles, and a recognized drawing offers its pictures.
            let isSymbol = b.editable != nil || pendingSketch != nil || snappedTitle != nil
            if gestureTool == .textPen && !isSymbol {
                model.queueTextStroke(stroke.id, page: active.page)
            } else if let shape = b.editable {
                model.startShapeEdit(page: active.page, strokeID: stroke.id, shape: shape)
            }
            if let sketch = pendingSketch, let tip = points.last {
                let ids = sketch.others.union([stroke.id])
                var box = CGRect.null
                for s in model.strokes(on: active.page) where ids.contains(s.id) {
                    box = box.union(CGRect(ink: s.bounds))
                }
                let o = pageOrigin(active.page)
                let location = zoomContainer.convert(CGPoint(x: o.x + CGFloat(tip.x), y: o.y + CGFloat(tip.y)), to: self)
                if !box.isNull {
                    model.suggestion = SketchSuggestion(kind: sketch.kind, alternate: sketch.alternate, page: active.page,
                                                        strokeIDs: ids, bounds: box, location: location)
                }
            }
        }
        pendingSketch = nil
        endGestureState()
    }

    /// The pencil resting in a recording: the same wait as a resting pencil (trackHold), with the
    /// window point of the scripted pencil instead of a touch.
    private func demoTrackHold(_ point: CGPoint) {
        guard model.settings.straightLine, let b = builder, !b.isStraight, pendingSketch == nil else { return }
        if let anchor = holdAnchor, hypot(point.x - anchor.x, point.y - anchor.y) < 4 {
            return
        }
        holdAnchor = point
        holdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.demoHoldFired()
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    /// holdFired without its touch: a recognized drawing waits for the lift with its pictures,
    /// anything else that looks like a shape becomes one.
    private func demoHoldFired() {
        guard var b = builder, var active = activeStroke else { return }
        let path = b.drawnPath
        if model.settings.sketchSuggestions, let sketch = recognizeSketch(path, page: active.page) {
            pendingSketch = sketch
            showHint(Loc.t("{0} · kaldırınca seçenekler", "\(sketch.kind.title)"), near: path.last, page: active.page)
            return
        }
        guard let title = b.snapToShape() else { return }
        builder = b
        active.points = b.preview(predicted: [])
        activeStroke = active
        snappedTitle = title
        showHint(b.shapeAdjustment == nil ? title : Loc.t("{0} · kalemi kaydır: boyut ve yön", "\(title)"), near: path.last, page: active.page)
        setNeedsRender()
    }

    /// Where a page point is in the window, for the recording's pen track.
    func demoWindowPoint(page: Int, _ point: CGPoint) -> CGPoint {
        let o = pageOrigin(page)
        return zoomContainer.convert(CGPoint(x: o.x + point.x, y: o.y + point.y), to: nil)
    }
}
#endif

import Foundation

/// One Apple Pencil / finger sample in page-local coordinates.
struct InputSample {
    var location: CGPoint
    /// UITouch.force (1.0 = average press). 0 when the device reports no force.
    var force: CGFloat
    var timestamp: TimeInterval
    /// Radians: π/2 = upright, close to 0 = lying flat. π/2 for fingers.
    var altitude: CGFloat = .pi / 2
    /// Radians in page space, the direction the pencil's barrel points to.
    var azimuth: CGFloat = 0
    /// Barrel roll of Apple Pencil Pro in radians. 0 on other pencils.
    var roll: CGFloat = 0
    var isPencil = false
    /// UITouch.estimationUpdateIndex while force is still an estimate.
    var estimationIndex: Int?
}

/// Turns raw touch samples into a smoothed, decimated stroke.
struct StrokeBuilder {
    let brush: Brush
    let color: InkColor
    let width: Float
    let seed: Float
    /// Calligraphy nib angle in radians (page space).
    var nibAngle: Float = 0.66
    /// Add Apple Pencil Pro's barrel roll to the nib angle.
    var useRoll = true

    private(set) var points: [InkPoint] = []
    /// Hold-to-shape turned the stroke into a line or another clean shape.
    private(set) var isStraight = false
    /// A recognized shape other than a line: the pencil now resizes and turns it.
    private var isFrozen = false
    private var shapeBase: [CGPoint] = []
    private var shapeAnchor = CGPoint.zero
    private var shapeGrab = CGPoint.zero
    private var shapeRadius: Float = 1
    private var shapeInk: Float = 1
    private var adjusting = false
    /// Current resize (1 = as recognized) and turn in degrees, for the label next to the pencil.
    private(set) var shapeAdjustment: (scale: CGFloat, degrees: Int)?
    /// The recognized shape with its corners, kept in step with the pencil so its handles can be
    /// shown once the pencil lifts. nil for freehand strokes, arcs and parabolas.
    private(set) var editable: EditableShape?
    private var editableBase: EditableShape?
    private var straightStart: InkPoint?
    private var smoothed: SIMD2<Float>?
    private var lastRaw: SIMD2<Float>?
    private var lastCommitted: SIMD2<Float>?
    private var lastTime: TimeInterval = 0
    private var lastRadius: Float
    private var inkLevel: Float = 1
    private var lastSample: InputSample?
    private var direction = SIMD2<Float>(1, 0)
    /// estimationUpdateIndex → index of the point that used the estimated force.
    private var pendingEstimates: [Int: Int] = [:]

    init(brush: Brush, color: InkColor, width: Float, seed: Float) {
        self.brush = brush
        self.color = color
        self.width = width
        self.seed = seed
        lastRadius = width * 0.5
    }

    /// Latest raw pencil position (page space).
    var tip: SIMD2<Float>? { lastRaw }

    /// Pressure part of the radius.
    func radius(for force: CGFloat) -> Float {
        let base = width * 0.5
        let s = brush.pressureSensitivity
        guard s > 0 else { return base }
        let f: Float = force > 0 ? Float(force) : 1
        let pn = clampf(f, 0.05, 3)
        return base * ((1 - s) + s * pn.squareRoot())
    }

    /// Nib angle for this sample (calligraphy).
    func nib(roll: CGFloat) -> Float {
        nibAngle + (useRoll ? Float(roll) : 0)
    }

    /// 0 when the pencil is upright, 1 when it lies flat on the glass.
    private func tilt(_ s: InputSample) -> Float {
        guard s.isPencil else { return 0 }
        return clampf(1 - Float(s.altitude) / (Float.pi / 2), 0, 1)
    }

    private func calligraphyRadius(base: Float, dir: SIMD2<Float>, roll: CGFloat) -> Float {
        let a = nib(roll: roll)
        let edge = SIMD2<Float>(cos(a), sin(a))
        // Moving along the nib edge leaves a hairline, moving across it the full width.
        let cross = abs(dir.x * edge.y - dir.y * edge.x)
        return base * (0.16 + 0.84 * cross)
    }

    private func targetRadius(_ s: InputSample) -> Float {
        var r = radius(for: s.force)
        switch brush {
        case .pencil:
            // Tilting the pencil shades with the side of the lead.
            let t = tilt(s)
            r *= 1 + 3.2 * t * t
        case .watercolor:
            r *= 1 + 0.8 * tilt(s)
        case .calligraphy:
            r = calligraphyRadius(base: r, dir: direction, roll: s.roll)
        case .fountain:
            // Pressing harder spreads the nib's tines: the width follows pressure closely
            // and downstrokes come out fuller, like a flexible fountain-pen nib.
            let f: Float = s.force > 0 ? Float(s.force) : 1
            let pn = clampf(f, 0.05, 3.5)
            let spread: Float = 0.22 + 0.78 * pow(pn, 0.85)
            let downstroke: Float = 0.82 + 0.25 * max(0, direction.y)
            r = width * 0.5 * spread * downstroke
        default:
            break
        }
        return r
    }

    /// Per-point "ink": pooling for wet ink, graphite density for the pencil.
    private func inkValue(_ s: InputSample) -> Float {
        guard brush == .pencil else { return inkLevel }
        let f: Float = s.force > 0 ? Float(s.force) : 1
        let pressure = clampf(0.35 + 0.4 * f, 0.25, 1)
        return clampf(pressure * (1 - 0.55 * tilt(s)), 0.12, 1)
    }

    private var tipInk: Float {
        brush == .pencil ? (points.last?.ink ?? 0.7) : inkLevel
    }

    private mutating func remember(_ s: InputSample, index: Int) {
        guard let e = s.estimationIndex else { return }
        if pendingEstimates.count > 256 { pendingEstimates.removeAll() }
        pendingEstimates[e] = index
    }

    mutating func add(_ sample: InputSample) {
        let raw = SIMD2<Float>(Float(sample.location.x), Float(sample.location.y))
        guard raw.x.isFinite, raw.y.isFinite else { return }
        lastRaw = raw
        lastSample = sample
        if isStraight {
            if isFrozen {
                adjustShape(to: raw)
            } else {
                updateLine(to: raw)
            }
            return
        }
        guard let prev = smoothed, let last = lastCommitted else {
            smoothed = raw
            lastCommitted = raw
            lastTime = sample.timestamp
            let r = targetRadius(sample)
            lastRadius = r
            points.append(InkPoint(x: raw.x, y: raw.y, r: r, ink: brush == .pencil ? inkValue(sample) : 1))
            remember(sample, index: 0)
            return
        }
        let s = prev + (raw - prev) * 0.62
        smoothed = s
        let delta = s - last
        let dist = vlength(delta)
        if dist > 0.05 {
            var d = delta / dist
            if vdot(d, direction) < 0 && brush == .calligraphy { d = -d }
            let blended = direction * 0.55 + d * 0.45
            let l = vlength(blended)
            direction = l > 1e-4 ? blended / l : d
        }
        let r = targetRadius(sample)
        let rr = lastRadius + (r - lastRadius) * 0.5
        let spacing = max(0.6, rr * 0.4)
        guard dist >= spacing else { return }
        let dt = max(sample.timestamp - lastTime, 1.0 / 480.0)
        let speed = dist / Float(dt)
        let target = clampf(1 - speed / 700, 0.05, 1)
        inkLevel = inkLevel * 0.8 + target * 0.2
        points.append(InkPoint(x: s.x, y: s.y, r: rr, ink: inkValue(sample)))
        remember(sample, index: points.count - 1)
        lastCommitted = s
        lastTime = sample.timestamp
        lastRadius = rr
    }

    /// Apple Pencil reports the final force a moment later; refine the point that used the estimate.
    mutating func refine(estimationIndex: Int, force: CGFloat, altitude: CGFloat) {
        guard !isStraight, let i = pendingEstimates.removeValue(forKey: estimationIndex), points.indices.contains(i),
              var s = lastSample else { return }
        s.force = force
        s.altitude = altitude
        let r = targetRadius(s)
        points[i].r = (points[i].r + r) * 0.5
        if brush == .pencil {
            points[i].ink = inkValue(s)
        }
    }

    /// Hold-to-straighten: the stroke becomes a line from its start to the pencil, which can still move.
    mutating func snapToLine() -> Bool {
        guard !isStraight, let first = points.first, let end = lastRaw, vlength(end - first.position) > 6 else { return false }
        let n = Float(points.count)
        let avgR = points.reduce(Float(0)) { $0 + $1.r } / n
        let avgInk = points.reduce(Float(0)) { $0 + $1.ink } / n
        straightStart = InkPoint(x: first.x, y: first.y, r: avgR, ink: avgInk)
        isStraight = true
        pendingEstimates.removeAll()
        updateLine(to: end)
        return true
    }

    /// What the pencil has drawn so far, tip included (page space).
    var drawnPath: [CGPoint] {
        var out = points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        if let raw = lastRaw, let last = lastCommitted, vlength(raw - last) > 0.05 {
            out.append(CGPoint(x: CGFloat(raw.x), y: CGFloat(raw.y)))
        }
        return out
    }

    /// Hold-to-shape: a line keeps following the pencil; a circle, ellipse, parabola, arc, rectangle
    /// or polygon replaces the stroke in the same ink. Returns the shape's name.
    mutating func snapToShape() -> String? {
        guard !isStraight, let shape = ShapeRecognizer.recognize(drawnPath) else { return nil }
        if shape.kind == .line {
            return snapToLine() ? shape.title : nil
        }
        apply(path: shape.path)
        guard isFrozen else { return nil }
        shapeBase = shape.path
        editableBase = EditableShape(match: shape)
        editable = editableBase
        let box = Geo.bounds(shape.path)
        shapeAnchor = shape.isClosed ? CGPoint(x: box.midX, y: box.midY) : shape.path[0]
        if let tip = lastRaw {
            shapeGrab = CGPoint(x: CGFloat(tip.x), y: CGFloat(tip.y))
        }
        adjusting = false
        shapeAdjustment = (scale: 1, degrees: 0)
        return shape.title
    }

    /// Replaces the stroke with `path`, keeping its average width and ink.
    mutating func apply(path: [CGPoint]) {
        guard path.count >= 2, !points.isEmpty else { return }
        let n = Float(points.count)
        shapeRadius = points.reduce(Float(0)) { $0 + $1.r } / n
        shapeInk = points.reduce(Float(0)) { $0 + $1.ink } / n
        place(path)
        isStraight = true
        isFrozen = true
        pendingEstimates.removeAll()
    }

    /// Ink points along `path` with the stroke's width and ink (calligraphy follows the direction).
    private mutating func place(_ path: [CGPoint]) {
        // Corners stay points of the stroke, so a square keeps square corners in every ink.
        let dense = Geo.densify(path, spacing: CGFloat(max(1.5, shapeRadius * 0.7)))
        var out: [InkPoint] = []
        out.reserveCapacity(dense.count)
        for (i, p) in dense.enumerated() {
            var r = shapeRadius
            if brush == .calligraphy {
                let a = dense[max(i - 1, 0)]
                let b = dense[min(i + 1, dense.count - 1)]
                let d = SIMD2<Float>(Float(b.x - a.x), Float(b.y - a.y))
                let len = vlength(d)
                if len > 0.01 {
                    r = calligraphyRadius(base: width * 0.5, dir: d / len, roll: lastSample?.roll ?? 0)
                }
            }
            out.append(InkPoint(x: Float(p.x), y: Float(p.y), r: r, ink: shapeInk))
        }
        points = out
        if let last = out.last {
            smoothed = last.position
            lastCommitted = last.position
            lastRadius = last.r
        }
    }

    /// After the snap the pencil keeps control: moving away from the center grows the shape,
    /// moving round it turns it (in 15° clicks near round angles).
    private mutating func adjustShape(to raw: SIMD2<Float>) {
        guard !shapeBase.isEmpty else { return }
        let tip = CGPoint(x: CGFloat(raw.x), y: CGFloat(raw.y))
        if !adjusting {
            // A tiny wobble while lifting the pencil changes nothing.
            guard Geo.dist(tip, shapeGrab) > 6 else { return }
            adjusting = true
        }
        let v0 = CGPoint(x: shapeGrab.x - shapeAnchor.x, y: shapeGrab.y - shapeAnchor.y)
        let v1 = CGPoint(x: tip.x - shapeAnchor.x, y: tip.y - shapeAnchor.y)
        let l0: CGFloat = max(hypot(v0.x, v0.y), 8)
        let scale: CGFloat = min(max(hypot(v1.x, v1.y) / l0, 0.15), 8)
        var angle: CGFloat = Geo.wrap(atan2(v1.y, v1.x) - atan2(v0.y, v0.x))
        let step = CGFloat.pi / 12
        let nearest = (angle / step).rounded() * step
        if abs(angle - nearest) < 4 * .pi / 180 { angle = nearest }
        let c = cos(angle)
        let s = sin(angle)
        let moved = shapeBase.map { p -> CGPoint in
            let x = (p.x - shapeAnchor.x) * scale
            let y = (p.y - shapeAnchor.y) * scale
            return CGPoint(x: shapeAnchor.x + x * c - y * s, y: shapeAnchor.y + x * s + y * c)
        }
        place(moved)
        let degrees = Int((angle * 180 / CGFloat.pi).rounded())
        shapeAdjustment = (scale: scale, degrees: degrees)
        editable = editableBase?.transformed(anchor: shapeAnchor, scale: scale, angle: angle)
    }

    private mutating func updateLine(to end: SIMD2<Float>) {
        guard let start = straightStart else { return }
        var r = start.r
        if brush == .calligraphy {
            let d = end - start.position
            let len = vlength(d)
            if len > 0.5 {
                r = calligraphyRadius(base: width * 0.5, dir: d / len, roll: lastSample?.roll ?? 0)
            }
        }
        points = [InkPoint(x: start.x, y: start.y, r: r, ink: start.ink),
                  InkPoint(x: end.x, y: end.y, r: r, ink: start.ink)]
        smoothed = end
        lastCommitted = end
        lastRadius = r
        editable = EditableShape(kind: .polyline,
                                 points: [CGPoint(x: CGFloat(start.x), y: CGFloat(start.y)), CGPoint(x: CGFloat(end.x), y: CGFloat(end.y))],
                                 title: Loc.t("Doğru"))
    }

    /// Committed points plus the live tip and predicted samples, for drawing while the pencil moves.
    func preview(predicted: [InputSample]) -> [InkPoint] {
        var out = points
        if isStraight { return out }
        let ink = tipInk
        if let raw = lastRaw, let last = lastCommitted, vlength(raw - last) > 0.05 {
            out.append(InkPoint(x: raw.x, y: raw.y, r: lastRadius, ink: ink))
        }
        for p in predicted {
            let x = Float(p.location.x)
            let y = Float(p.location.y)
            guard x.isFinite, y.isFinite else { continue }
            out.append(InkPoint(x: x, y: y, r: lastRadius, ink: ink))
        }
        return out
    }

    /// Final point list. Returns an empty array when nothing was drawn.
    mutating func finish() -> [InkPoint] {
        if !isStraight, let raw = lastRaw, let last = lastCommitted, vlength(raw - last) > 0.1 {
            points.append(InkPoint(x: raw.x, y: raw.y, r: lastRadius, ink: brush == .pencil ? tipInk : min(1, inkLevel + 0.25)))
        }
        if brush == .wet || brush == .fountain, let i = points.indices.last {
            points[i].ink = min(1, points[i].ink + 0.35)
        }
        return points
    }
}

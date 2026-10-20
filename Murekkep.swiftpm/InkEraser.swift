import Foundation

enum EraserMode: String, CaseIterable, Identifiable {
    case stroke
    case partial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stroke: return Loc.t("Tüm çizgi")
        case .partial: return Loc.t("Kısmi")
        }
    }
}

enum InkEraser {
    static func distance(point p: SIMD2<Float>, segmentA a: SIMD2<Float>, b: SIMD2<Float>) -> Float {
        let ab = b - a
        let l2 = vdot(ab, ab)
        if l2 <= 1e-10 { return vlength(p - a) }
        let t = clampf(vdot(p - a, ab) / l2, 0, 1)
        return vlength(p - (a + ab * t))
    }

    /// Minimum distance between segments p1-q1 and p2-q2.
    static func distance(segment p1: SIMD2<Float>, _ q1: SIMD2<Float>, segment p2: SIMD2<Float>, _ q2: SIMD2<Float>) -> Float {
        let d1 = q1 - p1
        let d2 = q2 - p2
        let r = p1 - p2
        let a = vdot(d1, d1)
        let e = vdot(d2, d2)
        let f = vdot(d2, r)
        let eps: Float = 1e-10
        var s: Float = 0
        var t: Float = 0
        if a <= eps && e <= eps {
            return vlength(p1 - p2)
        }
        if a <= eps {
            t = clampf(f / e, 0, 1)
        } else {
            let c = vdot(d1, r)
            if e <= eps {
                s = clampf(-c / a, 0, 1)
            } else {
                let b = vdot(d1, d2)
                let denom = a * e - b * b
                s = denom > eps ? clampf((b * f - c * e) / denom, 0, 1) : 0
                t = (b * s + f) / e
                if t < 0 {
                    t = 0
                    s = clampf(-c / a, 0, 1)
                } else if t > 1 {
                    t = 1
                    s = clampf((b - c) / a, 0, 1)
                }
            }
        }
        let c1 = p1 + d1 * s
        let c2 = p2 + d2 * t
        return vlength(c1 - c2)
    }

    /// True when the eraser path a→b (with radius) touches the stroke.
    static func hits(_ s: Stroke, from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float) -> Bool {
        let box = InkRect(a, b).expanded(by: radius + s.maxRadius)
        guard s.bounds.intersects(box) else { return false }
        let pts = s.points
        guard let first = pts.first else { return false }
        if pts.count == 1 {
            return distance(point: first.position, segmentA: a, b: b) <= radius + first.r
        }
        for i in 0..<(pts.count - 1) {
            let p = pts[i]
            let q = pts[i + 1]
            let d = distance(segment: p.position, q.position, segment: a, b)
            if d <= radius + max(p.r, q.r) * 0.8 { return true }
        }
        return false
    }

    /// Removes the parts of the stroke under the eraser path.
    /// Returns nil when the stroke is untouched, otherwise the remaining pieces (possibly none).
    static func erase(_ s: Stroke, from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float) -> [Stroke]? {
        let box = InkRect(a, b).expanded(by: radius + s.maxRadius)
        guard s.bounds.intersects(box) else { return nil }
        let dense = densify(s.points, maxSpacing: max(0.5, radius * 0.35))
        var pieces: [[InkPoint]] = []
        var current: [InkPoint] = []
        var touched = false
        for p in dense {
            if distance(point: p.position, segmentA: a, b: b) <= radius + p.r * 0.5 {
                touched = true
                if current.count >= 2 { pieces.append(current) }
                current = []
            } else {
                current.append(p)
            }
        }
        guard touched else { return nil }
        if current.count >= 2 { pieces.append(current) }
        return pieces.map { s.withPoints($0) }
    }

    static func densify(_ pts: [InkPoint], maxSpacing: Float) -> [InkPoint] {
        guard pts.count >= 2, maxSpacing > 0 else { return pts }
        var out: [InkPoint] = []
        out.reserveCapacity(pts.count)
        for i in 0..<(pts.count - 1) {
            let p = pts[i]
            let q = pts[i + 1]
            out.append(p)
            let len = vlength(q.position - p.position)
            let n = min(Int(len / maxSpacing), 2000)
            if n >= 1 {
                for k in 1...n {
                    let t = Float(k) / Float(n + 1)
                    out.append(InkPoint(x: p.x + (q.x - p.x) * t,
                                        y: p.y + (q.y - p.y) * t,
                                        r: p.r + (q.r - p.r) * t,
                                        ink: p.ink + (q.ink - p.ink) * t))
                }
            }
        }
        if let last = pts.last { out.append(last) }
        return out
    }
}

import Foundation

/// One vertex of a stroke ribbon (layout must match `RibbonVertexGPU` in InkShaders.swift).
struct RibbonVertexGPU {
    var center: SIMD2<Float>
    var offset: SIMD2<Float>
    var tangent: SIMD2<Float>
    var r: Float
    var u: Float
    var side: Float
    var arc: Float
    var ink: Float
    var stroke: UInt32
}

/// Turns a stroke into one continuous triangle mesh: a smoothed centerline, a strip along it
/// and round caps at both ends. Because the across and along coordinates are interpolated over a
/// single surface, shading has no seams at turns and every pixel of the stroke is covered once.
enum RibbonBuilder {
    /// Segments per half circle of a cap.
    private static let capSegments = 10
    /// Largest direction change between neighbouring vertex rows; quicker turns get a fan of rows.
    private static let maxJoinTurn: Float = 0.15

    /// `relax` lets thick ink bend smoothly through sharp corners (see `relaxed`).
    static func append(_ pts: [InkPoint], stroke: UInt32, relax: Bool = false,
                       vertices: inout [RibbonVertexGPU], indices: inout [UInt32]) {
        guard !pts.isEmpty else { return }
        let samples = smoothed(relax ? relaxed(pts) : pts)
        let n = samples.count
        var arcs = [Float](repeating: 0, count: n)
        if n > 1 {
            for i in 1..<n {
                arcs[i] = arcs[i - 1] + vlength(samples[i].position - samples[i - 1].position)
            }
        }
        // A dot: a full disc made of two caps.
        if n == 1 || arcs[n - 1] < 1e-3 {
            let p = samples[0]
            let t = SIMD2<Float>(1, 0)
            appendCap(p, arc: 0, tangent: t, forward: true, stroke: stroke, vertices: &vertices, indices: &indices)
            appendCap(p, arc: 0, tangent: t, forward: false, stroke: stroke, vertices: &vertices, indices: &indices)
            return
        }

        // Central-difference tangents; a zero-length step keeps the previous direction.
        var tangents = [SIMD2<Float>](repeating: SIMD2<Float>(1, 0), count: n)
        var last = SIMD2<Float>(1, 0)
        var foundFirst = false
        for i in 0..<n {
            let a = samples[max(i - 1, 0)].position
            let b = samples[min(i + 1, n - 1)].position
            let d = b - a
            let l = vlength(d)
            if l > 1e-5 {
                last = d / l
                if !foundFirst {
                    foundFirst = true
                    for j in 0..<i { tangents[j] = last }
                }
            }
            tangents[i] = last
        }

        // One row per sample: left edge, centerline, right edge. Each half of the ribbon is then a
        // clean strip, so even rows that share a center (round joins) never overlap each other.
        let base = UInt32(vertices.count)
        var rows = 0
        vertices.reserveCapacity(vertices.count + n * 3 + (capSegments + 2) * 2)
        for i in 0..<n {
            if i > 0 {
                let a = tangents[i - 1]
                let b = tangents[i]
                let turn = atan2(a.x * b.y - a.y * b.x, vdot(a, b))
                let extra = min(Int((abs(turn) / maxJoinTurn).rounded(.up)) - 1, 24)
                if extra > 0 {
                    let start = atan2(a.y, a.x)
                    let p = samples[i - 1]
                    let q = samples[i]
                    for j in 1...extra {
                        let f = Float(j) / Float(extra + 1)
                        let angle = start + turn * f
                        let mid = InkPoint(x: p.position.x + (q.position.x - p.position.x) * f,
                                           y: p.position.y + (q.position.y - p.position.y) * f,
                                           r: p.r + (q.r - p.r) * f,
                                           ink: p.ink + (q.ink - p.ink) * f)
                        appendRow(mid, tangent: SIMD2<Float>(cos(angle), sin(angle)),
                                  arc: arcs[i - 1] + (arcs[i] - arcs[i - 1]) * f, stroke: stroke, vertices: &vertices)
                        rows += 1
                    }
                }
            }
            appendRow(samples[i], tangent: tangents[i], arc: arcs[i], stroke: stroke, vertices: &vertices)
            rows += 1
        }
        indices.reserveCapacity(indices.count + (rows - 1) * 12 + capSegments * 6)
        for i in 0..<(rows - 1) {
            let l0 = base + UInt32(i * 3)
            let c0 = l0 + 1
            let r0 = l0 + 2
            let l1 = l0 + 3
            let c1 = l0 + 4
            let r1 = l0 + 5
            indices.append(contentsOf: [c0, l0, l1, c0, l1, c1, c0, r1, r0, c0, c1, r1])
        }
        appendCap(samples[0], arc: arcs[0], tangent: tangents[0], forward: false,
                  stroke: stroke, vertices: &vertices, indices: &indices)
        appendCap(samples[n - 1], arc: arcs[n - 1], tangent: tangents[n - 1], forward: true,
                  stroke: stroke, vertices: &vertices, indices: &indices)
    }

    private static func appendRow(_ p: InkPoint, tangent t: SIMD2<Float>, arc: Float, stroke: UInt32,
                                  vertices: inout [RibbonVertexGPU]) {
        let nrm = SIMD2<Float>(-t.y, t.x)
        vertices.append(RibbonVertexGPU(center: p.position, offset: nrm, tangent: t, r: p.r,
                                        u: 1, side: 1, arc: arc, ink: p.ink, stroke: stroke))
        vertices.append(RibbonVertexGPU(center: p.position, offset: .zero, tangent: t, r: p.r,
                                        u: 0, side: 0, arc: arc, ink: p.ink, stroke: stroke))
        vertices.append(RibbonVertexGPU(center: p.position, offset: -nrm, tangent: t, r: p.r,
                                        u: -1, side: -1, arc: arc, ink: p.ink, stroke: stroke))
    }

    /// Half disc around `p`, from the left edge through the stroke's end direction to the right edge.
    private static func appendCap(_ p: InkPoint, arc: Float, tangent t: SIMD2<Float>, forward: Bool, stroke: UInt32,
                                  vertices: inout [RibbonVertexGPU], indices: inout [UInt32]) {
        let nrm = SIMD2<Float>(-t.y, t.x)
        let dir = forward ? t : -t
        let center = UInt32(vertices.count)
        vertices.append(RibbonVertexGPU(center: p.position, offset: .zero, tangent: t, r: p.r,
                                        u: 0, side: 0, arc: arc, ink: p.ink, stroke: stroke))
        for j in 0...capSegments {
            let a = Float(j) / Float(capSegments) * Float.pi
            let c = cos(a)
            let s = sin(a)
            let offset = nrm * c + dir * s
            // The vertex shader extends `arc` into the cap by the rim's distance along the tangent.
            vertices.append(RibbonVertexGPU(center: p.position, offset: offset, tangent: t, r: p.r,
                                            u: 1, side: c, arc: arc, ink: p.ink, stroke: stroke))
        }
        for j in 0..<capSegments {
            let a = center + 1 + UInt32(j)
            indices.append(contentsOf: [center, a, a + 1])
        }
    }

    /// Gaussian smoothing along the stroke with a width that grows with the ink radius: a sharp corner
    /// becomes a bend about as tight as the ink is thick, like real ink pulled smooth by surface tension,
    /// so raised 3D ink shows no crease where the pen turned. Thin lines keep their shape, and the
    /// window shrinks towards the ends so the first and last points stay where they were drawn.
    static func relaxed(_ pts: [InkPoint]) -> [InkPoint] {
        let n = pts.count
        guard n > 2 else { return pts }
        var arc = [Float](repeating: 0, count: n)
        for i in 1..<n {
            arc[i] = arc[i - 1] + vlength(pts[i].position - pts[i - 1].position)
        }
        var out = pts
        var lo = 0
        var hi = 0
        for i in 0..<n {
            let r = pts[i].r
            let t = clampf((r - 1.5) / 2.5, 0, 1)
            let sigma = max(r * (0.35 + 0.55 * t * t * (3 - 2 * t)), 0.3)
            let reach = min(2.5 * sigma, arc[i], arc[n - 1] - arc[i])
            while arc[i] - arc[lo] > reach { lo += 1 }
            while lo > 0 && arc[i] - arc[lo - 1] <= reach { lo -= 1 }
            hi = max(hi, i)
            while hi + 1 < n && arc[hi + 1] - arc[i] <= reach { hi += 1 }
            while hi > i && arc[hi] - arc[i] > reach { hi -= 1 }
            var sum = SIMD2<Float>(0, 0)
            var weight: Float = 0
            for j in lo...hi {
                let dd = arc[j] - arc[i]
                let ds = (arc[min(j + 1, n - 1)] - arc[max(j - 1, 0)]) * 0.5 + 1e-4
                let w = exp(-0.5 * dd * dd / (sigma * sigma)) * ds
                sum += pts[j].position * w
                weight += w
            }
            guard weight > 0 else { continue }
            let p = sum / weight
            guard p.x.isFinite, p.y.isFinite else { continue }
            out[i] = InkPoint(x: p.x, y: p.y, r: pts[i].r, ink: pts[i].ink)
        }
        return out
    }

    /// Catmull-Rom through the input points: long gaps and sharp turns get extra samples so the
    /// ribbon follows a smooth curve instead of a polyline.
    static func smoothed(_ pts: [InkPoint]) -> [InkPoint] {
        let n = pts.count
        guard n > 2 else { return pts }
        var out: [InkPoint] = [pts[0]]
        out.reserveCapacity(n * 2)
        for i in 0..<(n - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, n - 1)]
            let seg = p2.position - p1.position
            let len = vlength(seg)
            if len < 1e-4 { continue }
            let step = max(0.5, min(p1.r, p2.r) * 0.45)
            var m = Int((len / step).rounded(.up))
            // Extra samples where the direction changes quickly.
            let turn = max(angle(p1.position - p0.position, seg), angle(seg, p3.position - p2.position))
            m = max(m, Int((turn / 0.3).rounded(.up)))
            m = min(max(m, 1), 32)
            for k in 1...m {
                let t = Float(k) / Float(m)
                let pos = catmullRom(p0.position, p1.position, p2.position, p3.position, t)
                guard pos.x.isFinite, pos.y.isFinite else { continue }
                out.append(InkPoint(x: pos.x, y: pos.y,
                                    r: p1.r + (p2.r - p1.r) * t,
                                    ink: p1.ink + (p2.ink - p1.ink) * t))
            }
        }
        return out
    }

    private static func angle(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let la = vlength(a)
        let lb = vlength(b)
        guard la > 1e-5, lb > 1e-5 else { return 0 }
        return acos(clampf(vdot(a, b) / (la * lb), -1, 1))
    }

    private static func catmullRom(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>,
                                   _ t: Float) -> SIMD2<Float> {
        let t2 = t * t
        let t3 = t2 * t
        let a = p1 * 2
        let b = (p2 - p0) * t
        let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
        let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
        return (a + b + c + d) * 0.5
    }
}

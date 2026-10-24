import Foundation

/// One blade of grass (or a flower stem), in page-local points. Blades grow up the page.
struct GrassBlade {
    var base: SIMD2<Float>
    var height: Float
    var width: Float
    /// Sideways offset of the tip.
    var lean: Float
    var phase: Float
    var stiffness: Float
    var color: SIMD3<Float>
    var isStem: Bool
    /// 0...1 position along the stroke, used to sprout blades in drawing order.
    var arc: Float
}

struct GrassFlower {
    /// Index of the stem in `GrassField.blades`.
    var stem: Int
    var radius: Float
    var petals: Float
    /// 0 daisy (many thin petals), 1 round petals, 2 poppy (wide, cupped).
    var style: Float
    var spin: Float
    var petal: SIMD3<Float>
    var core: SIMD3<Float>
    /// Seconds after the stroke ends when the bud starts to open.
    var delay: Float
}

struct GrassField {
    var blades: [GrassBlade] = []
    var flowers: [GrassFlower] = []
}

/// Deterministic grass for a stroke: the same stroke always grows the same blades and flowers,
/// so it looks identical after reopening the note, in PDF export and on screen.
enum GrassGenerator {
    /// The flower level travels inside the stroke seed (integer part), so no file format change is needed.
    static func flowerLevel(seed: Float) -> Int {
        Int(max(0, min(2, seed.rounded(.down))))
    }

    static func seed(level: Int, random: Float) -> Float {
        Float(max(0, min(2, level))) + min(max(random, 0), 0.999)
    }

    private struct FlowerKind {
        let petal: SIMD3<Float>
        let core: SIMD3<Float>
        let style: Float
        let petals: ClosedRange<Int>
        let scale: Float
    }

    private static let kinds: [FlowerKind] = [
        FlowerKind(petal: SIMD3(0.98, 0.97, 0.93), core: SIMD3(0.98, 0.76, 0.12), style: 0, petals: 12...16, scale: 1.1),
        FlowerKind(petal: SIMD3(0.97, 0.52, 0.70), core: SIMD3(1.00, 0.88, 0.35), style: 1, petals: 5...5, scale: 1.0),
        FlowerKind(petal: SIMD3(0.70, 0.56, 0.95), core: SIMD3(1.00, 0.92, 0.45), style: 1, petals: 5...6, scale: 0.95),
        FlowerKind(petal: SIMD3(1.00, 0.83, 0.12), core: SIMD3(0.92, 0.52, 0.08), style: 1, petals: 5...5, scale: 0.9),
        FlowerKind(petal: SIMD3(0.93, 0.17, 0.13), core: SIMD3(0.12, 0.08, 0.10), style: 2, petals: 4...5, scale: 1.15),
        FlowerKind(petal: SIMD3(0.42, 0.62, 0.98), core: SIMD3(1.00, 0.93, 0.50), style: 1, petals: 5...5, scale: 0.8),
        FlowerKind(petal: SIMD3(1.00, 0.55, 0.14), core: SIMD3(0.42, 0.22, 0.08), style: 2, petals: 6...6, scale: 1.0),
        FlowerKind(petal: SIMD3(0.86, 0.22, 0.62), core: SIMD3(1.00, 0.90, 0.50), style: 0, petals: 10...12, scale: 1.0),
    ]

    /// The flowering water pen's glassy flowers: blue and violet petals around a pale, icy centre.
    private static let crystals: [FlowerKind] = [
        FlowerKind(petal: SIMD3(0.56, 0.66, 1.00), core: SIMD3(0.92, 0.96, 1.00), style: 1, petals: 5...5, scale: 1.0),
        FlowerKind(petal: SIMD3(0.70, 0.62, 1.00), core: SIMD3(0.95, 0.93, 1.00), style: 1, petals: 5...6, scale: 0.9),
        FlowerKind(petal: SIMD3(0.45, 0.72, 0.98), core: SIMD3(0.88, 0.97, 1.00), style: 1, petals: 5...5, scale: 1.1),
        FlowerKind(petal: SIMD3(0.62, 0.55, 0.96), core: SIMD3(0.98, 0.95, 1.00), style: 0, petals: 8...10, scale: 0.85),
    ]

    @inline(__always)
    private static func hash(_ x: UInt32) -> UInt32 {
        var h = x &* 0x9E37_79B1
        h ^= h >> 16
        h = h &* 0x85EB_CA6B
        h ^= h >> 13
        h = h &* 0xC2B2_AE35
        h ^= h >> 16
        return h
    }

    /// Stable random number in [0, 1).
    @inline(__always)
    private static func rand(_ k: Int, _ channel: UInt32, _ salt: UInt32) -> Float {
        let h = hash(UInt32(truncatingIfNeeded: k) &* 7919 &+ channel &* 104_729 &+ salt)
        return Float(h & 0xFF_FFFF) / Float(0x100_0000)
    }

    static func field(points: [InkPoint], width: Float, color: InkColor, seed: Float) -> GrassField {
        let n = points.count
        guard n > 0, width > 0 else { return GrassField() }
        let fraction = seed - seed.rounded(.down)
        let salt = UInt32(truncatingIfNeeded: Int(fraction * 1_000_000)) &+ 17

        var cum = [Float](repeating: 0, count: n)
        for i in 1..<n {
            cum[i] = cum[i - 1] + vlength(points[i].position - points[i - 1].position)
        }
        let total = cum[n - 1]
        let baseR = max(width * 0.5, 0.5)
        let isTuft = total < width
        let spacing = max(0.6, width * 0.12)
        let steps = isTuft ? 7 : min(1600, Int(total / spacing) + 1)

        var seg = 0
        func sample(_ s: Float) -> (p: SIMD2<Float>, r: Float, tangent: SIMD2<Float>) {
            if n == 1 {
                return (points[0].position, points[0].r, SIMD2<Float>(1, 0))
            }
            if s < cum[seg] { seg = 0 }
            while seg < n - 2 && cum[seg + 1] < s {
                seg += 1
            }
            let a = points[seg]
            let b = points[seg + 1]
            let len = cum[seg + 1] - cum[seg]
            let t = len > 1e-5 ? clampf((s - cum[seg]) / len, 0, 1) : 0
            let d = b.position - a.position
            let dl = vlength(d)
            return (a.position + d * t, a.r + (b.r - a.r) * t, dl > 1e-5 ? d / dl : SIMD2<Float>(1, 0))
        }

        let baseColor = SIMD3<Float>(color.r, color.g, color.b)
        let yellow = SIMD3<Float>(0.80, 0.82, 0.30)
        let perStep = width > 22 ? 3 : 2
        var blades: [GrassBlade] = []
        blades.reserveCapacity(steps * perStep + 64)

        for k in 0..<steps {
            let s = isTuft ? total * rand(k, 1, salt) : min(total, (Float(k) + rand(k, 1, salt)) * spacing)
            let (p, r, tangent) = sample(s)
            let normal = SIMD2<Float>(-tangent.y, tangent.x)
            let pressure = clampf(r / baseR, 0.6, 1.5)
            for j in 0..<perStep {
                let key = k * 4 + j
                var base = p + normal * ((rand(key, 2, salt) - 0.5) * 2 * r * 0.7)
                if isTuft {
                    base += tangent * ((rand(key, 9, salt) - 0.5) * 2 * baseR)
                }
                // Short blades keep the letter shapes readable even in small handwriting.
                let height = width * (0.55 + 0.6 * rand(key, 3, salt)) * pressure
                let bladeWidth = max(0.5, width * 0.11) * (0.7 + 0.6 * rand(key, 4, salt))
                let tint = rand(key, 6, salt)
                var c = baseColor * (0.78 + 0.42 * rand(key, 7, salt))
                c += (yellow - c) * (tint * tint * 0.35)
                blades.append(GrassBlade(base: base,
                                         height: height,
                                         width: bladeWidth,
                                         lean: (rand(key, 5, salt) - 0.5) * height * 0.5,
                                         phase: rand(key, 8, salt) * 6.283,
                                         stiffness: rand(key, 10, salt),
                                         color: c,
                                         isStem: false,
                                         arc: total > 0 ? s / total : 0))
            }
        }

        var flowers: [GrassFlower] = []
        let level = flowerLevel(seed: seed)
        if level > 0 {
            let gap = max(width * (level == 2 ? 1.6 : 3.2), 10)
            let count = isTuft ? level : max(1, Int(total / gap))
            for m in 0..<min(count, 400) {
                let key = 50_000 + m
                let s: Float = isTuft ? total * 0.5 : min(total, (Float(m) + 0.25 + 0.5 * rand(key, 11, salt)) * gap)
                let (p, r, tangent) = sample(s)
                let normal = SIMD2<Float>(-tangent.y, tangent.x)
                var base = p + normal * ((rand(key, 12, salt) - 0.5) * r * 1.2)
                if isTuft {
                    base.x += (rand(key, 19, salt) - 0.5) * width
                }
                let stemHeight = width * (1.0 + 0.45 * rand(key, 13, salt))
                blades.append(GrassBlade(base: base,
                                         height: stemHeight,
                                         width: max(0.45, width * 0.07),
                                         lean: (rand(key, 14, salt) - 0.5) * stemHeight * 0.35,
                                         phase: rand(key, 15, salt) * 6.283,
                                         stiffness: rand(key, 16, salt),
                                         color: baseColor * 0.62,
                                         isStem: true,
                                         arc: total > 0 ? s / total : 0))
                let kind = kinds[min(kinds.count - 1, Int(rand(key, 17, salt) * Float(kinds.count)))]
                let petalCount = min(kind.petals.upperBound,
                                     kind.petals.lowerBound + Int(rand(key, 21, salt) * Float(kind.petals.count)))
                flowers.append(GrassFlower(stem: blades.count - 1,
                                           radius: max(1.4, width * (0.32 + 0.16 * rand(key, 18, salt))) * kind.scale,
                                           petals: Float(petalCount),
                                           style: kind.style,
                                           spin: rand(key, 22, salt) * 6.283,
                                           petal: kind.petal,
                                           core: kind.core,
                                           delay: 1.0 + rand(key, 20, salt)))
            }
        }

        return backToFront(blades, flowers)
    }

    /// The stroke's field: grass (with its flowers) for the grass pen, flowers on stems for the
    /// flowering water.
    static func field(for brush: Brush, points: [InkPoint], width: Float, color: InkColor, seed: Float) -> GrassField {
        brush == .bloom ? blooms(points: points, width: width, color: color, seed: seed)
                        : field(points: points, width: width, color: color, seed: seed)
    }

    /// The flowering water pen (as in the ads): no grass, only thin stems rising from the line, each
    /// with a glassy blue or violet flower that opens a moment after the pen lifts.
    static func blooms(points: [InkPoint], width: Float, color: InkColor, seed: Float) -> GrassField {
        let n = points.count
        guard n > 0, width > 0 else { return GrassField() }
        let salt = UInt32(truncatingIfNeeded: Int((seed - seed.rounded(.down)) * 1_000_000)) &+ 29
        var cum = [Float](repeating: 0, count: n)
        for i in 1..<n {
            cum[i] = cum[i - 1] + vlength(points[i].position - points[i - 1].position)
        }
        let total = cum[n - 1]
        func sample(_ s: Float) -> (p: SIMD2<Float>, r: Float, tangent: SIMD2<Float>) {
            guard n > 1 else { return (points[0].position, points[0].r, SIMD2<Float>(1, 0)) }
            var k = 0
            while k < n - 2 && cum[k + 1] < s {
                k += 1
            }
            let a = points[k]
            let b = points[k + 1]
            let len = cum[k + 1] - cum[k]
            let t = len > 1e-5 ? clampf((s - cum[k]) / len, 0, 1) : 0
            let d = b.position - a.position
            let dl = vlength(d)
            return (a.position + d * t, a.r + (b.r - a.r) * t, dl > 1e-5 ? d / dl : SIMD2<Float>(1, 0))
        }

        // A flower every two to three line widths; the stems in the ink's own colour, darker.
        let gap = max(width * 2.4, 12)
        let count = total < gap ? 1 : min(300, Int(total / gap))
        let stemColor = SIMD3<Float>(color.r, color.g, color.b) * 0.72
        var blades: [GrassBlade] = []
        var flowers: [GrassFlower] = []
        for m in 0..<count {
            let key = 70_000 + m
            let s = count == 1 ? total * 0.5 : (Float(m) + 0.2 + 0.6 * rand(key, 1, salt)) * total / Float(count)
            let (p, r, tangent) = sample(s)
            let normal = SIMD2<Float>(-tangent.y, tangent.x)
            var base = p + normal * ((rand(key, 2, salt) - 0.5) * r * 0.6)
            if n == 1 {
                base.x += (rand(key, 3, salt) - 0.5) * width * 0.6
            }
            let stemHeight = width * (1.3 + 0.9 * rand(key, 4, salt))
            blades.append(GrassBlade(base: base,
                                     height: stemHeight,
                                     width: max(0.45, width * 0.06),
                                     lean: (rand(key, 5, salt) - 0.5) * stemHeight * 0.4,
                                     phase: rand(key, 6, salt) * 6.283,
                                     stiffness: rand(key, 7, salt),
                                     color: stemColor,
                                     isStem: true,
                                     arc: total > 0 ? s / total : 0))
            let kind = crystals[min(crystals.count - 1, Int(rand(key, 8, salt) * Float(crystals.count)))]
            let petalCount = min(kind.petals.upperBound,
                                 kind.petals.lowerBound + Int(rand(key, 9, salt) * Float(kind.petals.count)))
            flowers.append(GrassFlower(stem: blades.count - 1,
                                       radius: max(1.6, width * (0.5 + 0.25 * rand(key, 10, salt))) * kind.scale,
                                       petals: Float(petalCount),
                                       style: kind.style,
                                       spin: rand(key, 11, salt) * 6.283,
                                       petal: kind.petal,
                                       core: kind.core,
                                       delay: 0.6 + 0.9 * rand(key, 12, salt)))
        }
        return backToFront(blades, flowers)
    }

    /// Back to front: blades further up the page are behind.
    private static func backToFront(_ blades: [GrassBlade], _ flowers: [GrassFlower]) -> GrassField {
        let order = blades.indices.sorted { blades[$0].base.y < blades[$1].base.y }
        var remap = [Int](repeating: 0, count: blades.count)
        for (newIndex, old) in order.enumerated() {
            remap[old] = newIndex
        }
        var flowers = flowers
        for i in flowers.indices {
            flowers[i].stem = remap[flowers[i].stem]
        }
        return GrassField(blades: order.map { blades[$0] }, flowers: flowers)
    }

    /// Point along a blade, matching `bladeAt` in the shader (s = 0 base, 1 tip).
    static func point(on b: GrassBlade, at s: Float, sway: Float = 0) -> SIMD2<Float> {
        let bend = b.lean + sway * b.height * 0.16
        return b.base + SIMD2<Float>(bend * s * s, -b.height * s)
    }
}

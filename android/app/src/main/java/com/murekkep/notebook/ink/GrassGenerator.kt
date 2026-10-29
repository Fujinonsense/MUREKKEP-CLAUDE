package com.murekkep.notebook.ink

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// Port of Murekkep.swiftpm/GrassGenerator.swift: deterministic grass and flowers for a stroke. The
// same stroke always grows the same blades and flowers, so it looks identical after reopening the
// note, in PDF export and on screen. Every number is the iPad's; the hash is the same, so the two
// editions grow the same field from the same ink.

/** A 3-vector (SIMD3<Float> on iPad), used for colours. */
data class Vec3(val x: Float, val y: Float, val z: Float) {
    operator fun plus(o: Vec3) = Vec3(x + o.x, y + o.y, z + o.z)
    operator fun minus(o: Vec3) = Vec3(x - o.x, y - o.y, z - o.z)
    operator fun times(k: Float) = Vec3(x * k, y * k, z * k)

    /** The smallest component (`.min()` of SIMD3 on iPad). */
    val minComponent: Float get() = min(x, min(y, z))
}

/**
 * What a blade is drawn as (the shader's `BladeGPU.kind`): the grass pen's blades and stems are
 * opaque plants; the flowering water's stems and leaves are translucent glass.
 */
enum class BladeKind(val raw: Int) {
    BLADE(0),
    STEM(1),
    GLASS_STEM(2),
    GLASS_LEAF(3),
}

/** One blade of grass (or a flower stem), in page-local points. Blades grow up the page. */
data class GrassBlade(
    val base: Vec2,
    val height: Float,
    val width: Float,
    /** Sideways offset of the tip. */
    val lean: Float,
    val phase: Float,
    val stiffness: Float,
    val color: Vec3,
    val kind: BladeKind,
    /** 0...1 position along the stroke, used to sprout blades in drawing order. */
    val arc: Float,
) {
    /** A flower sits at the tip of a stem. */
    val isStem: Boolean get() = kind == BladeKind.STEM || kind == BladeKind.GLASS_STEM
}

data class GrassFlower(
    /** Index of the stem in `GrassField.blades`. */
    val stem: Int,
    val radius: Float,
    val petals: Float,
    /**
     * 0 daisy (many thin petals), 1 round petals, 2 poppy (wide, cupped), 3 glass (the flowering
     * water: long translucent petals, pale centre, no pollen).
     */
    val style: Float,
    val spin: Float,
    val petal: Vec3,
    val core: Vec3,
    /** Seconds after the stroke ends when the bud starts to open. */
    val delay: Float,
)

data class GrassField(
    val blades: List<GrassBlade> = emptyList(),
    val flowers: List<GrassFlower> = emptyList(),
)

object GrassGenerator {
    /** The flower level travels inside the stroke seed (integer part), so no file format change is needed. */
    fun flowerLevel(seed: Float): Int = max(0f, min(2f, floor(seed))).toInt()

    fun seed(level: Int, random: Float): Float =
        max(0, min(2, level)).toFloat() + min(max(random, 0f), 0.999f)

    private class FlowerKind(
        val petal: Vec3,
        val core: Vec3,
        val style: Float,
        val petals: IntRange,
        val scale: Float,
    ) {
        /** `ClosedRange<Int>.count` of the iPad. */
        val petalChoices: Int get() = petals.last - petals.first + 1
    }

    private val KINDS: List<FlowerKind> = listOf(
        FlowerKind(Vec3(0.98f, 0.97f, 0.93f), Vec3(0.98f, 0.76f, 0.12f), 0f, 12..16, 1.1f),
        FlowerKind(Vec3(0.97f, 0.52f, 0.70f), Vec3(1.00f, 0.88f, 0.35f), 1f, 5..5, 1.0f),
        FlowerKind(Vec3(0.70f, 0.56f, 0.95f), Vec3(1.00f, 0.92f, 0.45f), 1f, 5..6, 0.95f),
        FlowerKind(Vec3(1.00f, 0.83f, 0.12f), Vec3(0.92f, 0.52f, 0.08f), 1f, 5..5, 0.9f),
        FlowerKind(Vec3(0.93f, 0.17f, 0.13f), Vec3(0.12f, 0.08f, 0.10f), 2f, 4..5, 1.15f),
        FlowerKind(Vec3(0.42f, 0.62f, 0.98f), Vec3(1.00f, 0.93f, 0.50f), 1f, 5..5, 0.8f),
        FlowerKind(Vec3(1.00f, 0.55f, 0.14f), Vec3(0.42f, 0.22f, 0.08f), 2f, 6..6, 1.0f),
        FlowerKind(Vec3(0.86f, 0.22f, 0.62f), Vec3(1.00f, 0.90f, 0.50f), 0f, 10..12, 1.0f),
    )

    /** The flower style the shader draws as glass; only the flowering water uses it. */
    const val GLASS_STYLE = 3f

    /**
     * The flowering water pen's glass flowers (as in the ad): five or six long petals shading from a
     * pale centre (`core`) to periwinkle blue or violet tips (`petal`), in several sizes.
     */
    private val CRYSTALS: List<FlowerKind> = listOf(
        FlowerKind(Vec3(0.46f, 0.56f, 0.99f), Vec3(0.90f, 0.95f, 1.00f), GLASS_STYLE, 5..6, 1.0f),
        FlowerKind(Vec3(0.60f, 0.50f, 0.97f), Vec3(0.94f, 0.92f, 1.00f), GLASS_STYLE, 5..6, 0.9f),
        FlowerKind(Vec3(0.40f, 0.66f, 0.99f), Vec3(0.88f, 0.96f, 1.00f), GLASS_STYLE, 5..5, 1.12f),
        FlowerKind(Vec3(0.56f, 0.58f, 1.00f), Vec3(0.95f, 0.94f, 1.00f), GLASS_STYLE, 6..6, 0.82f),
        FlowerKind(Vec3(0.68f, 0.52f, 0.98f), Vec3(0.96f, 0.92f, 1.00f), GLASS_STYLE, 5..5, 1.0f),
    )

    private fun hash(x: UInt): UInt {
        var h = x * 0x9E3779B1u
        h = h xor (h shr 16)
        h *= 0x85EBCA6Bu
        h = h xor (h shr 13)
        h *= 0xC2B2AE35u
        h = h xor (h shr 16)
        return h
    }

    /** Stable random number in [0, 1). */
    private fun rand(k: Int, channel: UInt, salt: UInt): Float {
        val h = hash(k.toUInt() * 7919u + channel * 104729u + salt)
        return (h and 0xFFFFFFu).toFloat() / 16777216f
    }

    /** vlength of the iPad: sqrt(x*x + y*y). */
    private fun length(x: Float, y: Float): Float = sqrt(x * x + y * y)

    /** Arc lengths along the points. */
    private fun cumulative(points: List<InkPoint>): FloatArray {
        val cum = FloatArray(points.size)
        for (i in 1 until points.size) {
            cum[i] = cum[i - 1] + length(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return cum
    }

    /**
     * The iPad's nested `sample(s)`: position, radius and tangent at arc length `s`, written to the
     * fields; `seg` is kept between calls as the closure's captured index was.
     */
    private class Sampler(val points: List<InkPoint>, val cum: FloatArray) {
        var seg = 0
        var px = 0f
        var py = 0f
        var r = 0f
        var tx = 1f
        var ty = 0f

        fun sample(s: Float) {
            val n = points.size
            if (n == 1) {
                val p = points[0]
                px = p.x
                py = p.y
                r = p.r
                tx = 1f
                ty = 0f
                return
            }
            if (s < cum[seg]) seg = 0
            while (seg < n - 2 && cum[seg + 1] < s) {
                seg++
            }
            val a = points[seg]
            val b = points[seg + 1]
            val len = cum[seg + 1] - cum[seg]
            val t = if (len > 1e-5f) clampf((s - cum[seg]) / len, 0f, 1f) else 0f
            val dx = b.x - a.x
            val dy = b.y - a.y
            val dl = length(dx, dy)
            px = a.x + dx * t
            py = a.y + dy * t
            r = a.r + (b.r - a.r) * t
            if (dl > 1e-5f) {
                tx = dx / dl
                ty = dy / dl
            } else {
                tx = 1f
                ty = 0f
            }
        }
    }

    fun field(points: List<InkPoint>, width: Float, color: InkColor, seed: Float): GrassField {
        val n = points.size
        if (n == 0 || width <= 0f) return GrassField()
        val fraction = seed - floor(seed)
        val salt = (fraction * 1000000f).toInt().toUInt() + 17u

        val cum = cumulative(points)
        val total = cum[n - 1]
        val baseR = max(width * 0.5f, 0.5f)
        val isTuft = total < width
        val spacing = max(0.6f, width * 0.12f)
        val steps = if (isTuft) 7 else min(1600, (total / spacing).toInt() + 1)
        val sampler = Sampler(points, cum)

        val baseColor = Vec3(color.r, color.g, color.b)
        val yellow = Vec3(0.80f, 0.82f, 0.30f)
        val blueGreen = Vec3(0.18f, 0.52f, 0.44f)
        val perStep = if (width > 22f) 3 else 2
        val blades = ArrayList<GrassBlade>(steps * perStep + 64)

        for (k in 0 until steps) {
            val s = if (isTuft) total * rand(k, 1u, salt) else min(total, (k.toFloat() + rand(k, 1u, salt)) * spacing)
            sampler.sample(s)
            val px = sampler.px
            val py = sampler.py
            val r = sampler.r
            val tangentX = sampler.tx
            val tangentY = sampler.ty
            val normalX = -tangentY
            val normalY = tangentX
            val pressure = clampf(r / baseR, 0.6f, 1.5f)
            for (j in 0 until perStep) {
                val key = k * 4 + j
                val across = (rand(key, 2u, salt) - 0.5f) * 2f * r * 0.7f
                var baseX = px + normalX * across
                var baseY = py + normalY * across
                if (isTuft) {
                    val along = (rand(key, 9u, salt) - 0.5f) * 2f * baseR
                    baseX += tangentX * along
                    baseY += tangentY * along
                }
                // Short blades keep the letter shapes readable even in small handwriting; a few stand
                // taller and thinner, and a few lean to blue-green, so the turf is not one even fringe.
                val tall = if (rand(key, 24u, salt) < 0.14f) 1.45f else 1f
                val height = width * (0.55f + 0.6f * rand(key, 3u, salt)) * pressure * tall
                val bladeWidth = max(0.5f, width * 0.11f) * (0.7f + 0.6f * rand(key, 4u, salt)) / (if (tall > 1f) 1.3f else 1f)
                val tint = rand(key, 6u, salt)
                val cool = rand(key, 23u, salt)
                var c = baseColor * (0.78f + 0.42f * rand(key, 7u, salt))
                c += (yellow - c) * (tint * tint * 0.35f)
                c += (blueGreen - c) * (cool * cool * 0.30f)
                blades.add(
                    GrassBlade(
                        base = Vec2(baseX, baseY),
                        height = height,
                        width = bladeWidth,
                        lean = (rand(key, 5u, salt) - 0.5f) * height * 0.5f,
                        phase = rand(key, 8u, salt) * 6.283f,
                        stiffness = rand(key, 10u, salt),
                        color = c,
                        kind = BladeKind.BLADE,
                        arc = if (total > 0f) s / total else 0f,
                    ),
                )
            }
        }

        val flowers = ArrayList<GrassFlower>()
        val level = flowerLevel(seed)
        if (level > 0) {
            val gap = max(width * (if (level == 2) 1.6f else 3.2f), 10f)
            val count = if (isTuft) level else max(1, (total / gap).toInt())
            for (m in 0 until min(count, 400)) {
                val key = 50000 + m
                val s = if (isTuft) total * 0.5f else min(total, (m.toFloat() + 0.25f + 0.5f * rand(key, 11u, salt)) * gap)
                sampler.sample(s)
                val r = sampler.r
                val normalX = -sampler.ty
                val normalY = sampler.tx
                val across = (rand(key, 12u, salt) - 0.5f) * r * 1.2f
                var baseX = sampler.px + normalX * across
                val baseY = sampler.py + normalY * across
                if (isTuft) {
                    baseX += (rand(key, 19u, salt) - 0.5f) * width
                }
                val stemHeight = width * (1.0f + 0.45f * rand(key, 13u, salt))
                blades.add(
                    GrassBlade(
                        base = Vec2(baseX, baseY),
                        height = stemHeight,
                        width = max(0.45f, width * 0.07f),
                        lean = (rand(key, 14u, salt) - 0.5f) * stemHeight * 0.35f,
                        phase = rand(key, 15u, salt) * 6.283f,
                        stiffness = rand(key, 16u, salt),
                        color = baseColor * 0.62f,
                        kind = BladeKind.STEM,
                        arc = if (total > 0f) s / total else 0f,
                    ),
                )
                val kind = KINDS[min(KINDS.size - 1, (rand(key, 17u, salt) * KINDS.size.toFloat()).toInt())]
                val petalCount = min(
                    kind.petals.last,
                    kind.petals.first + (rand(key, 21u, salt) * kind.petalChoices.toFloat()).toInt(),
                )
                flowers.add(
                    GrassFlower(
                        stem = blades.size - 1,
                        radius = max(1.4f, width * (0.32f + 0.16f * rand(key, 18u, salt))) * kind.scale,
                        petals = petalCount.toFloat(),
                        style = kind.style,
                        spin = rand(key, 22u, salt) * 6.283f,
                        petal = kind.petal,
                        core = kind.core,
                        delay = 1.0f + rand(key, 20u, salt),
                    ),
                )
            }
        }

        return backToFront(blades, flowers)
    }

    /**
     * The stroke's field: grass (with its flowers) for the grass pen, flowers on stems for the
     * flowering water.
     */
    fun field(brush: Brush, points: List<InkPoint>, width: Float, color: InkColor, seed: Float): GrassField =
        if (brush == Brush.BLOOM) blooms(points, width, color, seed) else field(points, width, color, seed)

    /**
     * The flowering water pen (as in the ads): no grass, only thin stems rising from the line, each
     * with a glassy blue or violet flower that opens a moment after the pen lifts.
     */
    fun blooms(points: List<InkPoint>, width: Float, color: InkColor, seed: Float): GrassField {
        val n = points.size
        if (n == 0 || width <= 0f) return GrassField()
        val salt = ((seed - floor(seed)) * 1000000f).toInt().toUInt() + 29u
        val cum = cumulative(points)
        val total = cum[n - 1]
        val sampler = Sampler(points, cum)

        // Slots at fixed distances along the line, so a stem stays where the pen passed while the line
        // grows (a slot the pen has not reached yet is skipped, never pulled back to the end). Most
        // slots hold one stem, some a pair or three from nearby points; a dot gets one cluster.
        val gap = max(width * 2.8f, 12f)
        val isDot = total < width * 0.5f
        val slots = if (isDot) 1 else min(220, (total / gap).toInt() + 1)
        // Glass stems and leaves: the ink's turquoise, lighter and bluer; the shader lights them.
        val ink = Vec3(color.r, color.g, color.b)
        val stemColor = ink + (Vec3(0.36f, 0.82f, 0.93f) - ink) * 0.55f
        val leafColor = ink + (Vec3(0.42f, 0.86f, 0.90f) - ink) * 0.5f
        val blades = ArrayList<GrassBlade>()
        val flowers = ArrayList<GrassFlower>()
        for (m in 0 until slots) {
            val slotKey = 70000 + m * 8
            val s = if (isDot) total * 0.5f else (m.toFloat() + 0.15f + 0.7f * rand(slotKey, 1u, salt)) * gap
            if (s > total) continue
            val group = rand(slotKey, 2u, salt)
            val members = if (group < 0.12f) 3 else (if (group < 0.45f) 2 else 1)
            for (j in 0 until members) {
                if (flowers.size >= 420) continue
                val key = slotKey + 1 + j
                var sj = s
                if (j > 0 && !isDot) {
                    sj += (rand(key, 1u, salt) - 0.5f) * width * 1.3f
                    if (sj < 0f || sj > total) continue
                }
                sampler.sample(sj)
                val r = sampler.r
                val normalX = -sampler.ty
                val normalY = sampler.tx
                val across = (rand(key, 2u, salt) - 0.5f) * r * 0.6f
                var baseX = sampler.px + normalX * across
                val baseY = sampler.py + normalY * across
                if (isDot) {
                    baseX += (rand(key, 3u, salt) - 0.5f) * width * (if (j == 0) 0.3f else 1.2f)
                }
                // Most stems short, a few tall; the tall ones carry the big flowers.
                val tall = rand(key, 4u, salt)
                val stemHeight = width * (1.0f + 1.9f * tall * tall)
                val stem = GrassBlade(
                    base = Vec2(baseX, baseY),
                    height = stemHeight,
                    width = max(0.45f, width * 0.055f),
                    lean = (rand(key, 5u, salt) - 0.5f) * stemHeight * 0.5f,
                    phase = rand(key, 6u, salt) * 6.283f,
                    stiffness = rand(key, 7u, salt),
                    color = stemColor,
                    kind = BladeKind.GLASS_STEM,
                    arc = if (total > 0f) sj / total else 0f,
                )
                blades.add(stem)
                val kind = CRYSTALS[min(CRYSTALS.size - 1, (rand(key, 8u, salt) * CRYSTALS.size.toFloat()).toInt())]
                val petalCount = min(
                    kind.petals.last,
                    kind.petals.first + (rand(key, 9u, salt) * kind.petalChoices.toFloat()).toInt(),
                )
                val size = 0.4f * tall + 0.6f * rand(key, 10u, salt)
                flowers.add(
                    GrassFlower(
                        stem = blades.size - 1,
                        radius = max(1.6f, width * (0.40f + 0.55f * size)) * kind.scale,
                        petals = petalCount.toFloat(),
                        style = kind.style,
                        spin = rand(key, 11u, salt) * 6.283f,
                        petal = kind.petal,
                        core = kind.core,
                        delay = 0.6f + 0.9f * rand(key, 12u, salt),
                    ),
                )
                // One or two small leaves low on half the stems, bending away from the stem; a leaf
                // sprouts a moment after its stem.
                val leafRoll = rand(key, 13u, salt)
                val leaves = if (leafRoll < 0.12f) 2 else (if (leafRoll < 0.50f) 1 else 0)
                val firstSide = if (rand(key, 14u, salt) < 0.5f) -1f else 1f
                for (l in 0 until leaves) {
                    val ch = (20 + l * 4).toUInt()
                    val at = 0.22f + 0.30f * rand(key, ch, salt)
                    val leafHeight = stemHeight * (0.20f + 0.16f * rand(key, ch + 1u, salt))
                    blades.add(
                        GrassBlade(
                            base = pointOn(stem, at),
                            height = leafHeight,
                            width = max(0.8f, width * (0.26f + 0.14f * rand(key, ch + 2u, salt))),
                            lean = (if (l == 0) firstSide else -firstSide) * leafHeight * (1.0f + 0.5f * rand(key, ch + 3u, salt)),
                            phase = stem.phase,
                            stiffness = stem.stiffness,
                            color = leafColor,
                            kind = BladeKind.GLASS_LEAF,
                            arc = min(1f, stem.arc + 0.02f),
                        ),
                    )
                }
            }
        }
        return backToFront(blades, flowers)
    }

    /** Back to front: blades further up the page are behind. */
    private fun backToFront(blades: List<GrassBlade>, flowers: List<GrassFlower>): GrassField {
        val order = blades.indices.sortedBy { blades[it].base.y }
        val remap = IntArray(blades.size)
        for ((newIndex, old) in order.withIndex()) {
            remap[old] = newIndex
        }
        return GrassField(
            blades = order.map { blades[it] },
            flowers = flowers.map { it.copy(stem = remap[it.stem]) },
        )
    }

    /** Point along a blade, matching `bladeAt` in the shader (s = 0 base, 1 tip). */
    fun pointOn(b: GrassBlade, s: Float, sway: Float = 0f): Vec2 {
        val bend = b.lean + sway * b.height * 0.16f
        return Vec2(b.base.x + bend * s * s, b.base.y + -b.height * s)
    }
}

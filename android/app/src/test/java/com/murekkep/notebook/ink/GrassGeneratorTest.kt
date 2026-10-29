package com.murekkep.notebook.ink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

// The grass and flowering-water checks of tools/swiftcheck/main.swift, with the same lines, widths,
// colours and seeds.
class GrassGeneratorTest {
    private val turquoise = InkColor.hex(0x22B8CF)
    private val waterLine = (0..40).map { InkPoint(it * 5f, 300f, 4f, 0f) }
    private val blooms = GrassGenerator.blooms(waterLine, 8f, turquoise, 0.37f)
    private val stems = blooms.blades.filter { it.kind == BladeKind.GLASS_STEM }
    private val leaves = blooms.blades.filter { it.kind == BladeKind.GLASS_LEAF }

    @Test
    fun aFlowerOnEveryStemLeavesOnSomeNoGrassBlades() {
        assertTrue(blooms.flowers.size >= 8)
        assertEquals(blooms.flowers.size, stems.size)
        assertTrue(stems.all { it.isStem })
        assertEquals(blooms.blades.size, stems.size + leaves.size)
    }

    @Test
    fun glassFlowersWhichTheGrassPenNeverGrows() {
        assertTrue(blooms.flowers.all { it.style == GrassGenerator.GLASS_STYLE })
        val grass = GrassGenerator.field(waterLine, 8f, InkColor.hex(0x3BA55D), 1.5f)
        assertTrue(grass.flowers.isNotEmpty())
        assertTrue(grass.flowers.all { it.style < 2.5f })
    }

    @Test
    fun tallThinBladesAndBlueGreenTintsAmongTheTurfNoneTallerThanTheBound() {
        // A few blades stand taller and thinner (above the tallest ordinary blade, 10 * 1.15 at full
        // pressure), a few lean to blue-green.
        val turfLine = (0..40).map { InkPoint(it * 5f, 300f, 5f, 0f) }
        val turf = GrassGenerator.field(turfLine, 10f, InkColor.hex(0x3F9B2F), 0.37f).blades.filter { !it.isStem }
        val heights = turf.map { it.height }
        assertTrue(turf.size > 50)
        assertTrue(heights.max() > 1.6f * heights.min())
        assertTrue(turf.any { it.height > 10f * 1.15f * 1.2f && it.width < 0.9f })
        assertTrue(turf.any { it.color.z > it.color.x })
        assertTrue(turf.all { it.kind == BladeKind.BLADE && it.height <= 10f * 1.15f * 1.45f })
    }

    @Test
    fun thePetalsAreBlueAndVioletAroundAPaleCentre() {
        assertTrue(blooms.flowers.all { it.petal.z >= it.petal.x && it.petal.z >= it.petal.y && it.core.minComponent > 0.85f })
    }

    @Test
    fun theFlowersOpenAfterThePenLifts() {
        assertTrue(blooms.flowers.all { it.delay >= 0.5f && it.delay <= 1.6f })
    }

    @Test
    fun theStemsRiseFromTheLineItself() {
        assertTrue(stems.all { it.height >= 8f && abs(it.base.y - 300f) <= 4f })
    }

    @Test
    fun theStemsAreTurquoiseBlueGlassNotTheInkDarkened() {
        assertTrue(stems.all { it.color.y > it.color.x + 0.3f && it.color.z > it.color.x + 0.3f })
    }

    @Test
    fun smallLeavesSitLowOnTheirStemsAndBendAwayFromThem() {
        assertTrue(leaves.isNotEmpty())
        for (leaf in leaves) {
            val onAStem = stems.any { stem ->
                val t = (stem.base.y - leaf.base.y) / stem.height
                t >= 0.2f && t <= 0.55f && abs(stem.base.x + stem.lean * t * t - leaf.base.x) < 0.01f &&
                    leaf.height < stem.height * 0.5f && abs(leaf.lean) >= leaf.height
            }
            assertTrue("leaf at ${leaf.base} sits on no stem", onAStem)
        }
    }

    @Test
    fun stemsOfDifferentHeightsCarryFlowersOfDifferentSizes() {
        val stemHeights = stems.map { it.height }
        val flowerRadii = blooms.flowers.map { it.radius }
        assertTrue(stemHeights.max() > stemHeights.min() * 1.6f)
        assertTrue(flowerRadii.max() > flowerRadii.min() * 1.5f)
    }

    @Test
    fun someStemsStandInPairsOrThrees() {
        val stemX = stems.map { it.base.x }.sorted()
        assertTrue(stemX.zipWithNext().any { (a, b) -> b - a < 8f * 0.7f })
    }

    @Test
    fun theSameStrokeAlwaysGrowsTheSameFlowers() {
        val again = GrassGenerator.blooms(waterLine, 8f, turquoise, 0.37f)
        assertEquals(blooms.flowers.map { it.radius }, again.flowers.map { it.radius })
        assertEquals(blooms.blades.map { it.base }, again.blades.map { it.base })
    }

    @Test
    fun aVeryLongLineStaysBounded() {
        val longLine = (0..4000).map { InkPoint(it * 5f, 300f, 4f, 0f) }
        val long = GrassGenerator.blooms(longLine, 8f, turquoise, 0.37f)
        assertTrue(long.flowers.size <= 420)
        assertTrue(long.blades.size <= 420 * 3)
        assertTrue(long.flowers.size > 300)
    }

    @Test
    fun stemsStayPutWhileTheLineGrows() {
        // The live stroke's flowers are made again every frame from the growing line: a stem must stay
        // where the pen passed, not slide along as the line gets longer.
        val halfway = GrassGenerator.blooms(waterLine.take(24), 8f, turquoise, 0.37f)
        assertTrue(halfway.blades.isNotEmpty())
        val whole = blooms.blades.map { it.base }.toSet()
        assertTrue(whole.containsAll(halfway.blades.map { it.base }))
    }

    @Test
    fun aDotGrowsAFlowerToo() {
        val dot = GrassGenerator.blooms(listOf(InkPoint(50f, 50f, 4f, 0f)), 8f, turquoise, 0.5f)
        assertTrue(dot.flowers.isNotEmpty())
    }

    @Test
    fun theFloweringWaterIsANaturePenGrowingFlowersLikeTheGrass() {
        assertEquals(BrushGroup.NATURE, Brush.BLOOM.group)
        assertTrue(Brush.BLOOM.isTrialInk)
        assertFalse(Brush.BLOOM.isPremium)
        assertTrue(Brush.BLOOM.growsFlowers)
        assertTrue(Brush.GRASS.growsFlowers)
        assertFalse(Brush.SEA.growsFlowers)
        assertEquals(Brush.JELLY.raw, Brush.BLOOM.shading)
        assertEquals(Brush.SEA.raw, Brush.SEA.shading)
    }

    @Test
    fun theFieldOfABrushPicksBloomsOrGrass() {
        val viaBrush = GrassGenerator.field(Brush.BLOOM, waterLine, 8f, turquoise, 0.37f)
        assertEquals(blooms.flowers.map { it.radius }, viaBrush.flowers.map { it.radius })
        val grass = GrassGenerator.field(Brush.GRASS, waterLine, 8f, turquoise, 0.37f)
        assertTrue(grass.blades.all { it.kind == BladeKind.BLADE })
        assertTrue(grass.flowers.isEmpty())
    }

    @Test
    fun theFlowerLevelTravelsInTheSeed() {
        assertEquals(2, GrassGenerator.flowerLevel(GrassGenerator.seed(2, 0.37f)))
        assertEquals(1, GrassGenerator.flowerLevel(1.999f))
        assertEquals(0, GrassGenerator.flowerLevel(0.37f))
        assertEquals(0, GrassGenerator.flowerLevel(-1f))
        assertEquals(2, GrassGenerator.flowerLevel(7.5f))
        assertEquals(2.999f, GrassGenerator.seed(5, 1.5f), 1e-6f)
        assertEquals(0f, GrassGenerator.seed(-1, -0.5f), 0f)
    }

    @Test
    fun grassFlowersSitOnStemsAndTheFieldIsSortedBackToFront() {
        val grass = GrassGenerator.field(waterLine, 8f, InkColor.hex(0x3F9B2F), 2.37f)
        assertTrue(grass.flowers.isNotEmpty())
        assertTrue(grass.flowers.all { grass.blades[it.stem].kind == BladeKind.STEM })
        assertTrue(grass.blades.zipWithNext().all { (a, b) -> a.base.y <= b.base.y })
        assertTrue(blooms.blades.zipWithNext().all { (a, b) -> a.base.y <= b.base.y })
    }

    @Test
    fun nothingGrowsFromNothing() {
        assertTrue(GrassGenerator.field(emptyList(), 8f, turquoise, 0.5f).blades.isEmpty())
        assertTrue(GrassGenerator.blooms(waterLine, 0f, turquoise, 0.5f).blades.isEmpty())
    }
}

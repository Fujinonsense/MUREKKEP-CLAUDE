package com.murekkep.notebook.games

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The ink bubbles' field: tools/gamescheck's checks of the iPad's BubbleField, and the field a seed
// gives on the iPad (printed by its MiniGameLogic.swift).
class BubbleFieldTest {
    private val w = 300.0
    private val h = 320.0

    private fun stepped(seed: ULong, steps: Int, dt: Double, difficulty: GameDifficulty = GameDifficulty.MEDIUM) =
        BubbleField(w, h, seed, difficulty).apply { repeat(steps) { advance(dt) } }

    private fun close(a: Double, b: Double, tolerance: Double = 1e-9) = abs(a - b) < tolerance

    private fun bits(d: Double): String = java.lang.Double.doubleToRawLongBits(d).toULong().toString(16)

    @Test
    fun anEmptyGentleFieldAtTheStart() {
        val f = BubbleField(w, h, 7uL)
        assertTrue(f.bubbles.isEmpty() && f.score == 0 && f.timeLeft == 60.0 && !f.isOver && f.combo == 1)
        assertTrue(close(f.spawnInterval, 1.0) && close(f.riseSpeed, 44.0) && f.radiusRange == 11.0..28.0 && close(f.blotShare, 0.12))
    }

    @Test
    fun twoSecondsInBubblesHaveComeUpInsideTheField() {
        val f = stepped(7uL, 40, 1.0 / 20)
        assertTrue(close(f.elapsed, 2.0))
        assertTrue(f.bubbles.size >= 2)
        assertTrue(f.bubbles.all { it.x >= it.radius && it.x <= w - it.radius })
        assertTrue(f.bubbles.all { if (it.kind == Bubble.Kind.BLOT) it.radius in 13.0..21.0 else it.radius in 11.0..28.0 })
        assertTrue(f.bubbles.all { it.y < h + it.radius })
        assertEquals(f.bubbles.size, f.bubbles.map { it.id }.toSet().size)
        assertEquals("the same seed gives the same field", stepped(7uL, 40, 1.0 / 20), f)
    }

    @Test
    fun theSeedGivesTheIpadsBubbles() {
        val f = stepped(7uL, 40, 1.0 / 20)
        val rows = f.bubbles.map { b -> listOf(b.id, b.kind, bits(b.home), bits(b.radius), bits(b.speed), bits(b.y), bits(b.hue), bits(b.sway), bits(b.phase)).joinToString(" ") }
        assertEquals(
            listOf(
                "1 INK 4070067114059020 40267f9650592f40 404fa7e707800779 406dee4f3f1a5d1a 3fe3891eeccce498 4017fb57d0d977d5 4007859a289ec6ff",
                "2 INK 405fd16704b02f1c 402a551441429bde 4047f26091e74822 4073538298eba059 3fe6c87f686b42fa 4026b0354df4a45c 4015e621f50950c2",
            ),
            rows,
        )
        assertTrue(close(f.bubbles[0].x, 251.789520128, 1e-6) && close(f.bubbles[1].x, 127.743167688, 1e-6))
        assertEquals("4000000000000002", bits(f.elapsed))
        val hard = BubbleField(316.0, 300.0, 99uL, GameDifficulty.HARD).apply { repeat(45 * 30) { advance(1.0 / 30) } }
        assertEquals(listOf(75, 77, 78, 79, 80), hard.bubbles.map { it.id })
        assertEquals(56, hard.escaped)
        assertTrue(hard.bubbles.none { it.kind == Bubble.Kind.BLOT })
    }

    @Test
    fun aStepNeverJumpsFurtherThanATenth() {
        val field = stepped(7uL, 40, 1.0 / 20)
        val jumped = field.copy().apply { advance(5.0) }
        assertTrue(close(jumped.elapsed, 2.1))
        val still = field.copy().apply {
            advance(0.0)
            advance(-1.0)
        }
        assertEquals(field, still)
    }

    @Test
    fun aTouchPopsTheBubbleUnderItAndTheNearestOfTwo() {
        val field = stepped(7uL, 40, 1.0 / 20)
        val target = field.bubbles.first { it.kind == Bubble.Kind.INK }.copy()
        val before = field.bubbles.size
        assertEquals(PopResult.Popped(target.worth, 1), field.pop(target.x + target.radius + 8, target.y))
        assertTrue(field.bubbles.size == before - 1 && field.bubbles.none { it.id == target.id })
        assertTrue(field.score == target.worth && field.popped == 1 && field.splashes.size == 1 && !field.splashes[0].blot)
        val worthRight = (target.radius < 15 && target.worth == 3) || (target.radius >= 15 && target.radius < 21 && target.worth == 2) ||
            (target.radius >= 21 && target.worth == 1)
        assertTrue("small bubbles are worth three, middling two, big one", worthRight)
        assertEquals(PopResult.Miss, field.pop(-500.0, -500.0))
        assertTrue("a touch on nothing scores nothing and breaks the row", field.score == target.worth && field.combo == 1)

        val crowd = BubbleField(w, h, 1uL).apply { repeat(200) { advance(1.0 / 30) } }
        val ink = crowd.bubbles.filter { it.kind == Bubble.Kind.INK }.map { it.copy() }
        assertTrue(ink.size >= 2)
        val (a, b) = ink
        crowd.pop(a.x + (b.x - a.x) * 0.1, a.y + (b.y - a.y) * 0.1)
        assertTrue(crowd.bubbles.none { it.id == a.id } && crowd.bubbles.any { it.id == b.id })
    }

    @Test
    fun quickPopsInARowMultiplyUpToFour() {
        var seed = 1uL
        var row = BubbleField(w, h, seed)
        while (row.bubbles.count { it.kind == Bubble.Kind.INK } < 5 && seed < 200uL) {
            seed += 1uL
            row = stepped(seed, 100, 1.0 / 20)
        }
        val combos = mutableListOf<Int>()
        val multipliers = mutableListOf<Int>()
        for (bubble in row.bubbles.filter { it.kind == Bubble.Kind.INK }.take(5).map { it.copy() }) {
            val result = row.pop(bubble.x, bubble.y)
            if (result is PopResult.Popped) {
                combos.add(result.combo)
                multipliers.add(result.points / bubble.worth)
            }
        }
        assertEquals(listOf(1, 2, 3, 4, 4), combos)
        assertEquals(combos, multipliers)
        assertTrue(row.combo == 4 && row.popped == 5)
        repeat(12) { row.advance(0.1) }
        val late = row.bubbles.first { it.kind == Bubble.Kind.INK }
        val result = row.pop(late.x, late.y)
        assertTrue("a pop after more than 0.9 s starts a new row", result is PopResult.Popped && result.combo == 1)
    }

    /** A field with a blot in it, as gamescheck finds one. */
    private fun blotField(): BubbleField {
        var seed = 2uL
        var field = stepped(seed, 80, 1.0 / 20)
        while (field.bubbles.none { it.kind == Bubble.Kind.BLOT } && seed < 300uL) {
            seed += 1uL
            field = stepped(seed, 80, 1.0 / 20)
        }
        return field
    }

    @Test
    fun aTouchedBlotCostsFivePointsAndThreeSeconds() {
        val field = blotField()
        val blot = field.bubbles.first { it.kind == Bubble.Kind.BLOT }.copy()
        val scoreBefore = field.score
        val leftBefore = field.timeLeft
        assertEquals(PopResult.Blot(5, 3), field.pop(blot.x, blot.y))
        assertTrue(field.blotsHit == 1 && field.combo == 1)
        assertTrue(field.score == maxOf(0, scoreBefore - 5) && close(field.timeLeft, leftBefore - 3) && field.splashes.last().blot)
        assertEquals(0, blot.worth)
        val shortened = field.copy()
        var steps = 0
        while (!shortened.isOver && steps < 2000) {
            shortened.advance(0.1)
            steps += 1
        }
        assertTrue("a blot's three seconds end the round sooner", shortened.isOver && close(shortened.elapsed, 57.0, 1e-6))
    }

    @Test
    fun theRoundQuickensShrinksAndEndsAtSixtySeconds() {
        val fading = stepped(7uL, 40, 1.0 / 20).apply {
            pop(bubbles[0].x, bubbles[0].y)
            repeat(12) { advance(0.05) }
        }
        assertTrue("a splash is gone after half a second", fading.splashes.isEmpty())
        val long = stepped(3uL, 30 * 30, 1.0 / 30)
        assertTrue(close(long.elapsed, 30.0, 1e-6) && close(long.difficulty, 0.5, 1e-6))
        assertTrue(close(long.spawnInterval, 0.675, 1e-6) && close(long.riseSpeed, 82.0, 1e-6) && close(long.radiusRange.endInclusive, 23.1, 1e-6) && close(long.blotShare, 0.21, 1e-6))
        assertTrue(long.bubbles.all { it.y + it.radius >= 0 } && long.escaped > 0 && long.combo == 1)
        assertTrue(long.bubbles.size < 60)
        repeat(31 * 30) { long.advance(1.0 / 30) }
        assertTrue(long.isOver && long.timeLeft == 0.0 && close(long.elapsed, 60.0, 1e-6))
        assertTrue(close(long.spawnInterval, 0.35) && close(long.riseSpeed, 120.0) && close(long.radiusRange.start, 7.15) && close(long.blotShare, 0.3))
        val frozen = long.copy()
        long.advance(0.5)
        val last = long.bubbles.firstOrNull()
        assertEquals(PopResult.Miss, long.pop(last?.x ?: 0.0, last?.y ?: 0.0))
        assertEquals("nothing moves or pops after the end", frozen, long)
    }

    @Test
    fun eachDifficultyHasItsPaceReachAndBlots() {
        assertTrue(BubbleField.pace(GameDifficulty.EASY) == 0.8 && BubbleField.pace(GameDifficulty.MEDIUM) == 1.0 && BubbleField.pace(GameDifficulty.HARD) == 1.3)
        val easy = BubbleField.Tuning.of(GameDifficulty.EASY)
        val medium = BubbleField.Tuning.of(GameDifficulty.MEDIUM)
        val hard = BubbleField.Tuning.of(GameDifficulty.HARD)
        assertTrue(easy.reach > medium.reach && hard.reach < medium.reach)
        assertTrue(easy.blotsAtEnd < medium.blotsAtEnd && hard.blotsAtStart > medium.blotsAtStart)
        val zor = BubbleField(w, h, 7uL, GameDifficulty.HARD)
        assertTrue(close(zor.spawnInterval, 1.0 / 1.3) && close(zor.riseSpeed, 44 * 1.3) && close(zor.blotShare, 0.18))
        val kolay = BubbleField(w, h, 7uL, GameDifficulty.EASY)
        assertTrue(close(kolay.spawnInterval, 1.0 / 0.8) && close(kolay.riseSpeed, 44 * 0.8) && close(kolay.blotShare, 0.06))
        assertTrue(BubbleField(w, h, 7uL) == BubbleField(w, h, 7uL, GameDifficulty.MEDIUM) && BubbleField(w, h, 7uL).pace == 1.0)
    }

    @Test
    fun aRoundAtOrtaBringsAboutAHundredBubbles() {
        val busy = BubbleField(w, h, 9uL)
        var spawned = 0
        var lastId = 0
        repeat(60 * 30) {
            busy.advance(1.0 / 30)
            val newest = busy.bubbles.maxOfOrNull { it.id }
            if (newest != null && newest > lastId) {
                spawned += newest - lastId
                lastId = newest
            }
        }
        assertTrue("$spawned", spawned in 95..130)
    }
}

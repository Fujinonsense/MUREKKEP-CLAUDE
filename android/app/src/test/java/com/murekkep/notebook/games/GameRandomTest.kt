package com.murekkep.notebook.games

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

// The games' random source draws as Swift does. The expected values were printed by the iPad's own
// MiniGameLogic.swift (GameRandom with Swift's Double.random, Int.random, randomElement and
// shuffled), compiled on the PC with the Windows Swift toolchain on 2026-10-30.
class GameRandomTest {
    private fun bits(d: Double): String = java.lang.Double.doubleToRawLongBits(d).toULong().toString(16)

    @Test
    fun splitMixGivesTheIpadsNumbers() {
        val r = GameRandom(7uL)
        val drawn = List(5) { r.next().toString() }
        assertEquals(listOf("7191089600892374487", "309689372594955804", "16616101746815609346", "10753165928301472203", "8346079845500723674"), drawn)
    }

    @Test
    fun aDoubleBelowOneIsSwiftsToTheLastBit() {
        val r = GameRandom(3uL)
        val drawn = List(6) { bits(r.nextDouble(0.0, 1.0)) }
        assertEquals("3fd629c9b6031fda,3fc9be29ee06a624,3fd7d14da0a1ba02,3fcd93ed9aaf273c,3fd11b5b956f332c,3fef7737091f4f07", drawn.joinToString(","))
    }

    @Test
    fun aDoubleInAClosedRangeIsSwiftsToTheLastBit() {
        val r = GameRandom(5uL)
        val drawn = List(6) { bits(r.nextDoubleClosed(13.0, 21.0)) }
        assertEquals("40301819d8651c4e,403304b98a6c9cba,402db92d3f0106bc,402b96e4ec2da05c,402d01e278faa016,40300b7cb185803a", drawn.joinToString(","))
    }

    @Test
    fun integersElementsAndShufflesAreSwifts() {
        val r = GameRandom(9uL)
        assertEquals(listOf(0, 1, 0, 5, 2, 9, 645, 2, 0), listOf(1, 2, 3, 7, 9, 81, 1000, 3, 2).map { r.nextInt(it) })
        assertEquals(listOf(5, 9, 3, 1, 2, 6, 0, 4, 8, 7), GameRandom(12uL).shuffled((0 until 10).toList()))
        val e = GameRandom(21uL)
        assertEquals(listOf(4, 42, 16, 16, 4, 15, 42, 4), List(8) { e.element(listOf(4, 8, 15, 16, 23, 42)) })
        assertNull("an empty list has no element", e.element(emptyList<Int>()))
    }

    @Test
    fun theHighHalfOfAProductIsExact() {
        val r = GameRandom(1uL)
        val two64 = BigInteger.ONE.shiftLeft(64)
        repeat(500) {
            val a = r.next()
            val b = if (it % 3 == 0) ULong.MAX_VALUE else r.next()
            val expected = BigInteger(a.toString()).multiply(BigInteger(b.toString())).divide(two64)
            assertEquals(expected.toString(), GameRandom.multiplyHigh(a, b).toString())
        }
    }

    @Test
    fun aCopyDrawsTheSameAndSeedsDiffer() {
        val r = GameRandom(40uL)
        r.next()
        val c = r.copy()
        assertEquals(r, c)
        assertEquals(r.next(), c.next())
        assertNotEquals(GameRandom(1uL), GameRandom(2uL))
    }
}

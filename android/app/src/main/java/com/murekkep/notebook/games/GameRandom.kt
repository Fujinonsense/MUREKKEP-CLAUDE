package com.murekkep.notebook.games

// The break corner's games without their screens (the iPad's MiniGameLogic.swift, SudokuLogic.swift
// and DotsLogic.swift, checked there by tools/gamescheck): plain Kotlin, nothing of Android, so the
// JVM tests run them as they are.

/**
 * A small seedable random source (SplitMix64, the iPad's GameRandom), so the games' checks run the
 * same every time. It draws numbers the way Swift's standard library does (Int.random(in:using:),
 * Double.random(in:using:), randomElement and shuffled over a RandomNumberGenerator), so a seed
 * gives the same puzzle, bubbles and moves as on the iPad.
 */
class GameRandom(seed: ULong) {
    private var state = seed

    /** The next 64 random bits. */
    fun next(): ULong {
        state += 0x9E37_79B9_7F4A_7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58_476D_1CE4_E5B9uL
        z = (z xor (z shr 27)) * 0x94D0_49BB_1331_11EBuL
        return z xor (z shr 31)
    }

    /** A number in 0 until [upperBound], unbiased: Lemire's nearly divisionless method, as Swift's next(upperBound:). */
    fun next(upperBound: ULong): ULong {
        require(upperBound != 0uL) { "upperBound cannot be zero" }
        var random = next()
        var low = random * upperBound
        if (low < upperBound) {
            val t = (0uL - upperBound) % upperBound
            while (low < t) {
                random = next()
                low = random * upperBound
            }
        }
        return multiplyHigh(random, upperBound)
    }

    /** Int.random(in: 0..<until). */
    fun nextInt(until: Int): Int {
        require(until > 0) { "empty range" }
        return next(until.toULong()).toInt()
    }

    /** Double.random(in: from..<until): 53 random bits; a value that rounds up to [until] is drawn again. */
    fun nextDouble(from: Double, until: Double): Double {
        val delta = until - from
        while (true) {
            val bits = next() and (SIGNIFICAND - 1uL)
            val value = delta * (bits.toDouble() * HALF_ULP) + from
            if (value != until) return value
        }
    }

    /** Double.random(in: from...to), [to] included. */
    fun nextDoubleClosed(from: Double, to: Double): Double {
        val delta = to - from
        val bits = next(SIGNIFICAND + 1uL)
        if (bits == SIGNIFICAND) return to
        return delta * (bits.toDouble() * HALF_ULP) + from
    }

    /** An element at random, null for an empty list (randomElement(using:)). */
    fun <T> element(items: List<T>): T? = if (items.isEmpty()) null else items[nextInt(items.size)]

    /** The items in a random order (shuffled(using:), the Fisher-Yates walk from the front). */
    fun <T> shuffled(items: List<T>): List<T> {
        val out = items.toMutableList()
        var amount = out.size
        var i = 0
        while (amount > 1) {
            val r = nextInt(amount)
            amount -= 1
            val held = out[i]
            out[i] = out[i + r]
            out[i + r] = held
            i += 1
        }
        return out
    }

    /** The same source at the same point: what it draws next, the copy draws too. */
    fun copy(): GameRandom = GameRandom(state)

    override fun equals(other: Any?): Boolean = other is GameRandom && other.state == state

    override fun hashCode(): Int = state.hashCode()

    companion object {
        /** 2^53: a Double's 52 significand bits and its leading one. */
        private const val SIGNIFICAND = 9_007_199_254_740_992uL
        /** Double.ulpOfOne / 2: 53 bits make a number in 0..<1. */
        private const val HALF_ULP = 1.0 / 9007199254740992.0

        /** Seeded from the clock. */
        fun clock(): GameRandom = GameRandom(System.currentTimeMillis().toULong())

        /** The high 64 bits of the 128-bit product (Hacker's Delight's mulhu). */
        internal fun multiplyHigh(a: ULong, b: ULong): ULong {
            val mask = 0xFFFF_FFFFuL
            val a0 = a and mask
            val a1 = a shr 32
            val b0 = b and mask
            val b1 = b shr 32
            val t = a1 * b0 + ((a0 * b0) shr 32)
            val w1 = (t and mask) + a0 * b1
            return a1 * b1 + (t shr 32) + (w1 shr 32)
        }
    }
}

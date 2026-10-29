package com.murekkep.notebook.ui

// The edges the notebook's pen bar can stand on (Murekkep.swiftpm/PaletteDock.swift, checked in
// tools/swiftcheck). The left edge is kept for the drafting rail, so the bar never goes there.

enum class PaletteEdge(val raw: String) {
    TOP("top"),
    BOTTOM("bottom"),
    TRAILING("trailing");

    /** Down the right side the bar stands upright. */
    val isVertical: Boolean get() = this == TRAILING

    companion object {
        /** A stored edge; anything else (and nothing) is the bottom, the default. */
        fun fromRaw(raw: String?): PaletteEdge = entries.firstOrNull { it.raw == raw } ?: BOTTOM

        /**
         * The edge a bar let go of at `x, y` in a canvas `width` x `height` goes to: the nearest of the
         * three. A point by the left edge goes to the nearer of top and bottom; a tie keeps `current`.
         */
        fun nearest(x: Float, y: Float, width: Float, height: Float, current: PaletteEdge): PaletteEdge {
            fun distance(edge: PaletteEdge): Float = when (edge) {
                TOP -> y
                BOTTOM -> height - y
                TRAILING -> width - x
            }
            val best = entries.minOf(::distance)
            return if (distance(current) == best) current else entries.first { distance(it) == best }
        }
    }
}

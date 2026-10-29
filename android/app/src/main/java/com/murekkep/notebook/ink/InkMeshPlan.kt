package com.murekkep.notebook.ink

// Port of Murekkep.swiftpm/InkMeshPlan.swift.

/**
 * How a page's GPU geometry follows a change of its strokes. The buffers hold the highlighters
 * first, then every other stroke in page order, so writing a new line (the common change) only
 * needs its own mesh copied after the others. Erasing, cutting, moving or reordering strokes keeps
 * the other strokes' meshes where they are and only redraws the lists; the whole page is rebuilt
 * when new grass appears (its blades live elsewhere in the buffers) or the page was never built.
 */
sealed class InkMeshPlan {
    /** The same strokes: keep everything. */
    data object Same : InkMeshPlan()

    /** The strokes from this buffer position on are new and go after the existing ones. */
    data class Append(val from: Int) : InkMeshPlan()

    /** Strokes went, came in between, or moved in the order: keep the meshes, redo the lists. */
    data object Keep : InkMeshPlan()

    data object Rebuild : InkMeshPlan()

    /** One of the page's strokes as the plan sees it (the iPad's `(id, highlighter, grass)` tuple). */
    data class Entry(val id: Int, val highlighter: Boolean, val grass: Boolean)

    companion object {
        /** `old` is the stroke ids in buffer order; `new` the page's strokes in page order. */
        fun plan(old: List<Int>, new: List<Entry>): InkMeshPlan {
            if (old.isEmpty()) return Rebuild
            val order = ArrayList<Int>(new.size)
            for (e in new) if (e.highlighter) order.add(e.id)
            for (e in new) if (!e.highlighter) order.add(e.id)
            if (order == old) return Same
            // Linear in the page's strokes: this runs on every lift of the pen and every eraser step.
            val known = old.toHashSet()
            val added = new.filter { it.id !in known }
            if (added.any { it.grass }) return Rebuild
            if (order.size > old.size && order.subList(0, old.size) == old && added.none { it.highlighter }) {
                return Append(old.size)
            }
            return Keep
        }
    }
}

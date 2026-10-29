package com.murekkep.notebook.ui

import com.murekkep.notebook.ink.Brush
import kotlin.math.max

// Which pens stand in the editor's floating bar (Murekkep.swiftpm/PenStrip.swift, checked in
// tools/swiftcheck): the favourites always, then the pens used last, so the bar holds five. Next
// to many favourites two recent pens still stay. Each group keeps the panel's order, so a pen keeps
// its place when it is picked.

object PenStripRule {
    const val COUNT = 5
    const val RECENT_BESIDE_FAVORITES = 2

    /** How many pens the recent list remembers (AppSettings.rememberBrush on iPad). */
    const val REMEMBERED = 6

    /** A new user's recent pens: the writing pens. */
    val defaultRecent: List<Brush> = listOf(Brush.PEN, Brush.PENCIL, Brush.FOUNTAIN, Brush.HIGHLIGHTER)

    /** The bar's pens: the favourites in the panel's order, then the recent ones that fill it up. */
    fun <Pen> pens(favorites: List<Pen>, recent: List<Pen>, order: List<Pen>): Pair<List<Pen>, List<Pen>> {
        val starred = favorites.toSet()
        val room = if (favorites.isEmpty()) COUNT else max(RECENT_BESIDE_FAVORITES, COUNT - starred.size)
        val lately = recent.filter { it !in starred }.take(room).toSet()
        return order.filter { it in starred } to order.filter { it in lately }
    }

    /** Stars a pen, or takes its star away. */
    fun <Pen> toggled(pen: Pen, favorites: List<Pen>): List<Pen> =
        if (pen in favorites) favorites.filter { it != pen } else favorites + pen

    /** The recent list after a pen is picked: it moves to the front; the list keeps [REMEMBERED]. */
    fun <Pen> remembered(pen: Pen, recent: List<Pen>): List<Pen> =
        if (recent.firstOrNull() == pen) recent else (listOf(pen) + recent.filter { it != pen }).take(REMEMBERED)
}

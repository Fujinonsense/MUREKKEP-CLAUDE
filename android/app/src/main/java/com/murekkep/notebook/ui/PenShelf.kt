package com.murekkep.notebook.ui

import com.murekkep.notebook.R
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.BrushGroup

// The pen panel shows one shelf at a time (Murekkep.swiftpm/PenShelf.swift, checked in
// tools/swiftcheck): the favourites, the writing, paint and nature pens, and the ten 3D inks together
// on their own shelf. Every pen stands on exactly one shelf besides the favourites.

enum class PenShelf(val raw: String, val titleRes: Int) {
    FAVORITES("favorites", R.string.pen_shelf_favorites),
    WRITING("writing", R.string.pen_shelf_writing),
    PAINT("paint", R.string.pen_shelf_paint),
    NATURE("nature", R.string.pen_shelf_nature),
    THREE_D("threeD", R.string.pen_shelf_3d);

    /** The shelf's pens in the panel's order. */
    fun brushes(favorites: List<Brush>): List<Brush> = when (this) {
        FAVORITES -> Brush.paletteOrder.filter { it in favorites }
        THREE_D -> Brush.paletteOrder.filter { it.isPremium }
        WRITING -> Brush.paletteOrder.filter { !it.isPremium && it.group == BrushGroup.WRITING }
        PAINT -> Brush.paletteOrder.filter { !it.isPremium && it.group == BrushGroup.PAINT }
        NATURE -> Brush.paletteOrder.filter { !it.isPremium && (it.group == BrushGroup.NATURE || it.group == BrushGroup.SHINE) }
    }

    companion object {
        /** The shelf a pen stands on (never the favourites). */
        fun shelf(of: Brush): PenShelf = when {
            of.isPremium -> THREE_D
            of.group == BrushGroup.WRITING -> WRITING
            of.group == BrushGroup.PAINT -> PAINT
            else -> NATURE
        }

        /** The shelf the panel opens on: the one used last, else the favourites when there are any,
         *  else the shelf of the pen in hand. */
        fun opening(saved: String?, favorites: List<Brush>, current: Brush): PenShelf {
            val shelf = entries.firstOrNull { it.raw == saved }
            if (shelf != null && (shelf != FAVORITES || favorites.isNotEmpty())) return shelf
            return if (favorites.isEmpty()) shelf(current) else FAVORITES
        }
    }
}

package com.murekkep.notebook.canvas

import com.murekkep.notebook.ink.InstrumentKind
import com.murekkep.notebook.ink.Vec2

// What the canvas hands the screen of the drafting instruments and the compass (CanvasOverlayView's
// `instrument`, `instrumentLabel`, `compass` and `compassPen` on iPad), in view pixels; the screen
// draws them over the ink (ui/InstrumentOverlay.kt).

/** A ruler, set square or protractor on the page: its middle (view pixels), its turn (radians,
 *  clockwise on screen), view pixels per document point, and its angle ("37°") while two fingers
 *  turn it. */
data class InstrumentOverlay(
    val kind: InstrumentKind,
    val x: Float,
    val y: Float,
    val angle: Float,
    val zoom: Float,
    val label: String? = null,
)

/** The compass (view pixels): its center, its radius (0 as its first drag starts) and the pen joined
 *  to the center while it sets the radius or draws an arc. */
data class CompassOverlay(val x: Float, val y: Float, val radius: Float, val pen: Vec2? = null)

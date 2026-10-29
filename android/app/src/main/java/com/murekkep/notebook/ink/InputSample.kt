package com.murekkep.notebook.ink

// One pen or finger sample in page-local points: the iPad's `InputSample` (Murekkep.swiftpm/
// StrokeBuilder.swift), which CanvasView.sample(_:origin:) fills from a UITouch. The Android canvas
// fills it from a MotionEvent (its history and the predicted samples included).
//
// Force is on the iPad's `UITouch.force` scale, which StrokeBuilder reads unchanged: 1 = an average
// press, 0 = the device reported no force (fingers; the builder then reads 1, a plain line), and an
// Apple Pencil reports up to `maximumPossibleForce`, about 4.17. The builder clamps the value to
// 0.05...3 (the fountain pen to 0.05...3.5) and takes its square root for the width, so 0.05 is the
// thinnest line and 3 the widest. Android's `MotionEvent.getPressure()` is 0...1 with 1 the pen's full
// pressure (a finger's is a guess from the contact size), so the canvas passes
// `pressure * PENCIL_MAX_FORCE` for a stylus (its full press reaches the Pencil's full width, about a
// quarter press is the average press; tune the scale per device if a pen writes too thick or thin)
// and 0 for a finger: `InputSample.force(pressure, stylus)`.
//
// Altitude and azimuth are radians as the Pencil reports them: altitude pi/2 = upright, 0 = flat
// (Android: pi/2 - AXIS_TILT); azimuth 0 = the barrel points along +x of the page, clockwise
// (Android: AXIS_ORIENTATION - pi/2, since 0 there points up the screen). The builder reads only the
// altitude (the pencil's and the watercolor's tilt shading); the azimuth is for the cursor. Roll is
// the Pencil Pro's barrel roll, which turns the calligraphy nib; Android pens report none, so 0.
//
// `timestamp` is seconds on any monotonic clock (the iPad uses the touch's own); only differences
// are read, for the stroke's speed. `predicted` marks a sample the system guessed ahead of the pen:
// it goes to `StrokeBuilder.preview` only, never to `add`.
data class InputSample(
    val x: Float,
    val y: Float,
    /** iPad `UITouch.force`: 1 = an average press, 0 = none reported (read as 1). See the file comment. */
    val force: Float,
    /** Seconds, any monotonic clock. */
    val timestamp: Double,
    /** Radians: pi/2 = upright, 0 = flat (Android: pi/2 - AXIS_TILT). */
    val altitude: Float = 1.5707964f,
    /** Radians in page space, 0 = +x, clockwise (Android: AXIS_ORIENTATION - pi/2). */
    val azimuth: Float = 0f,
    /** Barrel roll in radians (none on Android pens). */
    val roll: Float = 0f,
    val isPencil: Boolean = true,
    val predicted: Boolean = false,
) {
    companion object {
        /** The Apple Pencil's `UITouch.maximumPossibleForce`: a stylus pressure of 1 maps to it. */
        const val PENCIL_MAX_FORCE = 4.1666665f

        /**
         * The iPad force for an Android `MotionEvent` pressure (0...1): the Pencil's full range for a
         * stylus, 0 (no force, read as the average press) for a finger or a pressure of 0.
         */
        fun force(pressure: Float, stylus: Boolean): Float =
            if (stylus && pressure > 0f) pressure * PENCIL_MAX_FORCE else 0f
    }
}

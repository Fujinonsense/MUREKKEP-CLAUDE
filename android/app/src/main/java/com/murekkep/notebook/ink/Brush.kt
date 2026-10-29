package com.murekkep.notebook.ink

// The pens of the iPad app (Murekkep.swiftpm/Brushes.swift), with the same raw values (they are
// stored in ink files) and the same numbers.

enum class BrushGroup(val titleTr: String, val titleEn: String) {
    WRITING("Yazı", "Writing"),
    PAINT("Boya", "Paint"),
    NATURE("Doğa", "Nature"),
    SHINE("Işıltı", "Shine");

    val brushes: List<Brush> get() = Brush.paletteOrder.filter { it.group == this }
}

enum class Brush(val raw: Int, val titleTr: String, val titleEn: String) {
    PEN(0, "Kalem", "Pen"),
    WET(1, "Islak mürekkep", "Wet ink"),
    WAVE(2, "Okyanus", "Ocean"),
    HIGHLIGHTER(3, "Fosforlu", "Highlighter"),
    PENCIL(4, "Kurşun kalem", "Pencil"),
    CALLIGRAPHY(5, "Hat kalemi", "Calligraphy pen"),
    WATERCOLOR(6, "Sulu boya", "Watercolor"),
    NEON(7, "Neon", "Neon"),
    RAINBOW(8, "Gökkuşağı", "Rainbow"),
    GLITTER(9, "Simli", "Glitter"),
    GRASS(10, "Çim ve çiçek", "Grass and flowers"),
    SEA(11, "Deniz dalgası", "Sea wave"),
    LAVA(12, "Lav", "Lava"),
    FOUNTAIN(13, "Dolma kalem 3B", "Fountain pen 3D"),
    GOLD(14, "Sıvı altın", "Liquid gold"),
    CHROME(15, "Krom", "Chrome"),
    ICE(16, "Buz kristali", "Ice crystal"),
    JELLY(17, "Jöle", "Jelly"),
    GALAXY(18, "Galaksi", "Galaxy"),
    LIGHTNING(19, "Şimşek", "Lightning"),
    PEARL(20, "İnci dizisi", "Pearl string"),
    IMPASTO(21, "Yağlı boya", "Oil paint"),
    BLOOM(22, "Çiçekli su", "Flowering water");

    val group: BrushGroup
        get() = when (this) {
            PEN, PENCIL, FOUNTAIN, CALLIGRAPHY, HIGHLIGHTER -> BrushGroup.WRITING
            WATERCOLOR, IMPASTO, WET, NEON, RAINBOW, GLITTER -> BrushGroup.PAINT
            SEA, WAVE, GRASS, BLOOM, LAVA, ICE, LIGHTNING, GALAXY -> BrushGroup.NATURE
            GOLD, CHROME, PEARL, JELLY -> BrushGroup.SHINE
        }

    /** The 3D inks (Pro), marked with a star on the pen's barrel. */
    val isPremium: Boolean
        get() = this in setOf(LAVA, FOUNTAIN, GOLD, CHROME, ICE, JELLY, GALAXY, LIGHTNING, PEARL, IMPASTO)

    /** The nature pens: free to try with a trial amount of ink. */
    val isTrialInk: Boolean get() = this == SEA || this == WAVE || this == GRASS || this == BLOOM

    /** Stroke width in page points. */
    val defaultWidth: Float
        get() = when (this) {
            PEN -> 2.2f; WET -> 3.8f; WAVE -> 12f; HIGHLIGHTER -> 16f; PENCIL -> 2.6f; CALLIGRAPHY -> 7f
            WATERCOLOR -> 16f; NEON -> 4f; RAINBOW -> 6f; GLITTER -> 6f; GRASS -> 10f; SEA -> 8f; LAVA -> 7f
            FOUNTAIN -> 3.2f; GOLD -> 5f; CHROME -> 6f; ICE -> 7f; JELLY -> 8f; GALAXY -> 8f; LIGHTNING -> 4f
            PEARL -> 7f; IMPASTO -> 12f; BLOOM -> 7f
        }

    val widthRange: ClosedFloatingPointRange<Float>
        get() = when (this) {
            PEN -> 0.8f..8f; WET -> 1.5f..14f; WAVE -> 4f..40f; HIGHLIGHTER -> 6f..40f; PENCIL -> 1f..12f
            CALLIGRAPHY -> 2f..24f; WATERCOLOR -> 4f..48f; NEON -> 1.5f..14f; RAINBOW -> 2f..30f
            GLITTER -> 2f..24f; GRASS -> 3f..40f; SEA -> 2f..36f; LAVA -> 2f..36f; FOUNTAIN -> 1f..14f
            GOLD -> 1.5f..24f; CHROME -> 2f..30f; ICE -> 2f..32f; JELLY -> 2f..36f; GALAXY -> 2f..40f
            LIGHTNING -> 1.5f..16f; PEARL -> 3f..30f; IMPASTO -> 3f..48f; BLOOM -> 2f..30f
        }

    /** 0 = width ignores pressure, 1 = width follows pressure strongly. */
    val pressureSensitivity: Float
        get() = when (this) {
            PEN -> 0.45f; WET -> 0.65f; WAVE -> 0.3f; HIGHLIGHTER -> 0f; PENCIL -> 0.35f; CALLIGRAPHY -> 0.3f
            WATERCOLOR -> 0.55f; NEON -> 0.15f; RAINBOW -> 0.4f; GLITTER -> 0.35f; GRASS -> 0.3f; SEA -> 0.3f
            LAVA -> 0.4f; FOUNTAIN -> 0.9f; GOLD -> 0.45f; CHROME -> 0.35f; ICE -> 0.35f; JELLY -> 0.4f
            GALAXY -> 0.35f; LIGHTNING -> 0.2f; PEARL -> 0.25f; IMPASTO -> 0.5f; BLOOM -> 0.35f
        }

    /** Drawn every frame while animations are on. */
    val isAnimated: Boolean
        get() = this in setOf(WAVE, GLITTER, GRASS, BLOOM, SEA, LAVA, ICE, JELLY, GALAXY, LIGHTNING)

    /** Needs the full frame rate (fast motion) rather than 30 fps. */
    val isFastAnimated: Boolean get() = this == WAVE || this == SEA || this == LIGHTNING

    /** Fresh strokes are wet and dry over a few seconds. */
    val dries: Boolean get() = this == WET

    /** Drawn with multiply blending under the ink. */
    val isHighlighter: Boolean get() = this == HIGHLIGHTER

    /** Raised ink that casts a soft shadow. */
    val castsShadow: Boolean
        get() = this !in setOf(PEN, PENCIL, CALLIGRAPHY, HIGHLIGHTER, WATERCOLOR, NEON, RAINBOW, LIGHTNING)

    /** Uses the pen's tilt for shading. */
    val usesTilt: Boolean get() = this == PENCIL || this == WATERCOLOR

    /** See-through parts (glass, gel, glow): where the stroke folds over itself it gets a depth pass
     *  first and is blended only once. */
    val blendsOnce: Boolean get() = this in setOf(NEON, ICE, JELLY, BLOOM, LAVA, LIGHTNING)

    /** Grows blades or flowers over its line (GrassGenerator). */
    val growsFlowers: Boolean get() = this == GRASS || this == BLOOM

    /** The look the GPU draws the line with: the blooming water is the glossy gel. */
    val shading: Int get() = if (this == BLOOM) JELLY.raw else raw

    /** Thick, shaded ink bends smoothly through sharp corners instead of creasing. */
    val relaxesCorners: Boolean
        get() = this !in setOf(PEN, PENCIL, CALLIGRAPHY, HIGHLIGHTER, WATERCOLOR)

    val palette: List<InkColor>
        get() = when (this) {
            PEN -> p(0x1C1C1E, 0x1E4FD8, 0xD93025, 0x1E8E3E, 0x7B3FD0, 0xE8710A)
            WET -> p(0x122B94, 0x111318, 0x7A1530, 0x0B6E4F, 0x6B3E1F, 0x4B1C8C)
            WAVE -> p(0x0D61B8, 0x0A9396, 0x065A82, 0x1BA3C6, 0x5B3FD1, 0xE0566B)
            HIGHLIGHTER -> p(0xFFE74C, 0xA6F28A, 0xFFA3D1, 0x9CD8FF, 0xFFC26B, 0xD5B3FF)
            PENCIL -> p(0x2B2B2E, 0x5C5F66, 0x2F5DA8, 0xB3362F, 0x2E7D4F, 0x7A4A2A)
            CALLIGRAPHY -> p(0x111111, 0x8C1C13, 0x1B3A6B, 0xA77B12, 0x2F4F2F, 0x5B2A86)
            WATERCOLOR -> p(0x3A7BD5, 0xE4572E, 0x29A36A, 0xF2B134, 0x8E44AD, 0xE76F99)
            NEON -> p(0xFF2E88, 0x00D9FF, 0x39FF14, 0xFFE600, 0xB026FF, 0xFF6B00)
            RAINBOW -> p(0xF23030, 0xFFA8C5, 0x8C1A1A, 0xFF7A00, 0x9B5CFF, 0x22C1C3)
            GLITTER -> p(0xD4AF37, 0xB8BCC6, 0xE0115F, 0x1E90FF, 0x2FBF71, 0x9966CC)
            GRASS -> p(0x3F9B2F, 0x2E7D32, 0x7CB342, 0x8D9E2B, 0xC28E2B, 0x1B5E20)
            SEA -> p(0x0B5FA5, 0x0A8F9E, 0x1C3F94, 0x2BB0D6, 0x2E8B57, 0x5B3FD1)
            LAVA -> p(0xFF5A1F, 0xFF2D2D, 0xFFB020, 0x7A3CFF, 0x23C7FF, 0x3DFF7A)
            FOUNTAIN -> p(0x1F3FBF, 0x15161A, 0x7B1230, 0x0E6B4E, 0x6B4423, 0x4B2A9C)
            GOLD -> p(0xD4A537, 0xE0A090, 0xC9CED6, 0xC0703A, 0x9C7A3C, 0xE5E4E2)
            CHROME -> p(0xC8D0DA, 0x3A3F47, 0x5A8BD6, 0xE58FB0, 0xE8C66A, 0x9FE3D9)
            ICE -> p(0x9FE6FF, 0xE6FBFF, 0x7FD3D9, 0xB7B4FF, 0x9EF0C8, 0xFFB3D1)
            JELLY -> p(0xFF3B6B, 0xFF9F1C, 0x42D96B, 0x3AA0FF, 0xB45CFF, 0xFFE14D)
            GALAXY -> p(0x6A2CFF, 0x1E3CFF, 0xFF3CAC, 0x00C2C7, 0xFF7A3C, 0x9AA0B5)
            LIGHTNING -> p(0x7FD4FF, 0xC08BFF, 0xFFE45C, 0x6BFF9E, 0xFF6BD0, 0xFFFFFF)
            PEARL -> p(0xF4EFE6, 0xF2D0D9, 0x2C2F3A, 0xE8D59E, 0xBFD7EA, 0xD8C8F0)
            IMPASTO -> p(0xD7263D, 0x1B998B, 0xF46036, 0x2E294E, 0xF2C14E, 0x3D5A80)
            BLOOM -> p(0x22B8CF, 0x2EC4B6, 0x3A8DFF, 0x7FD3F7, 0x6C7BFF, 0x14A3A3)
        }

    companion object {
        /** Order in the pen panel and the toolbar. */
        val paletteOrder: List<Brush> = listOf(
            PEN, PENCIL, FOUNTAIN, CALLIGRAPHY, HIGHLIGHTER,
            WATERCOLOR, IMPASTO, WET, NEON, RAINBOW, GLITTER,
            SEA, WAVE, GRASS, BLOOM, LAVA, ICE, LIGHTNING, GALAXY,
            GOLD, CHROME, PEARL, JELLY,
        )

        /** Unknown raw values (a newer app's pens) read as the plain pen. */
        fun fromRaw(raw: Int): Brush = entries.firstOrNull { it.raw == raw } ?: PEN

        private fun p(vararg hexes: Int) = hexes.map { InkColor.hex(it) }
    }
}

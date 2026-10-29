package com.murekkep.notebook.ui

import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import com.murekkep.notebook.data.OutlineEntry
import org.junit.Assert.assertEquals
import org.junit.Test

// The page navigator's rules: the page a typed number goes to, against the answers of the iPad's
// own PageNavigator.pageIndex (copied verbatim into a Swift file and run with the Windows Swift
// toolchain, 2026-10-30: Swift's Int reads an optional sign and ASCII digits only, 64 bits wide,
// after spaces and tabs are trimmed); the contents' rows as their headings are opened; and where the
// navigator stands: above the badge, inside the window and clear of a bar at either side.
class PageNavigationTest {
    @Test
    fun aTypedNumberGoesWhereTheIPadGoes() {
        val cases = listOf(
            Triple("", 5, null),
            Triple("1", 5, 0),
            Triple("3", 5, 2),
            Triple("5", 5, 4),
            Triple("6", 5, 4),
            Triple("0", 5, 0),
            Triple("-2", 5, 0),
            Triple("+2", 5, 1),
            Triple(" 4 ", 5, 3),
            Triple("\t2", 5, 1),
            Triple("2\n", 5, null),
            Triple("abc", 5, null),
            Triple("2a", 5, null),
            Triple("2.5", 5, null),
            Triple("1e2", 5, null),
            Triple("99999999999", 5, 4),
            Triple("99999999999999999999", 5, null),
            Triple("3", 0, null),
            Triple("1", 1, 0),
            Triple(" 3", 5, 2),
            Triple("٣", 5, null),
            Triple("３", 5, null),
            Triple("- 2", 5, null),
            Triple("--2", 5, null),
            Triple("007", 5, 4),
            Triple("12", 40, 11),
            Triple(" ", 5, null),
            Triple("+", 5, null),
            Triple("-", 5, null),
            Triple(" 7 ", 9, 6),
            Triple("9223372036854775807", 3, 2),
            Triple("-9223372036854775808", 3, 0),
        )
        for ((text, count, page) in cases) {
            assertEquals("\"$text\" of $count", page, PageNavigation.pageIndex(text, count))
        }
    }

    private val contents = listOf(
        OutlineEntry("A", 0, listOf(OutlineEntry("A1", 1, null), OutlineEntry("A2", 2, listOf(OutlineEntry("A2a", 3, null))))),
        OutlineEntry("B", 4, null),
        OutlineEntry("C", null, listOf(OutlineEntry("C1", 5, null))),
    )

    private fun rows(vararg open: List<Int>) =
        PageNavigation.outlineRows(contents, open.toSet()).map { Triple(it.entry.title, it.depth, it.path) }

    @Test
    fun theContentsShowTheHeadingsUnderTheOnesOpened() {
        assertEquals(listOf(Triple("A", 0, listOf(0)), Triple("B", 0, listOf(1)), Triple("C", 0, listOf(2))), rows())
        assertEquals(
            listOf(
                Triple("A", 0, listOf(0)),
                Triple("A1", 1, listOf(0, 0)),
                Triple("A2", 1, listOf(0, 1)),
                Triple("A2a", 2, listOf(0, 1, 0)),
                Triple("B", 0, listOf(1)),
                Triple("C", 0, listOf(2)),
                Triple("C1", 1, listOf(2, 0)),
            ),
            rows(listOf(0), listOf(0, 1), listOf(2)),
        )
        // Under a closed heading nothing shows, even a heading left open there; a heading without
        // headings under it opens nothing.
        assertEquals(listOf("A", "B", "C"), rows(listOf(0, 1), listOf(1)).map { it.first })
    }

    @Test
    fun theNavigatorStandsAboveTheBadgeClearOfTheBarsAtTheSides() {
        // In pixels: a 40 px shadow margin round a 400 by 300 card, 12 above its anchor, 8 from the edges.
        val content = IntSize(480, 380)
        fun card(anchor: IntRect, left: Int, right: Int, window: IntSize = IntSize(1000, 700)): Pair<Int, Int> {
            val at = AboveAnchor(pad = 40, gap = 12, margin = 8, leftInset = left, rightInset = right)
                .calculatePosition(anchor, window, LayoutDirection.Ltr, content)
            return (at.x + 40) to (at.y + 40)
        }
        // Centred over a badge in the middle, 12 above it.
        assertEquals(300 to 188, card(IntRect(480, 500, 520, 544), left = 0, right = 0))
        // A badge at the right edge: the card ends 8 short of the window, or of a navigation bar there.
        assertEquals(592 to 188, card(IntRect(900, 500, 960, 544), left = 0, right = 0))
        assertEquals(544 to 188, card(IntRect(860, 500, 920, 544), left = 0, right = 48))
        // A bar or a cutout on the left: the card starts 8 past it.
        assertEquals(56 to 188, card(IntRect(20, 500, 80, 544), left = 48, right = 0))
        // Too narrow a window for the card between the bars: it starts past the left one.
        assertEquals(56 to 188, card(IntRect(200, 500, 260, 544), left = 48, right = 48, window = IntSize(450, 700)))
        // Never above the window's top.
        assertEquals(300 to 8, card(IntRect(480, 100, 520, 144), left = 0, right = 0))
    }
}

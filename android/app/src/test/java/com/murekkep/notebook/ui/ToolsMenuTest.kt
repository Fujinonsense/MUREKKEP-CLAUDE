package com.murekkep.notebook.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InstrumentKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode

// The pen bar's Araçlar as the iPad's toolsMenu: the instruments' submenu lays one on the page and
// checks it, then offers Açıyı ayarla and Kaldır; Pergel picks the compass and, picked again, goes
// back to the last pen; the button stands out while either is in use. On the real bar, in English.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w1280dp-h800dp")
// Conscrypt's native library is looked up by a name lower-cased in the machine's language, which a
// Turkish JVM spells "wındows": the bar needs no TLS, so the test runs without it.
@ConscryptMode(ConscryptMode.Mode.OFF)
class ToolsMenuTest {
    @get:Rule
    val compose = createComposeRule()

    private fun show(state: EditorState) {
        compose.setContent {
            MurekkepTheme {
                Box(Modifier.fillMaxSize()) {
                    PenBar(
                        state,
                        popoverRoom = 600.dp,
                        onGripMove = { _, _ -> },
                        onGripDrop = {},
                        onGripCancel = {},
                        modifier = Modifier.align(Alignment.BottomCenter),
                    )
                }
            }
        }
        compose.waitForIdle()
    }

    private fun openTools() {
        compose.onNodeWithContentDescription("Tools").performClick()
        compose.waitForIdle()
    }

    private fun tap(text: String) {
        compose.onNodeWithText(text).performClick()
        compose.waitForIdle()
    }

    private fun gone(text: String) {
        assertTrue("$text is not shown", compose.onAllNodes(hasText(text)).fetchSemanticsNodes().isEmpty())
    }

    private val toolsSelected get() = compose.onAllNodes(hasContentDescription("Tools") and isSelected()).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun theInstrumentsLieOnThePageTurnAndGo() {
        val state = EditorState()
        show(state)
        // Araçlar stands between Şekiller and Sayfa ekle, as on the iPad.
        val shapes = compose.onNode(hasContentDescription("Shape:", substring = true)).fetchSemanticsNode().boundsInRoot
        val tools = compose.onNodeWithContentDescription("Tools").fetchSemanticsNode().boundsInRoot
        val addPage = compose.onNodeWithContentDescription("Add page").fetchSemanticsNode().boundsInRoot
        assertTrue(shapes.right <= tools.left && tools.right <= addPage.left)
        assertTrue(!toolsSelected)
        openTools()
        tap("Ruler, set square and protractor")
        // Nothing on the page yet: the four instruments only.
        for (name in listOf("Ruler", "Set square 45°", "Set square 30°/60°", "Protractor")) {
            compose.onNodeWithText(name).assertExists()
        }
        gone("Set angle")
        gone("Remove")
        tap("Ruler")
        assertEquals(InstrumentKind.RULER, state.instrumentKind)
        // The menu closed, and the button stands out.
        gone("Protractor")
        compose.onNodeWithContentDescription("Tools").assertIsSelected()

        openTools()
        tap("Ruler, set square and protractor")
        tap("Set angle")
        for (d in listOf(0, 15, 30, 45, 60, 75, 90, 120, 135, 150)) compose.onNodeWithText("$d°").assertExists()
        tap("30°")
        assertEquals(30, state.instrument!!.degrees)

        // Another instrument takes the ruler's place and turn.
        openTools()
        tap("Ruler, set square and protractor")
        tap("Protractor")
        assertEquals(InstrumentKind.PROTRACTOR, state.instrumentKind)
        assertEquals(30, state.instrument!!.degrees)

        openTools()
        tap("Ruler, set square and protractor")
        tap("Remove")
        assertNull(state.instrument)
        assertTrue(!toolsSelected)
    }

    @Test
    fun aSubmenuGoesBackToTheMenu() {
        val state = EditorState()
        show(state)
        openTools()
        tap("Ruler, set square and protractor")
        gone("Compass")
        // Its first row is its title: a tap goes back.
        tap("Ruler, set square and protractor")
        compose.onNodeWithText("Compass").assertExists()
        gone("Protractor")
    }

    @Test
    fun pergelPicksTheCompassAndPickedAgainTheLastPen() {
        val state = EditorState()
        state.tool = Tool.Brush(Brush.PENCIL)
        show(state)
        openTools()
        tap("Compass")
        assertEquals(Tool.Compass, state.tool)
        compose.onNodeWithContentDescription("Tools").assertIsSelected()
        openTools()
        tap("Compass")
        assertEquals(Tool.Brush(Brush.PENCIL), state.tool)
        assertTrue(!toolsSelected)
    }
}

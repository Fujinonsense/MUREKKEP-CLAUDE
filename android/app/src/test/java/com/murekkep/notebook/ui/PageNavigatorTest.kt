package com.murekkep.notebook.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.render.PageSize
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageFitDestination
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDDocumentOutline
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode

// The page navigator the page badge opens (PageNavigator.swift): a number typed offers Go, which
// goes there and closes it; a page's picture goes to its page; the ribbon bookmarks the page in
// view and Bookmarks lists it (a hint while there are none); only an imported PDF has Contents, its
// headings open under their disclosure arrow and go to their pages, and a PDF without them says so.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w1280dp-h800dp")
// Conscrypt's native library is looked up by a name lower-cased in the machine's language, which a
// Turkish JVM spells "wındows": the screen needs no TLS, so the test runs without it.
@ConscryptMode(ConscryptMode.Mode.OFF)
class PageNavigatorTest {
    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    private var closed = 0
    private val jumps = ArrayList<Int>()

    private fun notebook(pages: Int, current: Int = 0) =
        EditorState(initialPages = List(pages) { emptyList() }).also { it.currentPage = current }

    private fun show(state: EditorState) {
        state.onScrollRequest = { jumps += it }
        compose.setContent {
            MurekkepTheme {
                Box(Modifier.fillMaxSize()) { PageNavigator(state, 400.dp, 580.dp) { closed++ } }
            }
        }
    }

    @Test
    fun aNumberTypedOffersGoWhichGoesThereAndCloses() {
        show(notebook(5, current = 1))
        compose.onAllNodesWithText("Go").assertCountEquals(0)
        compose.onNode(hasSetTextAction()).performTextInput("9")
        // Past the end: the last page.
        compose.onNodeWithText("Go").performClick()
        assertEquals(listOf(4), jumps)
        assertEquals(1, closed)
    }

    @Test
    fun aPagesPictureGoesToIt() {
        show(notebook(5))
        compose.onNodeWithContentDescription("Page 3").performClick()
        assertEquals(listOf(2), jumps)
        assertEquals(1, closed)
    }

    @Test
    fun theRibbonBookmarksThePageInViewAndBookmarksListsIt() {
        val state = notebook(4, current = 2)
        show(state)
        compose.onNodeWithText("Bookmarks").performClick()
        compose.onNodeWithText("No bookmarks yet. Tap the ribbon at the top right to bookmark this page.").assertIsDisplayed()
        compose.onNodeWithContentDescription("Bookmark this page").performClick()
        assertEquals(listOf(2), state.bookmarks)
        compose.onNodeWithContentDescription("Remove bookmark").assertIsDisplayed()
        compose.onNodeWithContentDescription("Page 3").assertIsDisplayed()
        compose.onAllNodesWithContentDescription("Page 1").assertCountEquals(0)
        assertEquals(0, closed)
    }

    @Test
    fun aNotebookHasNoContents() {
        show(notebook(2))
        compose.onNodeWithText("Pages").assertIsDisplayed()
        compose.onAllNodesWithText("Contents").assertCountEquals(0)
    }

    @Test
    fun aPdfWithoutHeadingsSaysSo() {
        // Its file is missing (the note opened read-only): no headings either.
        show(EditorState(initialPages = List(2) { emptyList() }, pageSizes = listOf(PageSize.A4, PageSize.A4)))
        compose.onNodeWithText("Contents").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("This PDF has no table of contents.").fetchSemanticsNodes().isNotEmpty() }
    }

    @Test
    fun aPdfsHeadingsOpenAndGoToTheirPages() {
        val file = File(folder.root, "book.pdf")
        PDDocument().use { doc ->
            repeat(3) { doc.addPage(PDPage(PDRectangle.A4)) }
            fun to(index: Int): PDPageFitDestination {
                val target = doc.getPage(index)
                return PDPageFitDestination().apply { page = target }
            }
            val outline = PDDocumentOutline()
            val chapter = PDOutlineItem().apply { title = "Chapter 1"; destination = to(0) }
            chapter.addLast(PDOutlineItem().apply { title = "Section"; destination = to(1) })
            outline.addLast(chapter)
            outline.addLast(PDOutlineItem().apply { title = "Chapter 2"; destination = to(2) })
            doc.documentCatalog.documentOutline = outline
            doc.save(file)
        }
        show(EditorState(initialPages = List(3) { emptyList() }, pageSizes = List(3) { PageSize.A4 }, pdfFile = file))
        compose.onNodeWithText("Contents").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Chapter 2")).fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodes(hasText("Section")).assertCountEquals(0)
        compose.onNode(hasContentDescription("Chapter 1") and hasClickAction()).performClick()
        compose.onNode(hasText("Section")).performClick()
        assertEquals(listOf(1), jumps)
        assertEquals(1, closed)
    }
}

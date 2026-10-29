package com.murekkep.notebook.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.isPopup
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.style.TextOverflow
import androidx.test.core.app.ApplicationProvider
import com.murekkep.notebook.data.LibraryImport
import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NotebookMeta
import com.murekkep.notebook.data.NotebookStore
import com.murekkep.notebook.data.PaperStyle
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import java.io.File

// The courses on the library's screen (LibraryView and LibraryPanes on iPad): the sidebar's rows with
// their counts open a course's pane, whose tabs split its PDFs from its notebooks; the + makes a
// course in the editor and opens it; a note's menu moves it into a course and out again; Diğer edits
// and deletes a course, whose notes stay; a search finds a course by its name, with its notes. A
// note made in a course is named after it and filed there; a course row's long press makes a
// notebook in it, edits it and deletes it; the course and its tab come back after a relaunch.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w1280dp-h800dp")
// Conscrypt's native library is looked up by a name lower-cased in the machine's language, which a
// Turkish JVM spells "wındows": the screen needs no TLS, so the test runs without it.
@ConscryptMode(ConscryptMode.Mode.OFF)
class CoursesScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val root: File get() = File(context.filesDir, "notebooks")
    private val biology = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

    @Before
    fun library() {
        // Each test reads its own folders: the store and the importer are one per process.
        for (holder in listOf(NotebookStore::class.java, LibraryImport::class.java)) {
            holder.getDeclaredField("shared").apply { isAccessible = true }.set(null, null)
        }
        val now = System.currentTimeMillis()
        write(note("Cell notes", NoteKind.NOTEBOOK, now - 3_000, biology))
        write(note("Derivatives", NoteKind.NOTEBOOK, now - 2_000))
        write(note("Biology PDF", NoteKind.PDF, now - 1_000, biology))
        File(root, "sections.json").writeText(
            """[{"id":"$biology","name":"Biology","symbol":"leaf","colorIndex":3,"created":"2026-10-26T10:00:00Z"}]""",
        )
    }

    private fun note(title: String, kind: NoteKind, modified: Long, course: String? = null) = NotebookMeta(
        id = title.replace(' ', '-'), title = title, created = modified, modified = modified, pageCount = 2,
        paper = PaperStyle.LINED, kind = kind, sectionId = course,
    )

    private fun write(meta: NotebookMeta) {
        File(root, meta.id).apply { mkdirs() }.resolve("meta.json").writeText(meta.toJson().toString())
    }

    private fun record(id: String) = JSONObject(File(root, "$id/meta.json").readText())

    private fun courseNames(): List<String> {
        val list = JSONArray(File(root, "sections.json").readText())
        return (0 until list.length()).map { list.getJSONObject(it).getString("name") }
    }

    private fun show(onOpen: (NotebookMeta) -> Unit = {}, until: String = "Biology PDF") {
        val store = NotebookStore.get(context)
        compose.setContent { MurekkepTheme { LibraryScreen(store = store, onOpen = onOpen) } }
        compose.waitUntil(5_000) { compose.onAllNodes(hasText(until)).fetchSemanticsNodes().isNotEmpty() }
    }

    /** A row of the sidebar: a button that can be selected, named [name]. */
    private fun sidebarRow(name: String): SemanticsMatcher =
        hasText(name) and
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button) and
            SemanticsMatcher.keyIsDefined(SemanticsProperties.Selected)

    private fun tab(name: String): SemanticsMatcher = hasText(name) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)

    private fun menuItem(name: String): SemanticsMatcher = hasText(name) and hasAnyAncestor(isPopup())

    private fun shows(title: String) = compose.onAllNodes(hasText(title)).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun aCoursesRowOpensItsPaneAndItsTabsSplitItsNotes() {
        show()
        // The row counts the course's notes.
        compose.onNode(sidebarRow("Biology") and hasText("2")).assertIsDisplayed()
        compose.onNode(sidebarRow("Biology")).performClick()
        compose.waitForIdle()
        compose.onNode(sidebarRow("Biology")).assertIsSelected()
        compose.onNode(sidebarRow("All notes")).assertIsNotSelected()
        compose.onNode(isHeading()).assertTextEquals("Biology")
        compose.onNodeWithText("1 source · 1 notebook").assertIsDisplayed()
        // Kaynaklar: the course's PDFs under its drop zone.
        compose.onNode(tab("Sources")).assertIsSelected()
        compose.onNodeWithText("Drag this course's PDFs here").assertIsDisplayed()
        assertTrue(shows("Biology PDF"))
        assertTrue(!shows("Cell notes") && !shows("Derivatives"))
        // Defterler: its notebooks.
        compose.onNode(tab("Notebooks")).performClick()
        compose.waitForIdle()
        compose.onNodeWithText("1 notebook").assertIsDisplayed()
        assertTrue(shows("Cell notes"))
        assertTrue(!shows("Biology PDF") && !shows("Derivatives"))
        // Back to a list.
        compose.onNode(sidebarRow("All notes")).performClick()
        compose.waitForIdle()
        compose.onNode(isHeading()).assertTextEquals("All notes")
        compose.onNode(sidebarRow("Biology")).assertIsNotSelected()
    }

    @Test
    fun theEditorMakesACourseAndOpensIt() {
        show()
        compose.onNodeWithContentDescription("New course").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("New section").assertIsDisplayed()
        // No name, no course.
        compose.onNodeWithText("Create").assertIsNotEnabled()
        compose.onNode(hasSetTextAction() and hasContentDescription("Section name (e.g. Calculus, Anatomy)")).performTextInput("Anatomy")
        compose.onNodeWithText("Create").assertIsEnabled().performClick()
        compose.waitForIdle()
        compose.onNode(isHeading()).assertTextEquals("Anatomy")
        compose.onNode(sidebarRow("Anatomy")).assertIsSelected()
        compose.onNodeWithText("0 sources · 0 notebooks").assertIsDisplayed()
        compose.waitUntil(5_000) { courseNames() == listOf("Biology", "Anatomy") }
    }

    @Test
    fun aNoteMovesIntoACourseAndOutAgainFromItsMenu() {
        show()
        compose.onNodeWithText("Derivatives").performTouchInput { longClick() }
        compose.onNodeWithText("Move to course").performClick()
        compose.waitForIdle()
        // The course's own note would be ticked; this one is in none, so there is nothing to leave.
        assertTrue(compose.onAllNodes(menuItem("Remove from course")).fetchSemanticsNodes().isEmpty())
        compose.onNode(menuItem("Biology")).performClick()
        compose.waitUntil(5_000) { record("Derivatives").optString("sectionID") == biology }
        compose.onNode(sidebarRow("Biology") and hasText("3")).assertIsDisplayed()

        compose.onNodeWithText("Derivatives").performTouchInput { longClick() }
        compose.onNodeWithText("Move to course").performClick()
        compose.onNode(menuItem("Remove from course")).performClick()
        compose.waitUntil(5_000) { !record("Derivatives").has("sectionID") }
        compose.onNode(sidebarRow("Biology") and hasText("2")).assertIsDisplayed()
    }

    @Test
    fun theFirstCoursePromptWaitsForTheFirstRead() {
        var loaded by mutableStateOf(false)
        val actions = CourseActions(create = {}, edit = {}, delete = {}, import = {}, newNotebook = {}, drop = { _, _, _ -> })
        compose.setContent { MurekkepTheme { CourseList(emptyList(), emptyMap(), null, {}, actions, loaded = loaded) } }
        // Before the disk is read there may well be courses on it: no prompt for the first one.
        compose.onNodeWithText("Courses").assertIsDisplayed()
        assertTrue(compose.onAllNodes(hasText("Add your first course")).fetchSemanticsNodes().isEmpty())
        loaded = true
        compose.onNodeWithText("Add your first course").assertIsDisplayed()
    }

    @Test
    fun theMoveMenusTitleSaysItGoesBack() {
        show()
        compose.onNodeWithText("Derivatives").performTouchInput { longClick() }
        compose.onNodeWithText("Move to course").performClick()
        compose.waitForIdle()
        // TalkBack hears what the title does, not only the name of the action just chosen.
        val title = compose.onNode(menuItem("Move to course"))
        title.assert(SemanticsMatcher("goes back") { it.config.getOrNull(SemanticsActions.OnClick)?.label == "Back" })
        title.performClick()
        compose.waitForIdle()
        compose.onNode(menuItem("Rename")).assertIsDisplayed()
    }

    @Test
    fun aNoteMadeInACourseIsNamedAfterItAndFiledThere() {
        val opened = ArrayList<NotebookMeta>()
        show(onOpen = { opened.add(it) })
        compose.onNode(sidebarRow("Biology")).performClick()
        compose.onNodeWithText("New note").performClick()
        compose.onNode(hasText("Grid") and hasClickAction()).performClick()
        compose.waitForIdle()
        // "Biology" and the moment, as the iPad's createNotebook names it, and opened at once.
        val made = opened.single()
        assertTrue(made.title, made.title.startsWith("Biology "))
        assertEquals(biology, made.sectionId)
        assertEquals(PaperStyle.GRID, made.paper)
        compose.waitUntil(5_000) { File(root, "${made.id}/meta.json").isFile && record(made.id).optString("sectionID") == biology }
        compose.onNode(sidebarRow("Biology") and hasText("3")).assertIsDisplayed()
    }

    @Test
    fun aCoursesRowMenuMakesANotebookEditsAndDeletesIt() {
        val opened = ArrayList<NotebookMeta>()
        show(onOpen = { opened.add(it) })
        // Yeni defter, from the row's menu while another list is on screen.
        compose.onNode(sidebarRow("Biology")).performTouchInput { longClick() }
        compose.onNode(menuItem("New notebook")).performClick()
        compose.onNode(hasText("Lined") and hasClickAction()).performClick()
        compose.waitForIdle()
        assertTrue(opened.single().title.startsWith("Biology "))
        assertEquals(biology, opened.single().sectionId)
        // Düzenle.
        compose.onNode(sidebarRow("Biology")).performTouchInput { longClick() }
        compose.onNode(menuItem("Edit")).performClick()
        compose.waitForIdle()
        val field = compose.onNode(hasSetTextAction() and hasContentDescription("Section name (e.g. Calculus, Anatomy)"))
        field.assertTextEquals("Biology")
        field.performTextClearance()
        field.performTextInput("Botany")
        compose.onNodeWithText("Save").performClick()
        compose.waitForIdle()
        compose.onNode(sidebarRow("Botany")).assertIsDisplayed()
        compose.waitUntil(5_000) { courseNames() == listOf("Botany") }
        // Dersi sil: it asks, and the notes stay.
        compose.onNode(sidebarRow("Botany")).performTouchInput { longClick() }
        compose.onNode(menuItem("Delete course (its contents stay)")).performClick()
        compose.onNodeWithText("Delete course").performClick()
        compose.waitForIdle()
        assertTrue(compose.onAllNodes(sidebarRow("Botany")).fetchSemanticsNodes().isEmpty())
        compose.waitUntil(5_000) { courseNames().isEmpty() && !record("Cell-notes").has("sectionID") }
        assertTrue(shows("Cell notes") && shows("Biology PDF"))
    }

    @Test
    fun theCourseAndItsTabComeBackAfterARelaunch() {
        val prefs = context.getSharedPreferences("library", Context.MODE_PRIVATE)
        // As the last launch left them (the iPad's library.place and course.tab).
        prefs.edit().putString("library.place", "course:$biology").putString("course.tab", "notebooks").commit()
        show(until = "Cell notes")
        compose.onNode(isHeading()).assertTextEquals("Biology")
        compose.onNode(sidebarRow("Biology")).assertIsSelected()
        compose.onNode(tab("Notebooks")).assertIsSelected()
        assertTrue(!shows("Biology PDF"))
        // A tab picked is kept for the next launch, and so is a list.
        compose.onNode(tab("Sources")).performClick()
        compose.waitForIdle()
        assertEquals("sources", prefs.getString("course.tab", null))
        compose.onNode(sidebarRow("All notes")).performClick()
        compose.waitForIdle()
        assertEquals("home", prefs.getString("library.place", null))
    }

    @Test
    fun theNameHintIsCutWithAnEllipsis() {
        show()
        compose.onNodeWithContentDescription("New course").performClick()
        compose.waitForIdle()
        val hint = compose.onNodeWithText("Section name (e.g. Calculus, Anatomy)", useUnmergedTree = true).fetchSemanticsNode()
        val layouts = ArrayList<TextLayoutResult>()
        hint.config[SemanticsActions.GetTextLayoutResult].action!!(layouts)
        // One line, cut with an ellipsis where a phone's field ends (as the iPad's placeholder), not
        // after its last whole word. Robolectric measures no real glyphs, so the test reads how the
        // hint asks to be laid out rather than where it is cut.
        val input = layouts.single().layoutInput
        assertEquals(TextOverflow.Ellipsis, input.overflow)
        assertFalse(input.softWrap)
        assertEquals(1, input.maxLines)
    }

    @Test
    fun deletingACourseAsksAndLeavesItsNotes() {
        show()
        compose.onNode(sidebarRow("Biology")).performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNode(menuItem("Delete course (its contents stay)")).performClick()
        compose.onNodeWithText("Delete this course?").assertIsDisplayed()
        compose.onNodeWithText("Only the course folder is removed; its notebooks and PDFs stay in the library.").assertIsDisplayed()
        compose.onNodeWithText("Delete course").performClick()
        compose.waitForIdle()
        // Back on Tüm notlar, every note still there; the course gone from the sidebar and the disk.
        compose.onNode(isHeading()).assertTextEquals("All notes")
        for (title in listOf("Cell notes", "Derivatives", "Biology PDF")) assertTrue(title, shows(title))
        assertTrue(compose.onAllNodes(sidebarRow("Biology")).fetchSemanticsNodes().isEmpty())
        compose.onNodeWithText("Add your first course").assertIsDisplayed()
        compose.waitUntil(5_000) { courseNames().isEmpty() && !record("Cell-notes").has("sectionID") }
    }

    @Test
    fun aCourseIsRenamedInItsEditor() {
        show()
        compose.onNode(sidebarRow("Biology")).performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNode(menuItem("Edit course")).performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Edit section").assertIsDisplayed()
        val field = compose.onNode(hasSetTextAction() and hasContentDescription("Section name (e.g. Calculus, Anatomy)"))
        field.assertTextEquals("Biology")
        field.performTextClearance()
        compose.onNodeWithText("Save").assertIsNotEnabled()
        field.performTextInput("Botany")
        compose.onNodeWithText("Save").performClick()
        compose.waitForIdle()
        compose.onNode(isHeading()).assertTextEquals("Botany")
        compose.waitUntil(5_000) { courseNames() == listOf("Botany") }
    }

    @Test
    fun aSearchFindsACourseByItsNameWithItsNotes() {
        show()
        compose.onNode(hasSetTextAction() and hasContentDescription("Search")).performTextInput("biol")
        compose.waitForIdle()
        // The course and its two notes ("Biology PDF" by its title too); "Derivatives" is in no course.
        compose.onNodeWithText("3 results").assertIsDisplayed()
        // "Courses" over the pane's capsules, besides the sidebar's.
        assertEquals(2, compose.onAllNodes(hasText("Courses")).fetchSemanticsNodes().size)
        assertTrue(shows("Cell notes") && shows("Biology PDF"))
        assertTrue(!shows("Derivatives"))
        val chip = hasText("Biology") and SemanticsMatcher.keyNotDefined(SemanticsProperties.Selected) and
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
        compose.onNode(chip).performClick()
        compose.waitForIdle()
        // The chip opens the course, and the search is over.
        compose.onNode(isHeading()).assertTextEquals("Biology")
        compose.onNode(sidebarRow("Biology")).assertIsSelected()
    }

    @Test
    @Config(qualifiers = "w560dp-h1600dp")
    fun aCoursePickedInTheDrawerClosesIt() {
        show()
        compose.onNodeWithContentDescription("Show sidebar").performClick()
        compose.waitForIdle()
        compose.onNode(sidebarRow("Biology")).performClick()
        compose.waitForIdle()
        compose.onNode(isHeading()).assertTextEquals("Biology")
        // The drawer closed: its rows are out of sight.
        compose.onNode(sidebarRow("Biology")).assertIsNotDisplayed()
    }
}

package com.murekkep.notebook.ui

import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.test.core.app.ApplicationProvider
import com.murekkep.notebook.data.LibraryImport
import com.murekkep.notebook.data.NoteKind
import com.murekkep.notebook.data.NotebookMeta
import com.murekkep.notebook.data.NotebookStore
import com.murekkep.notebook.data.PaperStyle
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import java.io.File

// The library's sidebar drives its notes pane (R2-01): every row picked shows that section's title
// and only its notes at once, in the wide layout and from the narrow layout's drawer. The pane used
// to keep the section it opened on until something else redrew it. And a note's menu stars it
// (R2-05): Favoriler shows it, its card wears the star, its record keeps it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
// Conscrypt's native library is looked up by a name lower-cased in the machine's language, which a
// Turkish JVM spells "wındows": the screen needs no TLS, so the test runs without it.
@ConscryptMode(ConscryptMode.Mode.OFF)
class LibraryScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before
    fun library() {
        // Each test reads its own folders: the store and the importer are one per process.
        for (holder in listOf(NotebookStore::class.java, LibraryImport::class.java)) {
            holder.getDeclaredField("shared").apply { isAccessible = true }.set(null, null)
        }
        val now = System.currentTimeMillis()
        write(note("Cell notes", NoteKind.NOTEBOOK, now - 3_000))
        write(note("Derivatives", NoteKind.NOTEBOOK, now - 2_000, starred = true))
        write(note("Biology PDF", NoteKind.PDF, now - 1_000))
    }

    private fun note(title: String, kind: NoteKind, modified: Long, starred: Boolean = false) = NotebookMeta(
        id = title.replace(' ', '-'), title = title, created = modified, modified = modified, pageCount = 2,
        paper = PaperStyle.LINED, kind = kind, starred = starred,
    )

    private fun folder(id: String) = File(context.filesDir, "notebooks/$id")

    private fun write(meta: NotebookMeta) {
        val dir = folder(meta.id).apply { mkdirs() }
        File(dir, "meta.json").writeText(meta.toJson().toString())
    }

    private fun show() {
        val store = NotebookStore.get(context)
        compose.setContent { MurekkepTheme { LibraryScreen(store = store, onOpen = {}) } }
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Biology PDF")).fetchSemanticsNodes().isNotEmpty() }
    }

    /** Each section, the notes it shows, in the order the test picks them (back to one already seen too). */
    private val sections = listOf(
        "Notebooks" to listOf("Derivatives", "Cell notes"),
        "PDFs" to listOf("Biology PDF"),
        "Favorites" to listOf("Derivatives"),
        "Recently opened" to listOf("Biology PDF", "Derivatives", "Cell notes"),
        "All notes" to listOf("Biology PDF", "Derivatives", "Cell notes"),
        "PDFs" to listOf("Biology PDF"),
    )

    @Test
    @Config(qualifiers = "w1280dp-h800dp")
    fun eachSidebarRowShowsItsSectionInTheWideLayout() {
        show()
        for ((section, titles) in sections) pick(section, titles)
    }

    @Test
    @Config(qualifiers = "w560dp-h1600dp")
    fun eachDrawerRowShowsItsSectionInTheNarrowLayout() {
        show()
        for ((section, titles) in sections) {
            compose.onNodeWithContentDescription("Show sidebar").performClick()
            pick(section, titles)
        }
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp")
    fun aNoteStarredFromItsMenuIsAFavorite() {
        show()
        compose.onNodeWithText("Cell notes").performTouchInput { longClick() }
        compose.onNodeWithText("Add to favorites").performClick()
        pick("Favorites", listOf("Derivatives", "Cell notes"))
        // Both cards wear the star; the record on disk keeps it.
        assertEquals(2, compose.onAllNodes(hasContentDescription("Favorite", substring = true)).fetchSemanticsNodes().size)
        compose.waitUntil(5_000) { JSONObject(File(folder("Cell-notes"), "meta.json").readText()).optBoolean("isFavorite") }
        // Taken away again, it leaves Favoriler.
        compose.onNodeWithText("Cell notes").performTouchInput { longClick() }
        compose.onNodeWithText("Remove from favorites").performClick()
        compose.waitForIdle()
        assertTrue(compose.onAllNodes(hasText("Cell notes")).fetchSemanticsNodes().isEmpty())
    }

    /** Settings › Display size (R2-02): the window keeps its pixels while its width in dp changes, and
     *  the library goes from the sidebar to the drawer and back. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp")
    fun aDisplaySizeChangeSwitchesTheLayout() {
        val store = NotebookStore.get(context)
        var scale by mutableFloatStateOf(1f)
        compose.setContent {
            val base = LocalConfiguration.current
            val density = LocalDensity.current
            val configuration = remember(base, scale) {
                Configuration(base).apply {
                    screenWidthDp = (base.screenWidthDp / scale).toInt()
                    screenHeightDp = (base.screenHeightDp / scale).toInt()
                    densityDpi = (base.densityDpi * scale).toInt()
                }
            }
            CompositionLocalProvider(LocalConfiguration provides configuration, LocalDensity provides Density(density.density * scale, density.fontScale)) {
                MurekkepTheme { LibraryScreen(store = store, onOpen = {}) }
            }
        }
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Biology PDF")).fetchSemanticsNodes().isNotEmpty() }
        // 1280 dp: the sidebar stands beside the notes.
        compose.onNodeWithContentDescription("Show sidebar").assertDoesNotExist()
        // 512 dp: the drawer, with its button in the pane's header.
        scale = 2.5f
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Show sidebar").assertExists()
        compose.onNode(isHeading()).assertTextEquals("All notes")
        // Back to 1280 dp.
        scale = 1f
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Show sidebar").assertDoesNotExist()
    }

    @Test
    fun aStarIsKeptUnderTheIpadsKey() {
        val starred = note("Derivatives", NoteKind.NOTEBOOK, 0L, starred = true)
        assertTrue(starred.toJson().getBoolean("isFavorite"))
        assertTrue(NotebookMeta.fromJson(starred.toJson(), starred.id).starred)
        // A record from before the stars, or the iPad's without the key, is not starred.
        val old = starred.toJson().apply { remove("isFavorite") }
        assertEquals(false, NotebookMeta.fromJson(old, starred.id).starred)
    }

    /** Picks [section] in the sidebar: it is selected, the pane is titled after it and shows [titles] only. */
    private fun pick(section: String, titles: List<String>) {
        compose.waitForIdle()
        compose.onNode(sidebarRow(section)).performClick()
        compose.waitForIdle()
        compose.onNode(sidebarRow(section)).assertIsSelected()
        compose.onNode(isHeading()).assertTextEquals(section)
        for (title in listOf("Cell notes", "Derivatives", "Biology PDF")) {
            if (title in titles) {
                compose.onNodeWithText(title).assertIsDisplayed()
            } else {
                assertTrue("$section shows $title", compose.onAllNodes(hasText(title)).fetchSemanticsNodes().isEmpty())
            }
        }
    }

    /** A row of the sidebar: a button that can be selected, named [name] (the filter's segments are tabs). */
    private fun sidebarRow(name: String): SemanticsMatcher =
        hasText(name) and
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button) and
            SemanticsMatcher.keyIsDefined(SemanticsProperties.Selected)
}

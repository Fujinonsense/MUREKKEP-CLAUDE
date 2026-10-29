package com.murekkep.notebook.data

import android.content.Context
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.core.app.ApplicationProvider
import com.murekkep.notebook.ui.EditorState
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import java.io.File
import java.nio.file.Files

// A note's bookmarks live in its record as the iPad keeps them (NoteMeta.bookmarks: page indices,
// left out when there are none): an iPad record's are read, an open note starts with them, and a
// bookmark set in the editor is in the record at once.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
// Conscrypt's native library is looked up by a name lower-cased in the machine's language, which a
// Turkish JVM spells "wındows": the store needs no TLS, so the test runs without it.
@ConscryptMode(ConscryptMode.Mode.OFF)
class NotebookBookmarksTest {
    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun note(bookmarks: List<Int>) = NotebookMeta(
        id = "marked", title = "Marked", created = 0, modified = 0, pageCount = 3, paper = PaperStyle.LINED, bookmarks = bookmarks,
    )

    @Test
    fun theRecordKeepsTheBookmarksAndLeavesThemOutWhenThereAreNone() {
        val json = note(listOf(0, 2)).toJson()
        assertEquals(listOf(0, 2), NotebookMeta.fromJson(JSONObject(json.toString()), "marked").bookmarks)
        assertFalse(note(emptyList()).toJson().has("bookmarks"))
        // The iPad's record: an array of page indices; an older one has none.
        assertEquals(listOf(1, 4), NotebookMeta.fromJson(JSONObject("""{"title":"T","bookmarks":[1,4]}"""), "x").bookmarks)
        assertEquals(emptyList<Int>(), NotebookMeta.fromJson(JSONObject("""{"title":"T"}"""), "x").bookmarks)
    }

    @Test
    fun anOpenNoteStartsWithItsBookmarksAndKeepsNewOnesInItsRecord() {
        // The store is one per process: this test reads its own folders.
        NotebookStore::class.java.getDeclaredField("shared").apply { isAccessible = true }.set(null, null)
        val dir = File(context.filesDir, "notebooks/marked").apply { mkdirs() }
        File(dir, "meta.json").writeText(note(listOf(2)).toJson().toString())
        val store = NotebookStore.get(context)
        var state: EditorState? = null
        compose.setContent {
            LaunchedEffect(Unit) {
                store.load()
                state = store.open(store.notebook("marked")!!)
            }
        }
        compose.waitUntil(5_000) { state != null }
        assertEquals(listOf(2), state!!.bookmarks)
        compose.runOnIdle { state!!.toggleBookmark(0) }
        // Read through NIO, which lets the store's move replace the file while it is read: on
        // Windows a java.io read in the meantime would make the move fail and the record stay old.
        compose.waitUntil(5_000) {
            JSONObject(String(Files.readAllBytes(File(dir, "meta.json").toPath()))).optJSONArray("bookmarks")?.length() == 2
        }
        assertEquals(listOf(0, 2), store.notebook("marked")!!.bookmarks)
    }
}

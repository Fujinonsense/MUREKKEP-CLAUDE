package com.murekkep.notebook.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.murekkep.notebook.export.FlatInk
import com.murekkep.notebook.export.PaperDrawer
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.render.PageSize
import com.murekkep.notebook.ui.EditorState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import kotlin.math.max

// Notebooks on disk (Murekkep.swiftpm/LibraryStore.swift and the saving part of EditorModel.swift):
// filesDir/notebooks/<uuid>/meta.json and ink.bin, a picture of the first page for the library's
// cover (thumb.jpg, drawn at every save), and for an imported PDF its source.pdf (its cover is the
// PDF's first page). There is no index file: the library is the folders,
// each with its own record, so one damaged record never empties the list. Saves wait for a pause in
// writing (1.2 s, as on iPad), take their snapshot on the main thread and write it on the IO
// dispatcher; the screen asks for a save at once when it leaves or the app goes to the background.

class NotebookStore private constructor(context: Context) {
    private val app: Context = context.applicationContext
    private val root = File(app.filesDir, "notebooks")

    /** Per-pen colors and widths, shared by every editor state the store opens. */
    val penPreferences = PenPreferences(app)

    /** Save jobs: the main-thread part takes the snapshot, the IO part writes it. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val saveJobs = HashMap<String, Job>()

    /** File writes happen one at a time; `writtenSequence` keeps an older snapshot from landing on a newer one. */
    private val writeLock = Any()
    private val writtenSequence = HashMap<String, Long>()
    private var nextSequence = 0L

    /** Each note's newest write on the IO dispatcher: `open` waits for it before it reads the ink. */
    private val writes = HashMap<String, Job>()

    /** Every notebook, newest first. Observable from Compose. */
    var notebooks by mutableStateOf<List<NotebookMeta>>(emptyList())
        private set

    /** The folders have been read once. */
    var loaded by mutableStateOf(false)
        private set

    /** Bumped after a cover (thumb.jpg) is written, so the library reads it again. */
    var coverVersion by mutableStateOf(0)
        private set

    /** The one read of the folders: everyone who needs the list waits for the same one. */
    private var firstLoad: Deferred<Unit>? = null

    companion object {
        private const val SAVE_DELAY_MS = 1200L

        /** The library's picture of a note's first page, in pixels across. */
        private const val THUMB_WIDTH = 360f

        @Volatile
        private var shared: NotebookStore? = null

        /** One store for the process: pending saves outlive the activity. */
        fun get(context: Context): NotebookStore =
            shared ?: synchronized(this) { shared ?: NotebookStore(context).also { shared = it } }
    }

    // MARK: Paths

    fun folder(id: String): File = File(root, id)

    fun metaFile(id: String): File = File(folder(id), "meta.json")

    fun inkFile(id: String): File = File(folder(id), "ink.bin")

    fun pdfFile(id: String): File = File(folder(id), "source.pdf")

    fun thumbFile(id: String): File = File(folder(id), "thumb.jpg")

    fun notebook(id: String): NotebookMeta? = notebooks.firstOrNull { it.id == id }

    // MARK: Library

    /** Reads every notebook's record off the main thread, once per process, and lists them newest
     *  first. After that the list in memory is the newest there is (this store is the folders' only
     *  writer): a later scan could put an older record over a save, or drop a notebook made while it
     *  read the disk, and then that notebook's saves would find no record and write nothing. */
    suspend fun load() {
        val load = firstLoad ?: scope.async {
            val scanned = withContext(Dispatchers.IO) { scan() }
            // Notebooks made while the disk was read stay, with their records from memory.
            val known = notebooks.mapTo(HashSet()) { it.id }
            notebooks = (notebooks + scanned.filter { it.id !in known }).sortedByDescending { it.modified }
            loaded = true
        }.also { firstLoad = it }
        load.await()
    }

    private fun scan(): List<NotebookMeta> {
        val dirs = root.listFiles() ?: return emptyList()
        val list = ArrayList<NotebookMeta>()
        for (dir in dirs) {
            if (!dir.isDirectory) continue
            val meta = readMeta(dir) ?: continue
            list.add(meta)
        }
        list.sortByDescending { it.modified }
        return list
    }

    private fun readMeta(dir: File): NotebookMeta? {
        val file = File(dir, "meta.json")
        if (!file.isFile) return null
        return try {
            NotebookMeta.fromJson(JSONObject(file.readText()), id = dir.name)
        } catch (e: Exception) {
            null
        }
    }

    /** A new notebook at the top of the library; its folder is written off the main thread. */
    fun create(title: String, paper: PaperStyle = PaperStyle.LINED): NotebookMeta {
        val now = System.currentTimeMillis()
        val meta = NotebookMeta(
            id = UUID.randomUUID().toString(),
            title = title.trim().ifEmpty { "Not" },
            created = now,
            modified = now,
            pageCount = 1,
            paper = paper,
        )
        notebooks = listOf(meta) + notebooks
        scope.launch(Dispatchers.IO) { writeMeta(meta) }
        return meta
    }

    /** Copies the PDF behind `uri` into a new note at the top of the library, with a picture of its
     *  first page. Null when Android cannot read it (damaged, or locked with a password); then
     *  nothing is left behind. */
    suspend fun importPdf(uri: Uri): NotebookMeta? {
        val id = UUID.randomUUID().toString()
        val dir = folder(id)
        val pageCount = withContext(Dispatchers.IO) {
            try {
                dir.mkdirs()
                val copied = app.contentResolver.openInputStream(uri)?.use { input ->
                    pdfFile(id).outputStream().use { input.copyTo(it) }
                }
                if (copied == null) {
                    null
                } else {
                    PdfSource(pdfFile(id)).use { pdf ->
                        if (pdf.pageCount == 0) {
                            null
                        } else {
                            val picture = pdf.renderPage(0, THUMB_WIDTH / pdf.sizes[0].width)
                            thumbFile(id).outputStream().use { picture.compress(Bitmap.CompressFormat.JPEG, 85, it) }
                            picture.recycle()
                            pdf.pageCount
                        }
                    }
                }
            } catch (e: Exception) {
                null
            }
        }
        if (pageCount == null) {
            withContext(Dispatchers.IO) { dir.deleteRecursively() }
            return null
        }
        val now = System.currentTimeMillis()
        val meta = NotebookMeta(
            id = id,
            title = displayName(uri).ifEmpty { "PDF" },
            created = now,
            modified = now,
            pageCount = pageCount,
            paper = PaperStyle.PLAIN,
            kind = NoteKind.PDF,
        )
        notebooks = listOf(meta) + notebooks
        scope.launch(Dispatchers.IO) { writeMeta(meta) }
        return meta
    }

    /** The document's name without ".pdf" (what the iPad calls an imported PDF). */
    private fun displayName(uri: Uri): String {
        val name = try {
            app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (e: Exception) {
            null
        } ?: uri.lastPathSegment ?: ""
        return name.substringAfterLast('/').removeSuffix(".pdf").removeSuffix(".PDF").trim()
    }

    fun rename(id: String, title: String) {
        val t = title.trim()
        if (t.isEmpty()) return
        val updated = update(id) { it.copy(title = t) } ?: return
        scope.launch(Dispatchers.IO) { writeMeta(updated) }
    }

    /** Removes the notebook and its folder; a pending save of it is dropped. */
    fun delete(id: String) {
        saveJobs.remove(id)?.cancel()
        notebooks = notebooks.filter { it.id != id }
        val dir = folder(id)
        scope.launch(Dispatchers.IO) {
            synchronized(writeLock) { dir.deleteRecursively() }
        }
    }

    /** Replaces one record in the list; null when the notebook is not in the library. */
    private fun update(id: String, change: (NotebookMeta) -> NotebookMeta): NotebookMeta? {
        val i = notebooks.indexOfFirst { it.id == id }
        if (i < 0) return null
        val updated = change(notebooks[i])
        val list = notebooks.toMutableList()
        list[i] = updated
        notebooks = list
        return updated
    }

    // MARK: Opening and saving

    private class Loaded(val pages: List<List<Stroke>>, val readOnly: Boolean, val pdfSizes: List<PageSize>? = null)

    /** Loads the notebook's ink off the main thread into an editor state hooked to this store, and
     *  notes the moment for the library's "Son açılanlar". */
    suspend fun open(meta: NotebookMeta): EditorState {
        update(meta.id) { it.copy(opened = System.currentTimeMillis()) }?.let { opened ->
            scope.launch(Dispatchers.IO) { writeMeta(opened) }
        }
        // The screen that had the note open may have just left: its last save lands first.
        writes[meta.id]?.join()
        val file = inkFile(meta.id)
        val isPdf = meta.kind == NoteKind.PDF
        val result = withContext(Dispatchers.IO) {
            // An imported PDF's pages are its own; a PDF Android cannot read now opens read-only.
            val sizes = if (!isPdf) null else try {
                PdfSource(pdfFile(meta.id)).use { it.sizes }.takeIf { it.isNotEmpty() }
            } catch (e: Exception) {
                null
            }
            val pdfUnreadable = isPdf && sizes == null
            if (!file.isFile) {
                Loaded(emptyList(), readOnly = pdfUnreadable, pdfSizes = sizes)
            } else {
                try {
                    Loaded(InkCodec.decode(file.readBytes()), readOnly = pdfUnreadable, pdfSizes = sizes)
                } catch (e: Exception) {
                    // The file stays as it is: the notebook opens read-only, so no save replaces ink
                    // a newer build (or a repair) could still read.
                    Loaded(emptyList(), readOnly = true, pdfSizes = sizes)
                }
            }
        }
        // The record may count more pages than the file holds (blank pages at the end); a PDF has
        // exactly its own pages.
        val pages = ArrayList(result.pages)
        val sizes = result.pdfSizes ?: if (isPdf) List(max(meta.pageCount, pages.size)) { PageSize.A4 } else null
        while (pages.size < (sizes?.size ?: meta.pageCount)) pages.add(emptyList())
        if (sizes != null) while (pages.size > sizes.size) pages.removeAt(pages.size - 1)
        val state = EditorState(
            notebookId = meta.id,
            initialPages = pages,
            prefs = penPreferences,
            readOnly = result.readOnly,
            pageSizes = sizes,
            pdfFile = if (result.pdfSizes != null) pdfFile(meta.id) else null,
            paper = meta.paper,
        )
        state.title = meta.title
        state.onDirty = { scheduleSave(state) }
        state.onSaveNow = { saveNow(state) }
        return state
    }

    /** Saves after a pause in writing; every change restarts the wait. */
    private fun scheduleSave(state: EditorState) {
        val id = state.notebookId ?: return
        saveJobs[id]?.cancel()
        saveJobs[id] = scope.launch {
            delay(SAVE_DELAY_MS)
            save(state)
        }
    }

    /** Writes the notebook now (the screen is leaving, or the app goes to the background). */
    fun saveNow(state: EditorState) {
        val id = state.notebookId ?: return
        saveJobs.remove(id)?.cancel()
        scope.launch { save(state) }
    }

    /** Takes the ink on the main thread and writes it off it; nothing when there is no change. */
    private fun save(state: EditorState) {
        val id = state.notebookId ?: return
        if (!state.dirty || state.readOnly) return
        val pages = state.pages.map { it.strokes }
        state.markSaved()
        val now = System.currentTimeMillis()
        val meta = update(id) { it.copy(modified = now, pageCount = pages.size) } ?: return
        notebooks = notebooks.sortedByDescending { it.modified }
        val sequence = ++nextSequence
        val cover = if (state.isPdf) null else pages.firstOrNull() ?: emptyList()
        // Once the snapshot is taken the write is the store's own job: it goes through, and the
        // library hears of the cover, even when the save is cancelled meanwhile (the note closed).
        writes[id] = scope.launch(Dispatchers.IO) {
            val bytes = InkCodec.encode(pages)
            val coverWritten = synchronized(writeLock) {
                val last = writtenSequence[id] ?: 0L
                if (last < sequence) {
                    writtenSequence[id] = sequence
                    writeAtomically(inkFile(id), bytes)
                    writeMeta(meta)
                    if (cover != null) writeCover(id, cover, meta.paper)
                    cover != null
                } else {
                    false
                }
            }
            if (coverWritten) coverChanged()
        }
    }

    /** The library reads the covers again; called from any thread, it counts on the main one (as
     *  LibraryStore.swift bumps its versions with DispatchQueue.main.async). */
    private fun coverChanged() {
        scope.launch { coverVersion++ }
    }

    /** The library's cover of a notebook: its first page, paper template and ink, 360 pixels across
     *  (an empty first page has no cover; the library draws ruled paper). */
    private fun writeCover(id: String, first: List<Stroke>, paper: PaperStyle) {
        val file = thumbFile(id)
        if (first.isEmpty()) {
            file.delete()
            return
        }
        try {
            val scale = THUMB_WIDTH / PageSize.A4.width
            val picture = Bitmap.createBitmap(THUMB_WIDTH.toInt(), (PageSize.A4.height * scale).toInt(), Bitmap.Config.ARGB_8888)
            picture.eraseColor(android.graphics.Color.WHITE)
            val canvas = Canvas(picture)
            canvas.scale(scale, scale)
            PaperDrawer.draw(paper, PageSize.A4.width, PageSize.A4.height, canvas)
            FlatInk.draw(first, canvas)
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.outputStream().use { picture.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            picture.recycle()
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        } catch (e: Exception) {
            // A cover is a nicety: the note is saved either way.
        }
    }

    /** Writes the newest record of the notebook (the list's, which may be newer than `meta`). */
    private fun writeMeta(meta: NotebookMeta) {
        synchronized(writeLock) {
            val latest = notebooks.firstOrNull { it.id == meta.id } ?: meta
            folder(meta.id).mkdirs()
            writeAtomically(metaFile(meta.id), latest.toJson().toString(2).toByteArray())
        }
    }

    /** A whole file or the old one: written next to it, then moved over it. */
    private fun writeAtomically(file: File, bytes: ByteArray) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeBytes(bytes)
        try {
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: Exception) {
            if (file.exists()) file.delete()
            tmp.renameTo(file)
        }
    }
}

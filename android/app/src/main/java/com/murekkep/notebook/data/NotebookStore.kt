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
import java.util.Collections
import java.util.UUID
import java.util.WeakHashMap
import kotlin.math.max

// Notebooks on disk (Murekkep.swiftpm/LibraryStore.swift and the saving part of EditorModel.swift):
// filesDir/notebooks/<uuid>/meta.json and ink.bin, a picture of the first page for the library's
// cover (thumb.jpg, drawn at every save, and once for a notebook open without changes, as the iPad
// draws it at every close), and for an imported PDF its source.pdf (its cover is the PDF's first
// page). There is no index file: the library is the folders,
// each with its own record, so one damaged record never empties the list. Saves wait for a pause in
// writing (1.2 s, as on iPad), take their snapshot on the main thread and write it on the IO
// dispatcher; the screen asks for a save at once when it leaves or the app goes to the background.
// The courses are the iPad's sections.json next to the folders (data/Sections.kt), each note's
// course in its own record; the library owns both, so a save of an open note keeps its course.

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

    /** Editor states whose ink has had its cover drawn (at a save, or once without changes); held
     *  weakly, so a closed note's ink is not kept. */
    private val coveredStates: MutableSet<EditorState> = Collections.newSetFromMap(WeakHashMap())

    /** Every notebook, newest first. Observable from Compose. */
    var notebooks by mutableStateOf<List<NotebookMeta>>(emptyList())
        private set

    /** The courses, in the order they were made (the iPad's sections). Observable from Compose. */
    var sections by mutableStateOf<List<NoteSection>>(emptyList())
        private set

    /** The entries of sections.json this build could not read, written back with the courses (read and
     *  written under [writeLock]). */
    private var unreadableSections: List<Any> = emptyList()

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

    /** The courses, at the library's root as on iPad (beside the folders, which the scan reads alone). */
    fun sectionsFile(): File = File(root, "sections.json")

    fun notebook(id: String): NotebookMeta? = notebooks.firstOrNull { it.id == id }

    fun section(id: String?): NoteSection? = if (id == null) null else sections.firstOrNull { it.id == id }

    // MARK: Library

    /** Reads every notebook's record off the main thread, once per process, and lists them newest
     *  first. After that the list in memory is the newest there is (this store is the folders' only
     *  writer): a later scan could put an older record over a save, or drop a notebook made while it
     *  read the disk, and then that notebook's saves would find no record and write nothing. */
    suspend fun load() {
        val load = firstLoad ?: scope.async {
            val (scanned, read) = withContext(Dispatchers.IO) { scan() to readSections() }
            // Notebooks made while the disk was read stay, with their records from memory.
            val known = notebooks.mapTo(HashSet()) { it.id }
            notebooks = (notebooks + scanned.filter { it.id !in known }).sortedByDescending { it.modified }
            // So do courses, after the ones on disk.
            val onDisk = read.items.mapTo(HashSet()) { it.id }
            sections = read.items + sections.filter { it.id !in onDisk }
            synchronized(writeLock) { unreadableSections = read.unreadable }
            loaded = true
            drawMissingCovers(scanned)
        }.also { firstLoad = it }
        load.await()
    }

    /** Notebooks saved before the covers came have ink but no thumb.jpg: their covers are drawn once,
     *  off the main thread, after the first read of the folders (newest first, as the library lists
     *  them). A notebook saved meanwhile keeps the cover its save drew. */
    private fun drawMissingCovers(list: List<NotebookMeta>) {
        val candidates = list.filter { it.kind == NoteKind.NOTEBOOK }
        if (candidates.isEmpty()) return
        scope.launch(Dispatchers.IO) {
            for (meta in candidates) {
                val id = meta.id
                if (thumbFile(id).exists() || !inkFile(id).isFile) continue
                val first = try {
                    InkCodec.decode(inkFile(id).readBytes()).firstOrNull()
                } catch (e: Exception) {
                    null
                }
                if (first.isNullOrEmpty()) continue
                val drawn = synchronized(writeLock) {
                    if (id in writtenSequence || thumbFile(id).exists()) {
                        false
                    } else {
                        writeCover(id, first, meta.paper)
                        true
                    }
                }
                if (drawn) coverChanged()
            }
        }
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

    /** sections.json as it is on disk; none when there is no file. A file that is not a list at all
     *  is copied aside first, as its next save replaces it (load in LibraryStore.swift). */
    private fun readSections(): SectionList {
        val file = sectionsFile()
        if (!file.isFile) return SectionList.EMPTY
        val read = try {
            SectionList.decode(file.readText())
        } catch (e: Exception) {
            null
        }
        if (read == null) FileBackup.keep(file)
        return read ?: SectionList.EMPTY
    }

    /** A new notebook at the top of the library, in [section] (a course's id) or in none; its folder
     *  is written off the main thread. */
    fun create(title: String, paper: PaperStyle = PaperStyle.LINED, section: String? = null): NotebookMeta {
        val now = System.currentTimeMillis()
        val meta = NotebookMeta(
            id = UUID.randomUUID().toString(),
            title = title.trim().ifEmpty { "Not" },
            created = now,
            modified = now,
            pageCount = 1,
            paper = paper,
            sectionId = section,
        )
        notebooks = listOf(meta) + notebooks
        scope.launch(Dispatchers.IO) { writeMeta(meta) }
        return meta
    }

    /** Copies the PDF behind `uri` into a new note at the top of the library, in [section] (a
     *  course's id) or in none, with a picture of its first page. Null when Android cannot read it
     *  (damaged, or locked with a password); then nothing is left behind. */
    suspend fun importPdf(uri: Uri, section: String? = null): NotebookMeta? {
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
            sectionId = section,
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

    /** Stars a note in the library, or takes its star away (the iPad's toggleFavorite). The library
     *  owns the star: a save of the open note keeps it, as it keeps the title. */
    fun toggleStarred(id: String) {
        val updated = update(id) { it.copy(starred = !it.starred) } ?: return
        scope.launch(Dispatchers.IO) { writeMeta(updated) }
    }

    /** Puts a notebook on another page template (Diğer › Şablonu değiştir): its record at once; the
     *  editor marks the ink changed, so the next save draws the cover on the new paper. */
    fun setPaper(id: String, paper: PaperStyle) {
        val updated = update(id) { it.copy(paper = paper) } ?: return
        scope.launch(Dispatchers.IO) { writeMeta(updated) }
    }

    // MARK: Courses

    /** A new course at the end of the list (createSection on iPad). */
    fun createSection(name: String, symbol: String, colorIndex: Int): NoteSection {
        val section = NoteSection.make(name.trim(), symbol, colorIndex)
        sections = sections + section
        persistSections()
        return section
    }

    /** A course's new name, symbol or colour; nothing when the course is gone. */
    fun updateSection(section: NoteSection) {
        val i = sections.indexOfFirst { it.id == section.id }
        if (i < 0) return
        sections = sections.toMutableList().also { it[i] = section }
        persistSections()
    }

    /** Removes the course; its notes stay in the library, in no course (deleteSection on iPad). */
    fun deleteSection(id: String) {
        sections = sections.filter { it.id != id }
        val freed = notebooks.filter { it.sectionId == id }
        if (freed.isNotEmpty()) {
            notebooks = notebooks.map { if (it.sectionId == id) it.copy(sectionId = null) else it }
            scope.launch(Dispatchers.IO) { for (meta in freed) writeMeta(meta) }
        }
        persistSections()
    }

    /** Files a note under a course, or under none (move on iPad). */
    fun move(noteId: String, sectionId: String?) {
        val updated = update(noteId) { it.copy(sectionId = sectionId) } ?: return
        scope.launch(Dispatchers.IO) { writeMeta(updated) }
    }

    /** Writes sections.json with the newest courses and the entries kept from the file. Only after
     *  the first read of the disk, so a course made before it never writes over the ones there. */
    private fun persistSections() {
        scope.launch {
            load()
            withContext(Dispatchers.IO) {
                synchronized(writeLock) {
                    writeAtomically(sectionsFile(), SectionList(sections, unreadableSections).encode().toByteArray())
                }
            }
        }
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

    private class Loaded(val pages: List<List<Stroke>>, val problems: List<LoadProblem>, val pdfSizes: List<PageSize>?)

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
            val problems = ArrayList<LoadProblem>()
            // An imported PDF's pages are its own; a PDF Android cannot read now opens read-only
            // (the iPad goes on with one A4 page, whose next save would drop the later pages' ink).
            val sizes = if (!isPdf) null else try {
                PdfSource(pdfFile(meta.id)).use { it.sizes }.takeIf { it.isNotEmpty() }
            } catch (e: Exception) {
                null
            }
            if (isPdf && sizes == null) problems.add(LoadProblem.PDF_UNREADABLE)
            var pages: List<List<Stroke>> = emptyList()
            if (file.isFile) {
                val bytes = try {
                    file.readBytes()
                } catch (e: Exception) {
                    null
                }
                try {
                    pages = InkCodec.decode(bytes ?: throw InkCodec.CodecException("unreadable"))
                } catch (e: Exception) {
                    // The file stays as it is: the note opens read-only, so no save replaces ink a
                    // newer build (or a repair) could still read. A damaged file also gets a copy
                    // next to it, as on the iPad.
                    if (bytes != null && InkCodec.isNewerFormat(bytes)) {
                        problems.add(LoadProblem.INK_NEWER)
                    } else {
                        FileBackup.keep(file)
                        problems.add(LoadProblem.INK_DAMAGED)
                    }
                }
            }
            Loaded(pages, problems, sizes)
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
            loadProblems = result.problems,
            pageSizes = sizes,
            pdfFile = if (result.pdfSizes != null) pdfFile(meta.id) else null,
            paper = meta.paper,
        )
        state.title = meta.title
        state.onPaperChange = { setPaper(meta.id, it) }
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

    /** Writes the notebook now (the screen is leaving, or the app goes to the background); a notebook
     *  without changes has its cover drawn instead, once while it is open. */
    fun saveNow(state: EditorState) {
        val id = state.notebookId ?: return
        saveJobs.remove(id)?.cancel()
        scope.launch {
            if (state.dirty) save(state) else drawCover(state)
        }
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
        if (cover != null) coveredStates.add(state)
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

    /** An unchanged notebook's cover from the ink it has open (the iPad draws it at every close): a
     *  note from before the covers, or one whose cover was lost, has it again. Once per opening, and
     *  never over a newer save's cover. */
    private fun drawCover(state: EditorState) {
        val id = state.notebookId ?: return
        if (state.readOnly || state.isPdf || !coveredStates.add(state)) return
        val first = state.pages.firstOrNull()?.strokes ?: emptyList()
        val paper = state.paper
        val sequence = ++nextSequence
        scope.launch(Dispatchers.IO) {
            val drawn = synchronized(writeLock) {
                if ((writtenSequence[id] ?: 0L) > sequence) {
                    false
                } else {
                    writeCover(id, first, paper)
                    true
                }
            }
            if (drawn) coverChanged()
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

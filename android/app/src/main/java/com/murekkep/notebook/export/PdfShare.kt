package com.murekkep.notebook.export

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.content.FileProvider
import com.murekkep.notebook.R
import com.murekkep.notebook.data.PdfSource
import com.murekkep.notebook.render.PageSize
import com.murekkep.notebook.ui.EditorState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

// The editor's Paylaş (the share sheet of EditorView.swift on iPad): the note written as a PDF by
// PdfExport into the app's cache, handed to the system's share chooser through a FileProvider
// (the manifest's provider, res/xml/file_paths.xml). An imported PDF's pages are drawn from the
// PDF itself at twice their size under the ink.

object PdfShare {
    /** The FileProvider's authority is the application id and this. */
    const val AUTHORITY_SUFFIX = ".files"

    /** Where the shared files wait in the cache (`file_paths.xml` names it). */
    private const val FOLDER = "shared"

    /** Pixels per point for an imported page's picture in the file. */
    private const val PDF_PAGE_SCALE = 2f

    /** The longest name before ".pdf", in UTF-8 bytes: a file name takes at most 255, and a Turkish
     *  letter (ğ, ş, ı, ç, ö, ü) is two of them. */
    const val NAME_BYTES = 240

    /** The file's name from the note's title: the characters no file system takes become "_", and
     *  a title longer than a file name takes is cut. */
    fun fileName(title: String): String {
        val clean = title.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").trim().trim('.').ifEmpty { "Not" }
        val hasPdf = clean.endsWith(".pdf", ignoreCase = true)
        val name = if (hasPdf) clean.dropLast(4) else clean
        val cut = cutToBytes(name, NAME_BYTES).let { if (it.length < name.length) it.trimEnd() else it }
        return cut + if (hasPdf) clean.takeLast(4) else ".pdf"
    }

    /** `text` cut to at most `max` bytes of UTF-8, never inside a character. */
    private fun cutToBytes(text: String, max: Int): String {
        var bytes = 0
        var i = 0
        while (i < text.length) {
            val c = text.codePointAt(i)
            bytes += when {
                c < 0x80 -> 1
                c < 0x800 -> 2
                c < 0x10000 -> 3
                else -> 4
            }
            if (bytes > max) return text.substring(0, i)
            i += Character.charCount(c)
        }
        return text
    }

    /** Writes the note into the cache off the main thread and returns the file; older shared files go. */
    suspend fun write(context: Context, state: EditorState): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, FOLDER)
        dir.mkdirs()
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, fileName(state.title))
        val pages = state.pages.map { it.strokes }
        val sizes = (state.pageSizes ?: List(pages.size) { PageSize.A4 }).map { it.width to it.height }
        val source = state.pdfFile?.let { f ->
            try {
                PdfSource(f)
            } catch (e: Exception) {
                null
            }
        }
        try {
            file.outputStream().buffered().use { out ->
                PdfExport.write(
                    out, pages, sizes, state.paper, state.isPdf,
                    background = source?.let { src -> { page, canvas -> drawImportedPage(src, page, canvas) } },
                )
            }
        } finally {
            source?.close()
        }
        file
    }

    /** The imported page's picture, scaled onto the page's points. */
    private fun drawImportedPage(source: PdfSource, page: Int, canvas: Canvas) {
        if (page >= source.pageCount) return
        val size = source.sizes[page]
        val picture = source.renderPage(page, PDF_PAGE_SCALE)
        canvas.drawBitmap(picture, null, RectF(0f, 0f, size.width, size.height), Paint(Paint.FILTER_BITMAP_FLAG))
        picture.recycle()
    }

    /** Opens the system's chooser with the file; the receiving app may read it. */
    fun share(context: Context, file: File, title: String) {
        val uri = FileProvider.getUriForFile(context, context.packageName + AUTHORITY_SUFFIX, file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title)
            putExtra(Intent.EXTRA_TITLE, title)
            clipData = ClipData.newUri(context.contentResolver, title, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, context.getString(R.string.share_pdf))
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
    }
}

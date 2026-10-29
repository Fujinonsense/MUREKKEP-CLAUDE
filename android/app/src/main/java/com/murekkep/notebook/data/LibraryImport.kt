package com.murekkep.notebook.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.murekkep.notebook.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.DateFormat
import java.util.Date
import java.util.UUID
import kotlin.math.max

// The library's imports (importFiles, importPicked and handleDrop in LibraryView.swift): PDFs come
// in as they are, and photos picked or dropped together become one PDF, a page per photo, while a
// banner counts them. The work runs in the process's own scope, not the library screen's, so
// opening a note or Ayarlar meanwhile never cuts an import off halfway (which left its copy on disk
// with no record). An import goes into a course, or into none: the library showing at the end opens
// the one note an import from its buttons brought into none (one brought into a course stays in the
// course, as on iPad), and lists the files that could not be read.

class LibraryImport private constructor(context: Context) {
    private val app: Context = context.applicationContext
    private val store = NotebookStore.get(app)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Photos on their way into one PDF: how many are done and how many there are. */
    data class PhotoProgress(val done: Int, val total: Int)

    private class Imported(val added: List<NotebookMeta>, val failed: List<String>)

    /** Imports under way; the library's button reads "Aktarılıyor…" meanwhile. */
    var running by mutableStateOf(0)
        private set

    var photoProgress by mutableStateOf<PhotoProgress?>(null)
        private set

    /** The names of the files that could not be read, until the library has shown them. */
    var failed by mutableStateOf<List<String>>(emptyList())
        private set

    /** The library on screen: it opens the one note an import from its buttons brought in. */
    var onOpen: ((NotebookMeta) -> Unit)? = null

    companion object {
        @Volatile
        private var shared: LibraryImport? = null

        /** One for the process, like the store, so an import outlives the screen that began it. */
        fun get(context: Context): LibraryImport =
            shared ?: synchronized(this) { shared ?: LibraryImport(context).also { shared = it } }
    }

    /** Files from the system's picker into [section] (a course's id) or into none: each PDF as it
     *  is, the photos among them as one PDF named after the first. */
    fun importFiles(uris: List<Uri>, section: String? = null) = start(uris, open = section == null) { importAll(uris, section) }

    /** Photos from the gallery into [section] or into none, as one PDF named "Fotoğraf" and the moment. */
    fun importPhotos(uris: List<Uri>, section: String? = null) = start(uris, open = section == null) {
        val meta = convertPhotos(uris, defaultPhotoTitle(), section)
        if (meta != null) Imported(listOf(meta), emptyList()) else Imported(emptyList(), names(uris))
    }

    /** Files dragged in from another app into [section] or into none; [release] gives back the right
     *  to read them once they are copied. */
    fun importDropped(uris: List<Uri>, release: () -> Unit, section: String? = null) =
        start(uris, open = false, release = release) { importAll(uris, section) }

    fun clearFailed() {
        failed = emptyList()
    }

    /** Runs an import; at its end the files that failed are listed, or the one note that came in
     *  is opened (finishImport on iPad). */
    private fun start(uris: List<Uri>, open: Boolean, release: (() -> Unit)? = null, work: suspend () -> Imported) {
        running++
        scope.launch {
            try {
                val result = try {
                    work()
                } catch (e: Exception) {
                    Imported(emptyList(), names(uris))
                }
                if (result.failed.isNotEmpty()) {
                    failed = failed + result.failed
                } else if (open && result.added.size == 1) {
                    onOpen?.invoke(result.added[0])
                }
            } finally {
                running--
                release?.invoke()
            }
        }
    }

    private suspend fun importAll(uris: List<Uri>, section: String?): Imported {
        val photos = withContext(Dispatchers.IO) { uris.filter { isPhoto(it) } }
        val added = ArrayList<NotebookMeta>()
        val failedNames = ArrayList<String>()
        for (uri in uris) {
            if (uri in photos) continue
            val meta = store.importPdf(uri, section)
            if (meta != null) added.add(meta) else failedNames.addAll(names(listOf(uri)))
        }
        if (photos.isNotEmpty()) {
            val first = names(photos.take(1)).first().substringBeforeLast('.').trim()
            val meta = convertPhotos(photos, first.ifEmpty { defaultPhotoTitle() }, section)
            if (meta != null) added.add(meta) else failedNames.addAll(names(photos))
        }
        return Imported(added, failedNames)
    }

    /** Photos as one PDF in the library (in [section], or in no course), titled [title]; null when
     *  none of them could be read. */
    private suspend fun convertPhotos(photos: List<Uri>, title: String, section: String?): NotebookMeta? {
        photoProgress = PhotoProgress(0, photos.size)
        val dir = File(app.cacheDir, "photo-import/" + UUID.randomUUID())
        try {
            // The store takes the title from the file's name, as the iPad does.
            val file = File(dir, PhotoPdf.fileName(title) + ".pdf")
            val pages = withContext(Dispatchers.IO) {
                dir.mkdirs()
                file.outputStream().buffered().use { out ->
                    PhotoPdf.write(out, photos.size, page = { readPhoto(photos[it]) }) { done, total ->
                        scope.launch { if (photoProgress != null) photoProgress = PhotoProgress(done, total) }
                    }
                }
            }
            return if (pages > 0) store.importPdf(Uri.fromFile(file), section) else null
        } catch (e: Exception) {
            return null
        } finally {
            photoProgress = null
            withContext(NonCancellable + Dispatchers.IO) { dir.deleteRecursively() }
        }
    }

    /** "Fotoğraf" and the moment (LibraryStore.photoTitle on iPad). */
    private fun defaultPhotoTitle(): String {
        val stamp = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date())
        return app.getString(R.string.photo_title) + " " + stamp
    }

    private fun isPhoto(uri: Uri): Boolean {
        val type = try {
            app.contentResolver.getType(uri)
        } catch (e: Exception) {
            null
        } ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(MimeTypeMap.getFileExtensionFromUrl(uri.toString()).lowercase())
        return type?.startsWith("image/") == true
    }

    /** The files' names, for the alert that lists the ones that could not be read. */
    private suspend fun names(uris: List<Uri>): List<String> = withContext(Dispatchers.IO) {
        uris.map { uri ->
            val name = try {
                app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) c.getString(0) else null
                }
            } catch (e: Exception) {
                null
            }
            name ?: uri.lastPathSegment?.substringAfterLast('/') ?: ""
        }
    }

    /** A photo upright, scaled down to [PhotoPdf.MAX_PIXELS] on its long side, on white, as JPEG
     *  at 85 (PhotoPDF.scaled on iPad); null when it cannot be read. Off the main thread. */
    private fun readPhoto(uri: Uri): PhotoPdf.Page? {
        return try {
            val photo = decodeUpright(uri) ?: return null
            val (w, h) = PhotoPdf.scaledPixels(photo.width, photo.height)
            val page = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            page.eraseColor(Color.WHITE)
            Canvas(page).drawBitmap(photo, null, Rect(0, 0, w, h), Paint(Paint.FILTER_BITMAP_FLAG))
            photo.recycle()
            val jpeg = ByteArrayOutputStream().use { out ->
                page.compress(Bitmap.CompressFormat.JPEG, 85, out)
                out.toByteArray()
            }
            page.recycle()
            PhotoPdf.Page(jpeg, w, h)
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }
    }

    private fun decodeUpright(uri: Uri): Bitmap? {
        val resolver = app.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // ImageDecoder turns the photo upright itself and decodes it at the size it will have.
            return ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
                val (w, h) = PhotoPdf.scaledPixels(info.size.width, info.size.height)
                decoder.setTargetSize(w, h)
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        // Android 8: sampled down while decoding, then turned by its EXIF orientation.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
        val long = max(bounds.outWidth, bounds.outHeight)
        if (long <= 0) return null
        var sample = 1
        while (long / (sample * 2) >= PhotoPdf.MAX_PIXELS) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return null
        val orientation = try {
            resolver.openInputStream(uri)?.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
        } catch (e: Exception) {
            null
        } ?: ExifInterface.ORIENTATION_NORMAL
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> matrix.apply { postRotate(90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> matrix.apply { postRotate(270f); postScale(-1f, 1f) }
            else -> return bitmap
        }
        val upright = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (upright !== bitmap) bitmap.recycle()
        return upright
    }
}

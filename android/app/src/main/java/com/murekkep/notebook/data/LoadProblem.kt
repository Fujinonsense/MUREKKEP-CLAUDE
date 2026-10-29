package com.murekkep.notebook.data

import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

// Why a note opened read-only (the iPad's loadError in EditorModel.swift), each with its own
// notice, and the copy of a damaged file kept next to it (FileBackup in SafeFiles.swift).

/** What could not be read when the note opened. */
enum class LoadProblem {
    /** The imported PDF cannot be read any more (damaged, or locked with a password). */
    PDF_UNREADABLE,

    /** A newer Mürekkep wrote the ink file: the ink in it is fine, this build cannot read it. */
    INK_NEWER,

    /** The ink file is damaged; a copy of it was kept next to it. */
    INK_DAMAGED,
}

/**
 * A copy of a file next to itself, made before the app goes on without it: "ink.bin" becomes
 * "ink.bak-20261026-141503", dated when the file was last written, so a newer build or a repair can
 * still get at the bytes. The same file keeps the same name, so the copy is made once.
 */
object FileBackup {
    const val MARKER = ".bak-"

    /** Where the copy of [file] goes, for a file last written at [modified] (ms) in [zone]. */
    fun backupFile(file: File, modified: Long, zone: TimeZone = TimeZone.getDefault()): File {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).apply { timeZone = zone }.format(Date(modified))
        return File(file.parentFile, file.nameWithoutExtension + MARKER + stamp)
    }

    /** Copies [file] aside (unless the copy is there already) and returns the copy; null when there
     *  is nothing to copy or the copy could not be made. */
    fun keep(file: File): File? {
        if (!file.isFile) return null
        val modified = file.lastModified().takeIf { it > 0L } ?: System.currentTimeMillis()
        val copy = backupFile(file, modified)
        if (copy.exists()) return copy
        // Whole or not at all: a copy cut short would pass for the kept one at the next opening.
        val tmp = File(copy.parentFile, copy.name + ".tmp")
        return try {
            file.copyTo(tmp, overwrite = true)
            if (tmp.renameTo(copy)) copy else null
        } catch (e: Exception) {
            null
        } finally {
            tmp.delete()
        }
    }
}

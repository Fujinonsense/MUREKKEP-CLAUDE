package com.murekkep.notebook.data

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

// Why a note opens read-only, as the iPad tells it: an ink file a newer Mürekkep wrote is not
// damaged (it gets its own notice and is left alone), a damaged one gets a copy next to it,
// "ink.bak-yyyyMMdd-HHmmss" after the time it was last written, made once (FileBackup on iPad).
class LoadProblemTest {
    private val utc = TimeZone.getTimeZone("UTC")

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int): Long =
        Calendar.getInstance(utc).apply {
            clear()
            set(year, month - 1, day, hour, minute, second)
        }.timeInMillis

    @Test
    fun theCopyIsNamedAfterTheFileAndItsTime() {
        val copy = FileBackup.backupFile(File("notes/abc/ink.bin"), millis(2026, 10, 26, 14, 15, 3), utc)
        assertEquals("ink.bak-20261026-141503", copy.name)
        assertEquals(File("notes/abc"), copy.parentFile)
    }

    @Test
    fun aDamagedFileIsCopiedOnceAndLeftAsItIs() {
        val dir = Files.createTempDirectory("backup").toFile()
        try {
            val ink = File(dir, "ink.bin")
            val bytes = byteArrayOf(1, 2, 3, 4, 5)
            ink.writeBytes(bytes)
            val first = FileBackup.keep(ink) ?: return fail("no copy")
            assertTrue(first.name.startsWith("ink" + FileBackup.MARKER))
            assertArrayEquals(bytes, first.readBytes())
            assertArrayEquals(bytes, ink.readBytes())
            // The same file keeps the same copy: opening it again makes no second one.
            assertEquals(first, FileBackup.keep(ink))
            assertEquals(listOf("ink.bin", first.name).sorted(), dir.list()!!.sorted())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun aMissingFileHasNothingToKeep() {
        assertNull(FileBackup.keep(File("no-such-folder/ink.bin")))
    }

    private fun header(magic: Int, version: Int): ByteArray =
        ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN).putInt(magic).putInt(version).putInt(0).array()

    @Test
    fun aNewerInkFileIsToldApartFromADamagedOne() {
        val mrk1 = 0x314B524D
        val newer = header(mrk1, InkCodec.VERSION + 1)
        assertTrue(InkCodec.isNewerFormat(newer))
        try {
            InkCodec.decode(newer)
            fail("a newer file is not read")
        } catch (e: InkCodec.CodecException) {
            // read-only, with its own notice
        }
        assertFalse(InkCodec.isNewerFormat(header(0x12345678, 2)))
        assertFalse(InkCodec.isNewerFormat(byteArrayOf(1, 2, 3)))
        assertEquals(0, InkCodec.decode(header(mrk1, InkCodec.VERSION)).size)
    }
}

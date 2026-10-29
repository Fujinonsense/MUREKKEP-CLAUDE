package com.murekkep.notebook.data

import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkPoint
import com.murekkep.notebook.ink.Stroke
import java.nio.ByteBuffer
import java.nio.ByteOrder

// The ink file (Murekkep.swiftpm/InkCodec.swift), byte for byte: a notebook's `ink.bin` here is the
// iPad's `ink.mrk`, so a notebook can move between the editions. Little-endian throughout: magic
// "MRK1", version, page count; a page is a stroke count and its strokes; a stroke is the brush's raw
// value (one byte and three of padding), color rgba, width, birth (f64), seed, point count and the
// points (x, y, r, ink as f32).

object InkCodec {
    class CodecException(message: String) : Exception(message)

    private const val MAGIC = 0x314B524D // "MRK1"
    const val VERSION = 1
    private const val MAX_PAGES = 100_000
    private const val MAX_STROKES = 2_000_000
    private const val MAX_POINTS = 5_000_000
    private const val STROKE_HEADER_BYTES = 4 + 16 + 4 + 8 + 4 + 4
    private const val POINT_BYTES = 16
    private const val ZERO: Byte = 0

    fun encode(pages: List<List<Stroke>>): ByteArray {
        var size = 12
        for (strokes in pages) {
            size += 4
            for (s in strokes) size += STROKE_HEADER_BYTES + s.points.size * POINT_BYTES
        }
        val b = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN)
        b.putInt(MAGIC)
        b.putInt(VERSION)
        b.putInt(pages.size)
        for (strokes in pages) {
            b.putInt(strokes.size)
            for (s in strokes) {
                b.put(s.brush.raw.toByte())
                b.put(ZERO)
                b.put(ZERO)
                b.put(ZERO)
                b.putFloat(s.color.r)
                b.putFloat(s.color.g)
                b.putFloat(s.color.b)
                b.putFloat(s.color.a)
                b.putFloat(s.width)
                b.putDouble(s.birth)
                b.putFloat(s.seed)
                b.putInt(s.points.size)
                for (p in s.points) {
                    b.putFloat(p.x)
                    b.putFloat(p.y)
                    b.putFloat(p.r)
                    b.putFloat(p.ink)
                }
            }
        }
        return b.array()
    }

    /** Throws CodecException for a file this build cannot read (damaged, or a newer version). */
    fun decode(bytes: ByteArray): List<List<Stroke>> {
        val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        if (b.remaining() < 12) throw CodecException("truncated")
        if (b.getInt() != MAGIC) throw CodecException("not an ink file")
        val version = b.getInt()
        if (version != VERSION) throw CodecException("unsupported version $version")
        val pageCount = b.getInt()
        if (pageCount < 0 || pageCount > MAX_PAGES) throw CodecException("too large")
        val pages = ArrayList<List<Stroke>>(pageCount)
        repeat(pageCount) {
            if (b.remaining() < 4) throw CodecException("truncated")
            val strokeCount = b.getInt()
            if (strokeCount < 0 || strokeCount > MAX_STROKES) throw CodecException("too large")
            val strokes = ArrayList<Stroke>(minOf(strokeCount, 4096))
            repeat(strokeCount) {
                if (b.remaining() < STROKE_HEADER_BYTES) throw CodecException("truncated")
                val brush = Brush.fromRaw(b.get().toInt() and 0xFF)
                b.get()
                b.get()
                b.get()
                val color = InkColor(b.getFloat(), b.getFloat(), b.getFloat(), b.getFloat())
                val width = b.getFloat()
                val birth = b.getDouble()
                val seed = b.getFloat()
                val n = b.getInt()
                if (n < 0 || n > MAX_POINTS || b.remaining() < n * POINT_BYTES) throw CodecException("truncated")
                val pts = ArrayList<InkPoint>(n)
                repeat(n) {
                    val p = InkPoint(b.getFloat(), b.getFloat(), b.getFloat(), b.getFloat())
                    if (p.x.isFinite() && p.y.isFinite() && p.r.isFinite() && p.r > 0f) pts.add(p)
                }
                if (pts.isNotEmpty()) strokes.add(Stroke(brush, color, width, birth, seed, pts))
            }
            pages.add(strokes)
        }
        return pages
    }

    /** The format version the bytes were written with; null when they are not an ink file at all. */
    fun formatVersion(bytes: ByteArray): Int? {
        if (bytes.size < 8) return null
        val b = ByteBuffer.wrap(bytes, 0, 8).order(ByteOrder.LITTLE_ENDIAN)
        if (b.getInt() != MAGIC) return null
        return b.getInt()
    }

    /** True for a file a newer Mürekkep wrote: the ink in it is fine, this build just cannot read it
     *  (and must not write over it). */
    fun isNewerFormat(bytes: ByteArray): Boolean = (formatVersion(bytes) ?: 0) > VERSION
}

package com.murekkep.notebook.data

import java.io.OutputStream
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// Photos become a PDF, one page per photo in the order given (PhotoPDF.swift on iPad), so a
// photographed handout or a whiteboard photo opens like any PDF: write on it, share it. Each page
// takes its photo's own shape, as long as A4, and holds the photo as a JPEG. The file is written
// here byte by byte, a plain PDF of image pages: the photos stay compressed (Android's PdfDocument
// would store them raw, many megabytes a page), and the layout is tested on the JVM.

object PhotoPdf {
    /** A page's long side in points (A4's), whatever the photo's resolution. */
    const val PAGE_LONG = 842f

    /** A photo's long side in pixels after scaling down: sharp enough to zoom into, small enough
     *  that twenty phone photos stay a few megabytes. */
    const val MAX_PIXELS = 2400

    /** One page: its photo as JPEG data and the photo's size in pixels. */
    class Page(val jpeg: ByteArray, val width: Int, val height: Int)

    /** The page for a photo of this (upright) size, in points: the photo's own shape, as long as
     *  A4 (in double, as CGFloat is, so the rounding is the iPad's). */
    fun pageSize(width: Int, height: Int): Pair<Int, Int> {
        if (width <= 0 || height <= 0) return 595 to 842
        val k = PAGE_LONG.toDouble() / max(width, height)
        return (width * k).roundToInt() to (height * k).roundToInt()
    }

    /** The pixel size a photo is scaled down to (never up). */
    fun scaledPixels(width: Int, height: Int): Pair<Int, Int> {
        val k = min(1.0, MAX_PIXELS.toDouble() / max(max(width, height), 1))
        return max(1, (width * k).roundToInt()) to max(1, (height * k).roundToInt())
    }

    /** A file name from a title: none of the characters a file name cannot hold. */
    fun fileName(title: String): String {
        val cleaned = title.map { if (it in "/\\:?%*|\"<>") '-' else it }.joinToString("").trim()
        return cleaned.ifEmpty { "Photos" }
    }

    /**
     * Writes up to [count] pages as a PDF, asking [page] for each in turn (null skips a photo that
     * cannot be read), and tells [progress] how many photos are done after each. Returns how many
     * pages were written; with none the output is not a PDF and belongs in the bin.
     */
    fun write(out: OutputStream, count: Int, page: (Int) -> Page?, progress: (Int, Int) -> Unit = { _, _ -> }): Int {
        val pdf = CountingStream(out)
        // Object 1 is the catalog and 2 the page tree, written last, once the pages are known;
        // each page takes three more: the page, its drawing and its photo.
        val offsets = HashMap<Int, Long>()
        pdf.write("%PDF-1.4\n".toByteArray(Charsets.US_ASCII))
        pdf.write(byteArrayOf(0x25, 0xE2.toByte(), 0xE3.toByte(), 0xCF.toByte(), 0xD3.toByte(), 0x0A))
        offsets[1] = pdf.count
        pdf.ascii("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        val kids = ArrayList<Int>()
        for (i in 0 until count) {
            val photo = page(i)
            if (photo != null && photo.width > 0 && photo.height > 0) {
                val n = 3 + 3 * kids.size
                val (w, h) = pageSize(photo.width, photo.height)
                offsets[n] = pdf.count
                pdf.ascii(
                    "$n 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $w $h] " +
                        "/Resources << /XObject << /Im0 ${n + 2} 0 R >> /ProcSet [/PDF /ImageC] >> /Contents ${n + 1} 0 R >>\nendobj\n",
                )
                val drawing = "q\n$w 0 0 $h 0 0 cm\n/Im0 Do\nQ\n".toByteArray(Charsets.US_ASCII)
                offsets[n + 1] = pdf.count
                pdf.ascii("${n + 1} 0 obj\n<< /Length ${drawing.size} >>\nstream\n")
                pdf.write(drawing)
                pdf.ascii("\nendstream\nendobj\n")
                offsets[n + 2] = pdf.count
                pdf.ascii(
                    "${n + 2} 0 obj\n<< /Type /XObject /Subtype /Image /Width ${photo.width} /Height ${photo.height} " +
                        "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${photo.jpeg.size} >>\nstream\n",
                )
                pdf.write(photo.jpeg)
                pdf.ascii("\nendstream\nendobj\n")
                kids.add(n)
            }
            progress(i + 1, count)
        }
        if (kids.isEmpty()) {
            pdf.flush()
            return 0
        }
        offsets[2] = pdf.count
        pdf.ascii("2 0 obj\n<< /Type /Pages /Kids [${kids.joinToString(" ") { "$it 0 R" }}] /Count ${kids.size} >>\nendobj\n")
        // The cross-reference table: every entry exactly 20 bytes.
        val size = 3 + 3 * kids.size
        val xref = pdf.count
        val table = StringBuilder("xref\n0 $size\n0000000000 65535 f \n")
        for (n in 1 until size) table.append(String.format(Locale.ROOT, "%010d 00000 n \n", offsets.getValue(n)))
        table.append("trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n")
        pdf.ascii(table.toString())
        pdf.flush()
        return kids.size
    }

    /** Counts what goes through it, for the cross-reference table's offsets. */
    private class CountingStream(private val out: OutputStream) : OutputStream() {
        var count = 0L
            private set

        override fun write(b: Int) {
            out.write(b)
            count++
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            out.write(b, off, len)
            count += len
        }

        override fun flush() = out.flush()

        fun ascii(s: String) = write(s.toByteArray(Charsets.US_ASCII))
    }
}

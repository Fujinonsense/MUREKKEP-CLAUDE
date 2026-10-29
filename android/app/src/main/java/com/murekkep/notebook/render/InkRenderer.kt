package com.murekkep.notebook.render

import android.opengl.GLES30
import android.util.Log
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.GrassField
import com.murekkep.notebook.ink.GrassGenerator
import com.murekkep.notebook.ink.PageInk
import com.murekkep.notebook.ink.RibbonBuilder
import com.murekkep.notebook.ink.RibbonOut
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.referenceNow
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// The iPad's Metal renderer (Murekkep.swiftpm/InkRenderer.swift) on OpenGL ES 3.0: every stroke is
// one ribbon mesh; a per-stroke depth makes the parts of a stroke that fold over themselves merge
// while later strokes land on top; highlighters go first with multiply blending, then the soft
// shadows of raised ink (only the raised inks' triangles), then the ink. Runs on the GL thread.

/** One linked program and its uniform locations. */
private class GlProgram(val id: Int, val blend: Blend) {
    private val locations = HashMap<String, Int>()

    fun loc(name: String): Int = locations.getOrPut(name) { GLES30.glGetUniformLocation(id, name) }
}

/** A contiguous index range of committed ink; see-through brushes get a run of their own. */
private class InkRun(val first: Int, var count: Int, val blendsOnce: Boolean)

/** A stroke's ribbon, indices from 0 (kept per stroke id so a change rebuilds only new strokes). */
private class StrokeMesh(val vertices: FloatArray, val vertexCount: Int, val indices: IntArray)

/** GPU geometry of one page's committed strokes. */
private class PageGpu {
    var version = -1
    var vbo = 0
    var ibo = 0
    var shadowIbo = 0
    var records = 0
    var highlighterIndexCount = 0
    var inkIndexCount = 0
    var shadowIndexCount = 0
    var highlighterStrokes = 0
    var inkStrokes = 0
    var runs: List<InkRun> = emptyList()
    var has3D = false
    var hasAnimated = false
    var hasWave = false
    var latestWetBirth = Double.NEGATIVE_INFINITY
    var latestLavaBirth = Double.NEGATIVE_INFINITY
    var meshes = HashMap<Int, StrokeMesh>()
    // The grass and flowering-water pens' blades and flowers (GrassGenerator), drawn instanced.
    var bladeTex = 0
    var flowerTex = 0
    var bladeCount = 0
    var flowerCount = 0
    var latestGrassBirth = Double.NEGATIVE_INFINITY
    var grass = HashMap<Int, GrassField>()
}

/** A growable float list (records for the blade and flower tables). */
private class FloatBuilder {
    var data = FloatArray(256)
    var size = 0

    fun add(a: Float, b: Float, c: Float, d: Float) {
        if (size + 4 > data.size) data = data.copyOf(data.size * 2)
        data[size] = a; data[size + 1] = b; data[size + 2] = c; data[size + 3] = d
        size += 4
    }
}

class InkRenderer {
    private val epoch = referenceNow()
    private var programs = HashMap<String, GlProgram>()
    private val pageCache = HashMap<Int, PageGpu>()
    private var width = 0
    private var height = 0
    private var activeVbo = 0
    private var activeIbo = 0
    private var activeRecords = 0
    private val scratch = RibbonOut()

    /** GL thread, on a new surface: compiles the programs (InkShaders) and makes the live stroke's buffers. */
    fun onSurfaceCreated() {
        pageCache.clear()
        programs = HashMap()
        for (p in InkShaders.programs) {
            val id = link(p.name, p.vertex, p.fragment)
            if (id != 0) programs[p.name] = GlProgram(id, p.blend)
        }
        val ids = IntArray(2)
        GLES30.glGenBuffers(2, ids, 0)
        activeVbo = ids[0]
        activeIbo = ids[1]
        activeRecords = newRecordTexture()
        GLES30.glDisable(GLES30.GL_CULL_FACE)
    }

    fun onSurfaceChanged(w: Int, h: Int) {
        width = w
        height = h
        GLES30.glViewport(0, 0, w, h)
    }

    /** GL thread: deletes what the renderer made (the canvas is going away). */
    fun release() {
        for (gpu in pageCache.values) deletePage(gpu)
        pageCache.clear()
        GLES30.glDeleteBuffers(2, intArrayOf(activeVbo, activeIbo), 0)
        GLES30.glDeleteTextures(1, intArrayOf(activeRecords), 0)
        for (p in programs.values) GLES30.glDeleteProgram(p.id)
        programs.clear()
    }

    /** Draws one frame; returns the frame rate the visible ink needs (0: draw only on change). */
    fun drawFrame(input: FrameInput): Int {
        GLES30.glClearColor(input.ground[0], input.ground[1], input.ground[2], 1f)
        GLES30.glClearDepthf(1f)
        GLES30.glDepthMask(true)
        GLES30.glColorMask(true, true, true, true)
        GLES30.glDisable(GLES30.GL_SCISSOR_TEST)
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)
        if (width <= 0 || height <= 0 || input.zoom <= 0f) return 0

        val now = referenceNow()
        val time = (now - epoch).toFloat()
        val frame = Frame(
            drawableW = width.toFloat(), drawableH = height.toFloat(),
            viewX = input.originX, viewY = input.originY,
            scale = input.zoom, time = time,
            dry = input.dryDuration, wave = if (input.animate) time else 0f, cool = input.coolDuration,
        )
        val docTop = -input.originY / input.zoom
        val docBottom = (height - input.originY) / input.zoom
        val docLeft = -input.originX / input.zoom
        val docRight = (width - input.originX) / input.zoom
        val visible = input.layout.pagesBetween(docTop - 8f, docBottom + 8f)
        var animationFps = 0
        val pdf = input.pdf
        pdf?.upload()
        val onScreen = ArrayList<PdfTextures.Region>()

        for (index in visible) {
            val x0 = input.layout.left(index)
            val y0 = input.layout.top(index)
            val w = input.layout.width(index)
            val h = input.layout.height(index)
            if (pdf != null) {
                drawPdfPage(frame, pdf, index, x0, y0, w, h, input.fitScale)
                // The part of the page on screen, for a sharper picture when zoomed in.
                val l = max(docLeft, x0)
                val t = max(docTop, y0)
                val r = min(docRight, x0 + w)
                val b = min(docBottom, y0 + h)
                if (r > l && b > t) onScreen.add(PdfTextures.Region(index, l - x0, t - y0, r - l, b - t))
            } else {
                drawPageBackground(frame, x0, y0, w, h, input.paperStyle)
            }
            if (!scissor(frame, x0, y0, w, h)) continue
            val page = if (index < input.pages.size) input.pages[index] else PageInk()
            val gpu = cached(index, page)
            val activeHere = input.active?.takeIf { it.page == index }
            drawStrokes(frame, gpu, x0, y0, activeHere)
            GLES30.glDisable(GLES30.GL_SCISSOR_TEST)

            // Water, lava and lightning need smooth motion; sway, glitter and drying ink are fine at 30.
            if (input.animate) {
                if (gpu.hasWave || activeHere?.brush?.isFastAnimated == true) animationFps = 60
                if (gpu.hasAnimated || activeHere?.brush?.isAnimated == true) animationFps = max(animationFps, 30)
            }
            if (now - gpu.latestWetBirth < input.dryDuration + 0.3) animationFps = max(animationFps, 30)
            if (now - gpu.latestLavaBirth < input.coolDuration + 0.5) animationFps = 60
            if (now - gpu.latestGrassBirth < 3.4 || activeHere?.brush?.growsFlowers == true) animationFps = 60
            if (activeHere?.brush == Brush.LAVA) animationFps = 60
        }
        trimCache(visible)
        if (pdf != null) {
            pdf.want(onScreen, frame.scale)
            pdf.keep(visible)
        }
        return animationFps
    }

    // MARK: pages

    private class Frame(
        val drawableW: Float, val drawableH: Float,
        val viewX: Float, val viewY: Float,
        val scale: Float, val time: Float,
        val dry: Float, val wave: Float, val cool: Float,
    )

    private fun use(name: String, frame: Frame): GlProgram? {
        val p = programs[name] ?: return null
        GLES30.glUseProgram(p.id)
        blend(p.blend)
        GLES30.glUniform2f(p.loc("u_drawableSize"), frame.drawableW, frame.drawableH)
        GLES30.glUniform2f(p.loc("u_viewOffset"), frame.viewX, frame.viewY)
        GLES30.glUniform1f(p.loc("u_scale"), frame.scale)
        GLES30.glUniform1f(p.loc("u_pixelSize"), 1f / frame.scale)
        GLES30.glUniform1f(p.loc("u_time"), frame.time)
        GLES30.glUniform1f(p.loc("u_dryDuration"), frame.dry)
        GLES30.glUniform1f(p.loc("u_waveTime"), frame.wave)
        GLES30.glUniform1f(p.loc("u_coolDuration"), frame.cool)
        return p
    }

    private fun blend(mode: Blend) {
        when (mode) {
            Blend.OPAQUE -> GLES30.glDisable(GLES30.GL_BLEND)
            Blend.ALPHA -> {
                GLES30.glEnable(GLES30.GL_BLEND)
                GLES30.glBlendEquation(GLES30.GL_FUNC_ADD)
                GLES30.glBlendFuncSeparate(GLES30.GL_SRC_ALPHA, GLES30.GL_ONE_MINUS_SRC_ALPHA,
                    GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
            }
            Blend.PREMULTIPLIED -> {
                GLES30.glEnable(GLES30.GL_BLEND)
                GLES30.glBlendEquation(GLES30.GL_FUNC_ADD)
                GLES30.glBlendFuncSeparate(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA,
                    GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
            }
            Blend.MULTIPLY -> {
                GLES30.glEnable(GLES30.GL_BLEND)
                GLES30.glBlendEquation(GLES30.GL_FUNC_ADD)
                GLES30.glBlendFuncSeparate(GLES30.GL_DST_COLOR, GLES30.GL_ZERO, GLES30.GL_ZERO, GLES30.GL_ONE)
            }
        }
    }

    private fun drawPageBackground(frame: Frame, x: Float, y: Float, w: Float, h: Float, style: Int) {
        GLES30.glDisable(GLES30.GL_DEPTH_TEST)
        GLES30.glDepthMask(false)
        disableAttributes()
        val sr = 12f
        use("pageShadow", frame)?.let { p ->
            GLES30.glUniform4f(p.loc("u_rect"), x - sr, y - sr, w + sr * 2, h + sr * 2 + 2)
            GLES30.glUniform4f(p.loc("u_uvRect"), 0f, 0f, 1f, 1f)
            GLES30.glUniform2f(p.loc("u_pageOrigin"), x, y)
            GLES30.glUniform2f(p.loc("u_pageSize"), w, h)
            GLES30.glUniform1ui(p.loc("u_style"), 0)
            GLES30.glUniform1f(p.loc("u_shadowRadius"), sr)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        }
        use("paper", frame)?.let { p ->
            GLES30.glUniform4f(p.loc("u_rect"), x, y, w, h)
            GLES30.glUniform4f(p.loc("u_uvRect"), 0f, 0f, 1f, 1f)
            GLES30.glUniform2f(p.loc("u_pageOrigin"), x, y)
            GLES30.glUniform2f(p.loc("u_pageSize"), w, h)
            GLES30.glUniform1ui(p.loc("u_style"), style)
            GLES30.glUniform1f(p.loc("u_shadowRadius"), 0f)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        }
    }

    /** A PDF page under the ink: its shadow, white until its picture is ready, the picture at about
     *  fit-width size, and over it the sharper picture of the part on screen when zoomed in. */
    private fun drawPdfPage(frame: Frame, pdf: PdfTextures, index: Int, x: Float, y: Float, w: Float, h: Float, fitScale: Float) {
        drawPageBackground(frame, x, y, w, h, 0)
        val base = pdf.base(index, PageSize(w, h), fitScale) ?: return
        drawPicture(frame, base, x, y)
        val detail = pdf.detail(index) ?: return
        if (detail.scale > base.scale * 1.05f) drawPicture(frame, detail, x, y)
    }

    private fun drawPicture(frame: Frame, t: PdfTextures.Texture, x: Float, y: Float) {
        val p = use("texture", frame) ?: return
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, t.id)
        GLES30.glUniform1i(p.loc("u_texture"), 0)
        GLES30.glUniform4f(p.loc("u_rect"), x + t.left, y + t.top, t.width, t.height)
        GLES30.glUniform4f(p.loc("u_uvRect"), 0f, 0f, 1f, 1f)
        GLES30.glUniform2f(p.loc("u_pageOrigin"), x, y)
        GLES30.glUniform2f(p.loc("u_pageSize"), t.width, t.height)
        GLES30.glUniform1ui(p.loc("u_style"), 0)
        GLES30.glUniform1f(p.loc("u_shadowRadius"), 0f)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    }

    /** Limits drawing to the page (its pixels); false when it is off screen. */
    private fun scissor(frame: Frame, x: Float, y: Float, w: Float, h: Float): Boolean {
        val fx0 = floor(x * frame.scale + frame.viewX)
        val fy0 = floor(y * frame.scale + frame.viewY)
        val fx1 = ceil((x + w) * frame.scale + frame.viewX)
        val fy1 = ceil((y + h) * frame.scale + frame.viewY)
        val x0 = fx0.coerceIn(0f, frame.drawableW).toInt()
        val y0 = fy0.coerceIn(0f, frame.drawableH).toInt()
        val x1 = fx1.coerceIn(0f, frame.drawableW).toInt()
        val y1 = fy1.coerceIn(0f, frame.drawableH).toInt()
        if (x1 <= x0 || y1 <= y0) return false
        GLES30.glEnable(GLES30.GL_SCISSOR_TEST)
        // GL counts rows from the bottom.
        GLES30.glScissor(x0, height - y1, x1 - x0, y1 - y0)
        return true
    }

    // MARK: strokes

    private fun drawStrokes(frame: Frame, gpu: PageGpu, x: Float, y: Float, active: ActiveStroke?) {
        // Depth slots: highlighters [0, H), active highlighter H, shadows H+1 (shared), active shadow
        // H+I+1, inks [H+I+2, H+2I+1], active ink H+2I+2 (as on iPad).
        val h = gpu.highlighterStrokes
        val i = gpu.inkStrokes
        val total = h + 2 * i + 3
        val step = 0.9f / (total + 1).toFloat()
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        depthWrite()

        if (gpu.vbo != 0 && (gpu.highlighterIndexCount + gpu.inkIndexCount) > 0) {
            bindRibbons(gpu.vbo, gpu.records)
            if (gpu.highlighterIndexCount > 0) {
                drawRibbon("highlighter", frame, x, y, 0, step, gpu.ibo, 0, gpu.highlighterIndexCount)
            }
            if (gpu.inkIndexCount > 0) {
                if (gpu.has3D && gpu.shadowIndexCount > 0) {
                    drawOnce("shadow", frame, x, y, h + 1, step, gpu.shadowIbo, 0, gpu.shadowIndexCount)
                }
                for (run in gpu.runs) {
                    if (run.blendsOnce) {
                        drawOnce("ink", frame, x, y, i + 2, step, gpu.ibo, run.first, run.count)
                    } else {
                        drawRibbon("ink", frame, x, y, i + 2, step, gpu.ibo, run.first, run.count)
                    }
                }
            }
            if (gpu.bladeCount > 0) drawDecor(frame, gpu, x, y, i + 2, step)
        }

        if (active == null || active.points.isEmpty()) return
        val count = uploadActive(active, frame.time)
        if (count <= 0) return
        bindRibbons(activeVbo, activeRecords)
        val brush = active.brush
        if (brush.isHighlighter) {
            drawRibbon("highlighter", frame, x, y, h, step, activeIbo, 0, count)
            return
        }
        if (brush.castsShadow) drawOnce("shadow", frame, x, y, h + i + 1, step, activeIbo, 0, count)
        if (brush.blendsOnce) {
            drawOnce("ink", frame, x, y, h + 2 * i + 2, step, activeIbo, 0, count)
        } else {
            drawRibbon("ink", frame, x, y, h + 2 * i + 2, step, activeIbo, 0, count)
        }
    }

    private fun depthWrite() {
        GLES30.glDepthFunc(GLES30.GL_LESS)
        GLES30.glDepthMask(true)
    }

    /** The grass pens' blades, then their flowers, instanced from the page's tables (drawDecor on iPad). */
    private fun drawDecor(frame: Frame, gpu: PageGpu, x: Float, y: Float, orderOffset: Int, step: Float) {
        disableAttributes()
        GLES30.glActiveTexture(GLES30.GL_TEXTURE1)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, gpu.bladeTex)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE2)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, if (gpu.flowerTex != 0) gpu.flowerTex else gpu.bladeTex)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, gpu.records)
        for ((name, count, vertices) in listOf(
            Triple("blade", gpu.bladeCount, InkShaders.BLADE_VERTICES),
            Triple("flower", gpu.flowerCount, 4),
        )) {
            if (count <= 0) continue
            val p = use(name, frame) ?: continue
            GLES30.glUniform2f(p.loc("u_pageOrigin"), x, y)
            GLES30.glUniform1ui(p.loc("u_orderOffset"), orderOffset)
            GLES30.glUniform1f(p.loc("u_depthStep"), step)
            GLES30.glUniform1ui(p.loc("u_depthOnly"), 0)
            GLES30.glUniform1i(p.loc("u_strokes"), 0)
            GLES30.glUniform1i(p.loc("u_blades"), 1)
            GLES30.glUniform1i(p.loc("u_flowers"), 2)
            GLES30.glDrawArraysInstanced(GLES30.GL_TRIANGLE_STRIP, 0, vertices, count)
        }
    }

    /** A depth-only pass, then color for the nearest fragment only: where a ribbon folds over itself
     *  (or shadows overlap), see-through parts are blended exactly once. */
    private fun drawOnce(name: String, frame: Frame, x: Float, y: Float, orderOffset: Int, step: Float,
                         ibo: Int, first: Int, count: Int) {
        if (count <= 0) return
        GLES30.glColorMask(false, false, false, false)
        drawRibbon(name, frame, x, y, orderOffset, step, ibo, first, count, depthOnly = true)
        GLES30.glColorMask(true, true, true, true)
        GLES30.glDepthFunc(GLES30.GL_LEQUAL)
        GLES30.glDepthMask(false)
        drawRibbon(name, frame, x, y, orderOffset, step, ibo, first, count)
        depthWrite()
    }

    private fun drawRibbon(name: String, frame: Frame, x: Float, y: Float, orderOffset: Int, step: Float,
                           ibo: Int, first: Int, count: Int, depthOnly: Boolean = false) {
        if (count <= 0) return
        val p = use(name, frame) ?: return
        GLES30.glUniform2f(p.loc("u_pageOrigin"), x, y)
        GLES30.glUniform1ui(p.loc("u_orderOffset"), orderOffset)
        GLES30.glUniform1f(p.loc("u_depthStep"), step)
        GLES30.glUniform1ui(p.loc("u_depthOnly"), if (depthOnly) 1 else 0)
        GLES30.glUniform1i(p.loc("u_strokes"), 0)
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, ibo)
        GLES30.glDrawElements(GLES30.GL_TRIANGLES, count, GLES30.GL_UNSIGNED_INT, first * 4)
    }

    /** The ribbon vertex layout of PORTING.md (48 bytes) and the records on texture unit 0. */
    private fun bindRibbons(vbo: Int, records: Int) {
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo)
        val stride = 48
        val floats = intArrayOf(2, 2, 2, 1, 1, 1, 1, 1)
        var offset = 0
        for (loc in 0 until 8) {
            GLES30.glEnableVertexAttribArray(loc)
            GLES30.glVertexAttribPointer(loc, floats[loc], GLES30.GL_FLOAT, false, stride, offset)
            offset += floats[loc] * 4
        }
        GLES30.glEnableVertexAttribArray(8)
        GLES30.glVertexAttribIPointer(8, 1, GLES30.GL_UNSIGNED_INT, stride, 44)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, records)
    }

    private fun disableAttributes() {
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, 0)
        for (loc in 0..8) GLES30.glDisableVertexAttribArray(loc)
    }

    /** The live stroke's mesh and its one record (order 0), made again every frame. */
    private fun uploadActive(a: ActiveStroke, time: Float): Int {
        scratch.clear()
        RibbonBuilder.append(a.points, 0, a.brush.relaxesCorners, scratch)
        if (scratch.vertexCount == 0 || scratch.indexCount == 0) return 0
        uploadVertices(activeVbo, scratch.vertices, scratch.vertexCount * 12, GLES30.GL_DYNAMIC_DRAW)
        uploadIndices(activeIbo, scratch.indices, scratch.indexCount, GLES30.GL_DYNAMIC_DRAW)
        val rec = FloatArray(12)
        rec[0] = a.color.r; rec[1] = a.color.g; rec[2] = a.color.b; rec[3] = a.color.a
        rec[4] = a.brush.shading.toFloat(); rec[5] = time; rec[6] = a.width; rec[7] = a.seed
        rec[8] = 0f
        uploadRecords(activeRecords, rec, 1)
        return scratch.indexCount
    }

    // MARK: page cache

    private fun cached(index: Int, page: PageInk): PageGpu {
        val gpu = pageCache.getOrPut(index) { PageGpu() }
        if (gpu.version != page.version) build(gpu, page)
        return gpu
    }

    /** Makes the page's buffers from its strokes (meshes already made for a stroke are reused):
     *  highlighters first, then everything else in page order; a stroke's slot is its drawing order. */
    private fun build(gpu: PageGpu, page: PageInk) {
        val ordered = page.strokes.filter { it.brush.isHighlighter } + page.strokes.filter { !it.brush.isHighlighter }
        val meshes = HashMap<Int, StrokeMesh>(ordered.size * 2)
        var vertexTotal = 0
        var indexTotal = 0
        for (s in ordered) {
            val mesh = gpu.meshes[s.id] ?: meshOf(s)
            meshes[s.id] = mesh
            vertexTotal += mesh.vertexCount
            indexTotal += mesh.indices.size
        }
        val vertices = FloatArray(vertexTotal * 12)
        val indices = IntArray(indexTotal)
        val shadow = IntArray(indexTotal)
        val records = FloatArray(max(ordered.size, 1) * 12)
        val runs = ArrayList<InkRun>()
        var v = 0
        var n = 0
        var sh = 0
        var highlighters = 0
        var highlighterIndices = 0
        var has3D = false
        var hasAnimated = false
        var hasWave = false
        var latestWet = Double.NEGATIVE_INFINITY
        var latestLava = Double.NEGATIVE_INFINITY
        var latestGrass = Double.NEGATIVE_INFINITY
        val grass = HashMap<Int, GrassField>()
        val blades = FloatBuilder()
        val flowers = FloatBuilder()
        for ((slot, s) in ordered.withIndex()) {
            val mesh = meshes.getValue(s.id)
            System.arraycopy(mesh.vertices, 0, vertices, v * 12, mesh.vertexCount * 12)
            val slotBits = java.lang.Float.intBitsToFloat(slot)
            for (k in 0 until mesh.vertexCount) vertices[(v + k) * 12 + 11] = slotBits
            val start = n
            for (index in mesh.indices) indices[n++] = index + v
            v += mesh.vertexCount
            val count = n - start
            val r = slot * 12
            records[r] = s.color.r; records[r + 1] = s.color.g; records[r + 2] = s.color.b; records[r + 3] = s.color.a
            records[r + 4] = s.brush.shading.toFloat(); records[r + 5] = (s.birth - epoch).toFloat()
            records[r + 6] = s.width; records[r + 7] = s.seed
            records[r + 8] = slot.toFloat()
            if (s.brush.isHighlighter) {
                highlighters++
                highlighterIndices += count
                continue
            }
            if (count > 0) {
                val last = runs.lastOrNull()
                if (!s.brush.blendsOnce && last != null && !last.blendsOnce && last.first + last.count == start) {
                    last.count += count
                } else {
                    runs.add(InkRun(start, count, s.brush.blendsOnce))
                }
            }
            if (s.brush.castsShadow) {
                has3D = true
                System.arraycopy(indices, start, shadow, sh, count)
                sh += count
            }
            if (s.brush.isAnimated) hasAnimated = true
            if (s.brush.isFastAnimated) hasWave = true
            if (s.brush == Brush.WET) latestWet = max(latestWet, s.birth)
            if (s.brush == Brush.LAVA) latestLava = max(latestLava, lavaCoolEnd(s))
            if (s.brush.growsFlowers) {
                latestGrass = max(latestGrass, s.birth)
                val field = gpu.grass[s.id] ?: GrassGenerator.field(s.brush, s.points, s.width, s.color, s.seed)
                grass[s.id] = field
                // Blades sprout in drawing order over the time the pen took; flowers open after it lifts.
                val end = (s.birth - epoch).toFloat()
                val duration = s.duration.coerceIn(0.0, 60.0).toFloat()
                appendDecor(field, slot, s.color.a, end - duration, duration, end, blades, flowers)
            }
        }

        if (gpu.vbo == 0) {
            val ids = IntArray(3)
            GLES30.glGenBuffers(3, ids, 0)
            gpu.vbo = ids[0]; gpu.ibo = ids[1]; gpu.shadowIbo = ids[2]
            gpu.records = newRecordTexture()
        }
        uploadVertices(gpu.vbo, vertices, vertices.size, GLES30.GL_STATIC_DRAW)
        uploadIndices(gpu.ibo, indices, indices.size, GLES30.GL_STATIC_DRAW)
        uploadIndices(gpu.shadowIbo, shadow, sh, GLES30.GL_STATIC_DRAW)
        uploadRecords(gpu.records, records, max(ordered.size, 1))
        gpu.highlighterIndexCount = highlighterIndices
        gpu.inkIndexCount = indexTotal - highlighterIndices
        gpu.shadowIndexCount = sh
        gpu.highlighterStrokes = highlighters
        gpu.inkStrokes = ordered.size - highlighters
        gpu.runs = runs
        gpu.has3D = has3D
        gpu.hasAnimated = hasAnimated
        gpu.hasWave = hasWave
        gpu.latestWetBirth = latestWet
        gpu.latestLavaBirth = latestLava
        gpu.meshes = meshes
        gpu.bladeCount = blades.size / 16
        gpu.flowerCount = flowers.size / 16
        if (gpu.bladeCount > 0) {
            if (gpu.bladeTex == 0) gpu.bladeTex = newRecordTexture()
            uploadTable(gpu.bladeTex, blades.data, gpu.bladeCount)
        }
        if (gpu.flowerCount > 0) {
            if (gpu.flowerTex == 0) gpu.flowerTex = newRecordTexture()
            uploadTable(gpu.flowerTex, flowers.data, gpu.flowerCount)
        }
        gpu.latestGrassBirth = latestGrass
        gpu.grass = grass
        gpu.version = page.version
    }

    /** A grass field as GPU records (appendGPU on iPad): blades sprout between `birthStart` and
     *  `birthStart + duration` in drawing order; flowers open `delay` seconds after `bloomBase`. */
    private fun appendDecor(field: GrassField, stroke: Int, alpha: Float, birthStart: Float, duration: Float,
                            bloomBase: Float, blades: FloatBuilder, flowers: FloatBuilder) {
        val offset = blades.size / 16
        val n = max(field.blades.size, 1).toFloat()
        for ((k, b) in field.blades.withIndex()) {
            blades.add(b.base.x, b.base.y, b.height, b.width)
            blades.add(b.lean, b.phase, birthStart + b.arc * duration, 1f - (k + 1f) / (n + 1f))
            blades.add(b.color.x, b.color.y, b.color.z, alpha)
            blades.add(stroke.toFloat(), b.kind.raw.toFloat(), b.stiffness, 0f)
        }
        for (f in field.flowers) {
            val stemArc = field.blades.getOrNull(f.stem)?.arc ?: 0f
            flowers.add((offset + f.stem).toFloat(), f.radius, bloomBase + f.delay + stemArc * 0.3f, f.petals)
            flowers.add(f.petal.x, f.petal.y, f.petal.z, 1f)
            flowers.add(f.core.x, f.core.y, f.core.z, 1f)
            flowers.add(f.spin, f.style, 0f, 0f)
        }
    }

    private fun meshOf(s: Stroke): StrokeMesh {
        scratch.clear()
        RibbonBuilder.append(s.points, 0, s.brush.relaxesCorners, scratch)
        return StrokeMesh(scratch.vertices.copyOf(scratch.vertexCount * 12), scratch.vertexCount,
            scratch.indices.copyOf(scratch.indexCount))
    }

    /** When the last point of a lava stroke starts cooling (lava cools from its first point to its
     *  last at 380 points a second, as in the lava shader). */
    private fun lavaCoolEnd(s: Stroke): Double {
        var length = 0.0
        for (k in 1 until s.points.size) {
            val dx = (s.points[k].x - s.points[k - 1].x).toDouble()
            val dy = (s.points[k].y - s.points[k - 1].y).toDouble()
            length += kotlin.math.sqrt(dx * dx + dy * dy)
        }
        return s.birth + length / 380.0
    }

    private fun trimCache(visible: List<Int>) {
        if (pageCache.size <= 24 || visible.isEmpty()) return
        val keep = (visible.first() - 6)..(visible.last() + 6)
        val drop = pageCache.keys.filter { it !in keep }
        for (k in drop) pageCache.remove(k)?.let { deletePage(it) }
    }

    private fun deletePage(gpu: PageGpu) {
        if (gpu.vbo != 0) GLES30.glDeleteBuffers(3, intArrayOf(gpu.vbo, gpu.ibo, gpu.shadowIbo), 0)
        if (gpu.records != 0) GLES30.glDeleteTextures(1, intArrayOf(gpu.records), 0)
        for (t in intArrayOf(gpu.bladeTex, gpu.flowerTex)) if (t != 0) GLES30.glDeleteTextures(1, intArrayOf(t), 0)
    }

    // MARK: uploads

    private fun uploadVertices(vbo: Int, data: FloatArray, count: Int, usage: Int) {
        val buffer = ByteBuffer.allocateDirect(max(count, 1) * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        buffer.put(data, 0, count)
        buffer.position(0)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo)
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, max(count, 1) * 4, buffer, usage)
    }

    private fun uploadIndices(ibo: Int, data: IntArray, count: Int, usage: Int) {
        val buffer = ByteBuffer.allocateDirect(max(count, 1) * 4).order(ByteOrder.nativeOrder()).asIntBuffer()
        buffer.put(data, 0, count)
        buffer.position(0)
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, ibo)
        GLES30.glBufferData(GLES30.GL_ELEMENT_ARRAY_BUFFER, max(count, 1) * 4, buffer, usage)
    }

    private fun newRecordTexture(): Int {
        val ids = IntArray(1)
        GLES30.glGenTextures(1, ids, 0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, ids[0])
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
        return ids[0]
    }

    /** Records as PORTING.md lays them out: 3 RGBA32F texels each, 512 to a row of 1536 texels. */
    private fun uploadRecords(texture: Int, records: FloatArray, count: Int) {
        val rows = max(1, (count + RECORDS_PER_ROW - 1) / RECORDS_PER_ROW)
        val floats = rows * RECORDS_PER_ROW * 12
        val buffer: FloatBuffer = ByteBuffer.allocateDirect(floats * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        buffer.put(records, 0, min(records.size, count * 12))
        buffer.position(0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 4)
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA32F, RECORDS_PER_ROW * 3, rows, 0,
            GLES30.GL_RGBA, GLES30.GL_FLOAT, buffer)
    }

    /** Blade and flower records as InkShaders lays them out: 4 RGBA32F texels each, 256 to a row. */
    private fun uploadTable(texture: Int, records: FloatArray, count: Int) {
        val perRow = 256
        val rows = max(1, (count + perRow - 1) / perRow)
        val floats = rows * perRow * 16
        val buffer: FloatBuffer = ByteBuffer.allocateDirect(floats * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        buffer.put(records, 0, min(records.size, count * 16))
        buffer.position(0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 4)
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA32F, perRow * 4, rows, 0,
            GLES30.GL_RGBA, GLES30.GL_FLOAT, buffer)
    }

    // MARK: programs

    private fun link(name: String, vertex: String, fragment: String): Int {
        val vs = compile(name, GLES30.GL_VERTEX_SHADER, vertex)
        val fs = compile(name, GLES30.GL_FRAGMENT_SHADER, fragment)
        if (vs == 0 || fs == 0) return 0
        val program = GLES30.glCreateProgram()
        GLES30.glAttachShader(program, vs)
        GLES30.glAttachShader(program, fs)
        for ((loc, attribute) in ATTRIBUTES.withIndex()) GLES30.glBindAttribLocation(program, loc, attribute)
        GLES30.glLinkProgram(program)
        val status = IntArray(1)
        GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, status, 0)
        GLES30.glDeleteShader(vs)
        GLES30.glDeleteShader(fs)
        if (status[0] == 0) {
            Log.e(TAG, "link $name: ${GLES30.glGetProgramInfoLog(program)}")
            GLES30.glDeleteProgram(program)
            return 0
        }
        return program
    }

    private fun compile(name: String, type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)
        val status = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            Log.e(TAG, "compile $name (${if (type == GLES30.GL_VERTEX_SHADER) "vertex" else "fragment"}): " +
                GLES30.glGetShaderInfoLog(shader))
            GLES30.glDeleteShader(shader)
            return 0
        }
        return shader
    }

    private companion object {
        const val TAG = "MurekkepInk"
        const val RECORDS_PER_ROW = 512
        val ATTRIBUTES = listOf("a_center", "a_offset", "a_tangent", "a_r", "a_u", "a_side", "a_arc", "a_ink", "a_stroke")
    }
}

package com.murekkep.notebook.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.murekkep.notebook.data.PenPreferences
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.EraserMode
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkEraser
import com.murekkep.notebook.ink.PageInk
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.Vec2

// Ink, tools and undo for one open notebook: the part of Murekkep.swiftpm/EditorModel.swift the
// Android edition has (pens, the eraser, undo, the blank page at the end; no stickers, shapes,
// lasso edits, text pen or PDFs yet). The canvas reads `pages` on its render thread, so the list is
// replaced whole on every change and never mutated: a frame always sees one consistent snapshot.
// Everything else runs on the main thread (touch events and the chrome).

/** What the pen does on the page. */
sealed class Tool {
    data class Brush(val brush: com.murekkep.notebook.ink.Brush) : Tool()

    data object Eraser : Tool()

    /** Select strokes by drawing around them (the canvas does not do it yet). */
    data object Lasso : Tool()

    val selectedBrush: com.murekkep.notebook.ink.Brush?
        get() = (this as? Brush)?.brush
}

/** One undoable change on a page: its strokes before and after. */
class InkEdit(val page: Int, val before: List<Stroke>, val after: List<Stroke>)

class EditorState(
    /** The notebook's folder name in the store; null for a notebook that is never saved. */
    val notebookId: String? = null,
    initialPages: List<List<Stroke>> = emptyList(),
    /** Per-pen colors and widths kept between sessions; null keeps them for this run only. */
    private val prefs: PenPreferences? = null,
    /** The ink file could not be read (damaged, or written by a newer Mürekkep): nothing is changed
     *  or written, so the file stays for a build that can read it. */
    val readOnly: Boolean = false,
) {
    companion object {
        /** A4 in points. */
        const val A4_WIDTH = 595.28f
        const val A4_HEIGHT = 841.89f
        const val DEFAULT_ERASER_SIZE = 18f
        private const val UNDO_LIMIT = 300
    }

    /** Every page is A4 in points: 595.28 x 841.89. */
    val pageSize: Pair<Float, Float> = Pair(A4_WIDTH, A4_HEIGHT)

    /** Snapshot of every page's ink. Pages never go, and a blank page always ends the notebook. */
    @Volatile
    var pages: List<PageInk> = emptyList()
        private set

    /** The notebook's title, for the top bar. */
    var title by mutableStateOf("")

    var pageCount by mutableStateOf(1)
        private set

    // Tools

    private val firstBrush: Brush = prefs?.lastBrush() ?: Brush.PEN
    private val toolState = mutableStateOf<Tool>(Tool.Brush(firstBrush))
    private val lastBrushState = mutableStateOf(firstBrush)

    /** Set while the eraser is only borrowed (the pen's side button): the tool to return to. */
    private var eraserReturn: Tool? = null

    /** Tool.Brush(brush), Tool.Eraser or Tool.Lasso; observable from Compose. */
    var tool: Tool
        get() = toolState.value
        set(value) {
            val old = toolState.value
            if (old == value) return
            previousTool = old
            toolState.value = value
            if (value is Tool.Brush) {
                lastBrushState.value = value.brush
                prefs?.rememberBrush(value.brush)
            }
            if (value !is Tool.Eraser) eraserReturn = null
        }

    /** Tool before the last change (the pen's "switch to previous tool"). */
    var previousTool: Tool = Tool.Eraser
        private set

    /** The last pen picked: what tools that draw without a pen of their own use. */
    val lastBrush: Brush get() = lastBrushState.value

    /** Brush the color and width controls apply to (the last brush while another tool is active). */
    val activeBrush: Brush get() = tool.selectedBrush ?: lastBrush

    private val colors = mutableStateMapOf<Brush, InkColor>()
    private val widths = mutableStateMapOf<Brush, Float>()

    var eraserMode by mutableStateOf(EraserMode.STROKE)

    /** The eraser's diameter in page points. */
    var eraserSize by mutableStateOf(DEFAULT_ERASER_SIZE)

    /** The pen's side button or squeeze held: erases, and when let go returns to the tool it borrowed from. */
    var temporaryEraser: Boolean
        get() = eraserReturn != null && tool is Tool.Eraser
        set(value) {
            if (value) beginTemporaryEraser() else endTemporaryEraser()
        }

    // Hooks

    /** The canvas asks for a frame. */
    var onInkChange: (() -> Unit)? = null

    /** A page was added: the canvas lays the pages out again. */
    var onLayoutChange: (() -> Unit)? = null

    /** The store saves after a pause in writing. */
    var onDirty: (() -> Unit)? = null

    /** The store saves at once (the screen is leaving, or the app goes to the background). */
    var onSaveNow: (() -> Unit)? = null

    /** Changes since the last `markSaved`. */
    @Volatile
    var dirty: Boolean = false
        private set

    // Undo

    private val undoStack = ArrayDeque<InkEdit>()
    private val redoStack = ArrayDeque<InkEdit>()

    /** The page being erased and its strokes before the touch began. */
    private var eraseSnapshot: Pair<Int, List<Stroke>>? = null

    var canUndo by mutableStateOf(false)
        private set

    var canRedo by mutableStateOf(false)
        private set

    init {
        for (b in Brush.entries) {
            colors[b] = prefs?.color(b) ?: b.palette[0]
            widths[b] = (prefs?.width(b) ?: b.defaultWidth).coerceIn(b.widthRange)
        }
        var list: List<PageInk> = initialPages.map { PageInk(it, 1) }
        if (list.isEmpty()) list = listOf(PageInk(emptyList(), 1))
        // An opened notebook ends in a blank page too (keepBlankPageAtEnd), in memory only: opening
        // writes nothing; the page is saved with the next change.
        if (!readOnly && list.last().strokes.isNotEmpty()) list = list + PageInk(emptyList(), 1)
        pages = list
        pageCount = list.size
    }

    // MARK: Tools

    fun color(brush: Brush): InkColor = colors[brush] ?: brush.palette[0]

    fun width(brush: Brush): Float = widths[brush] ?: brush.defaultWidth

    fun setColor(brush: Brush, color: InkColor) {
        colors[brush] = color
        prefs?.setColor(brush, color)
    }

    fun setWidth(brush: Brush, width: Float) {
        val w = width.coerceIn(brush.widthRange)
        widths[brush] = w
        prefs?.setWidth(brush, w)
    }

    fun toggleEraser() {
        if (tool is Tool.Eraser) leaveEraser() else tool = Tool.Eraser
    }

    /** Leaves the eraser, borrowed or picked: back to the tool before it (the last pen when the
     *  eraser was all there was). */
    fun leaveEraser() {
        if (tool !is Tool.Eraser) return
        if (eraserReturn != null) {
            endTemporaryEraser()
        } else {
            tool = if (previousTool is Tool.Eraser) Tool.Brush(lastBrush) else previousTool
        }
    }

    /** The pen's "switch to previous tool". */
    fun switchToPrevious() {
        tool = if (previousTool == tool) Tool.Brush(Brush.PEN) else previousTool
    }

    private fun beginTemporaryEraser() {
        if (tool is Tool.Eraser) return
        val back = tool
        tool = Tool.Eraser
        eraserReturn = back
    }

    private fun endTemporaryEraser() {
        val back = eraserReturn ?: return
        eraserReturn = null
        if (tool is Tool.Eraser) tool = back
    }

    // MARK: Editing

    fun addStroke(page: Int, stroke: Stroke) {
        if (readOnly || page !in pages.indices) return
        val before = pages[page].strokes
        record(page, before, before + stroke)
    }

    /** Removes and adds strokes on a page as one undoable step. */
    fun replaceStrokes(page: Int, removing: Set<Int>, adding: List<Stroke>) {
        if (readOnly || page !in pages.indices || (removing.isEmpty() && adding.isEmpty())) return
        val before = pages[page].strokes
        record(page, before, before.filter { it.id !in removing } + adding)
    }

    fun strokes(page: Int): List<Stroke> = pages.getOrNull(page)?.strokes ?: emptyList()

    /** True when the page has ink on it. */
    fun pageIsUsed(page: Int): Boolean = pages.getOrNull(page)?.strokes?.isNotEmpty() == true

    // MARK: Erasing

    fun beginErase(page: Int) {
        if (readOnly || page !in pages.indices) return
        eraseSnapshot = Pair(page, pages[page].strokes)
    }

    /** Erases along the path a→b (page points) with the eraser's radius. */
    fun erase(page: Int, from: Vec2, to: Vec2) {
        if (readOnly) return
        val current = pages.getOrNull(page) ?: return
        val radius = eraserSize / 2f
        val strokes = current.strokes
        // Most samples touch no ink: find the first stroke touched before copying the page's list.
        // `hits` is looser than the cut of `erase` (r·0.8 per segment against r·0.5 per point on it),
        // so a stroke it misses would keep every point anyway.
        val first = strokes.indexOfFirst { InkEraser.hits(it, from, to, radius) }
        if (first < 0) return
        val result = ArrayList<Stroke>(strokes.size)
        for (i in 0 until first) result.add(strokes[i])
        var changed = false
        for (i in first until strokes.size) {
            val s = strokes[i]
            when (eraserMode) {
                EraserMode.STROKE -> {
                    if (InkEraser.hits(s, from, to, radius)) {
                        changed = true
                    } else {
                        result.add(s)
                    }
                }
                EraserMode.PARTIAL -> {
                    val pieces = if (InkEraser.hits(s, from, to, radius)) InkEraser.erase(s, from, to, radius) else null
                    if (pieces != null) {
                        changed = true
                        result.addAll(pieces)
                    } else {
                        result.add(s)
                    }
                }
            }
        }
        if (!changed) return
        setPage(page, result)
        onInkChange?.invoke()
    }

    /** The eraser touch ended: what it removed becomes one undo step. */
    fun endErase() {
        val (page, before) = eraseSnapshot ?: return
        eraseSnapshot = null
        val after = pages.getOrNull(page)?.strokes ?: return
        // Strokes are equal when they are the same stroke (by id).
        if (after == before) return
        pushUndo(InkEdit(page, before, after))
        markDirty()
    }

    /** Puts back what an interrupted eraser touch removed (a palm or a second finger cancelled it). */
    fun cancelErase() {
        val (page, before) = eraseSnapshot ?: return
        eraseSnapshot = null
        val current = pages.getOrNull(page) ?: return
        if (current.strokes == before) return
        setPage(page, before)
        onInkChange?.invoke()
    }

    // MARK: Undo

    fun undo() {
        val edit = undoStack.removeLastOrNull() ?: return
        if (edit.page in pages.indices) setPage(edit.page, edit.before)
        redoStack.addLast(edit)
        updateUndoFlags()
        markDirty()
        onInkChange?.invoke()
    }

    fun redo() {
        val edit = redoStack.removeLastOrNull() ?: return
        if (edit.page in pages.indices) setPage(edit.page, edit.after)
        undoStack.addLast(edit)
        updateUndoFlags()
        markDirty()
        onInkChange?.invoke()
    }

    /** Applies a page's new strokes as one undo step. */
    private fun record(page: Int, before: List<Stroke>, after: List<Stroke>) {
        setPage(page, after)
        pushUndo(InkEdit(page, before, after))
        markDirty()
        onInkChange?.invoke()
        keepBlankPageAtEnd()
    }

    private fun pushUndo(edit: InkEdit) {
        undoStack.addLast(edit)
        if (undoStack.size > UNDO_LIMIT) undoStack.removeFirst()
        redoStack.clear()
        updateUndoFlags()
    }

    private fun updateUndoFlags() {
        val u = undoStack.isNotEmpty()
        val r = redoStack.isNotEmpty()
        if (canUndo != u) canUndo = u
        if (canRedo != r) canRedo = r
    }

    /** Replaces a page's strokes and bumps its version (the GPU caches follow it). */
    private fun setPage(index: Int, strokes: List<Stroke>) {
        val list = pages.toMutableList()
        list[index] = PageInk(strokes, list[index].version + 1)
        pages = list
    }

    // MARK: Pages

    /** Adds a blank page at the end (the chrome's "new page"). */
    fun addPage() {
        if (readOnly) return
        appendBlankPage()
    }

    /** A notebook always ends in a blank page: the moment ink lands on the last page, a blank one
     *  joins after it, so the next page is there before the pen gets to it (no pulling at the end).
     *  Pages only come this way, they never go: an undo leaves the blank page in place. */
    private fun keepBlankPageAtEnd() {
        if (readOnly) return
        if (pages.lastOrNull()?.strokes?.isNotEmpty() != true) return
        appendBlankPage()
    }

    private fun appendBlankPage() {
        pages = pages + PageInk(emptyList(), 1)
        pageCount = pages.size
        markDirty()
        onLayoutChange?.invoke()
        onInkChange?.invoke()
    }

    // MARK: Saving

    private fun markDirty() {
        dirty = true
        onDirty?.invoke()
    }

    /** The store took a snapshot of the pages to write. */
    fun markSaved() {
        dirty = false
    }

    /** Asks the store to write the notebook now. */
    fun requestSave() {
        onSaveNow?.invoke()
    }
}

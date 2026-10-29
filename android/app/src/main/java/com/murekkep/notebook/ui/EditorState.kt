package com.murekkep.notebook.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.murekkep.notebook.data.PaperStyle
import com.murekkep.notebook.data.PenPreferences
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.EraserMode
import com.murekkep.notebook.ink.InkColor
import com.murekkep.notebook.ink.InkEraser
import com.murekkep.notebook.ink.InkSelection
import com.murekkep.notebook.ink.Lasso
import com.murekkep.notebook.ink.EditableShape
import com.murekkep.notebook.ink.PageInk
import com.murekkep.notebook.ink.PenPaths
import com.murekkep.notebook.ink.Pt
import com.murekkep.notebook.ink.ShapeBuilder
import com.murekkep.notebook.ink.ShapeEditState
import com.murekkep.notebook.ink.ShapeHandleFeedback
import com.murekkep.notebook.ink.ShapeKind
import com.murekkep.notebook.ink.Stroke
import com.murekkep.notebook.ink.Vec2
import com.murekkep.notebook.ink.referenceNow
import com.murekkep.notebook.ink.restroke
import com.murekkep.notebook.render.PageLayout
import com.murekkep.notebook.render.PageSize
import java.io.File
import kotlin.math.hypot
import kotlin.random.Random

// Ink, tools and undo for one open notebook: the part of Murekkep.swiftpm/EditorModel.swift the
// Android edition has (pens, the eraser, the lasso, held shapes and the shape tool, undo, the blank
// page at the end of a notebook, imported PDFs; no stickers or text pen yet). The canvas reads `pages` on its render thread, so the list is
// replaced whole on every change and never mutated: a frame always sees one consistent snapshot.
// Everything else runs on the main thread (touch events and the chrome).

/** What the pen does on the page. */
sealed class Tool {
    data class Brush(val brush: com.murekkep.notebook.ink.Brush) : Tool()

    data object Eraser : Tool()

    /** Select strokes by drawing around them, then move, resize, turn or restyle them. */
    data object Lasso : Tool()

    /** Drag a line, arrow, box, oval, triangle or regular polygon (`EditorState.shapeKind`). */
    data object Shape : Tool()

    val selectedBrush: com.murekkep.notebook.ink.Brush?
        get() = (this as? Brush)?.brush
}

/** One undoable change on a page: its strokes before and after, and the changes on other pages made
 *  in the same step (a selection carried to another page). */
class InkEdit(val page: Int, val before: List<Stroke>, val after: List<Stroke>, val linked: List<InkEdit> = emptyList())

class EditorState(
    /** The notebook's folder name in the store; null for a notebook that is never saved. */
    val notebookId: String? = null,
    initialPages: List<List<Stroke>> = emptyList(),
    /** Per-pen colors and widths kept between sessions; null keeps them for this run only. */
    private val prefs: PenPreferences? = null,
    /** The ink file could not be read (damaged, or written by a newer Mürekkep): nothing is changed
     *  or written, so the file stays for a build that can read it. */
    val readOnly: Boolean = false,
    /** An imported PDF's page sizes: its pages are the PDF's and none are added. Null for a notebook,
     *  whose pages are A4. */
    val pageSizes: List<PageSize>? = null,
    /** The PDF the pages are drawn on (its `source.pdf`), for the canvas and the export. */
    val pdfFile: File? = null,
    /** The notebook's page template, for the export and the library's cover. */
    val paper: PaperStyle = PaperStyle.LINED,
) {
    companion object {
        /** A4 in points. */
        const val A4_WIDTH = 595.28f
        const val A4_HEIGHT = 841.89f
        const val DEFAULT_ERASER_SIZE = 18f
        private const val UNDO_LIMIT = 300
    }

    /** Pages written on an imported PDF. */
    val isPdf: Boolean get() = pageSizes != null

    private var cachedLayout: PageLayout? = null

    /** Where the pages stand in the document (main thread). */
    fun layout(): PageLayout {
        cachedLayout?.let { if (it.pageCount == pages.size) return it }
        return (pageSizes?.let { PageLayout(it) } ?: PageLayout(pages.size)).also { cachedLayout = it }
    }

    /** Snapshot of every page's ink. Pages never go, and a blank page always ends the notebook. */
    @Volatile
    var pages: List<PageInk> = emptyList()
        private set

    /** The notebook's title, for the top bar. */
    var title by mutableStateOf("")

    var pageCount by mutableStateOf(1)
        private set

    /** The page in the middle of the view, from the canvas; the page badge shows it. */
    var currentPage by mutableStateOf(0)

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
                rememberRecent(value.brush)
            }
            if (value !is Tool.Eraser) eraserReturn = null
            if (value !is Tool.Lasso && selection != null) clearSelection()
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

    /** The starred pens: always in the bar (PenStripRule). */
    var favoriteBrushes: List<Brush> by mutableStateOf(prefs?.favoriteBrushes() ?: emptyList())
        private set

    /** The pens picked last, newest first: they fill the bar up. */
    var recentBrushes: List<Brush> by mutableStateOf(prefs?.recentBrushes() ?: PenStripRule.defaultRecent)
        private set

    /** The bar's pens: the favourites, then the recent ones, each in the panel's order. */
    val barPens: Pair<List<Brush>, List<Brush>>
        get() = PenStripRule.pens(favoriteBrushes, recentBrushes, Brush.paletteOrder)

    fun isFavorite(brush: Brush): Boolean = brush in favoriteBrushes

    /** Stars a pen, or takes its star away (a long press on it in the bar). */
    fun toggleFavorite(brush: Brush) {
        favoriteBrushes = PenStripRule.toggled(brush, favoriteBrushes)
        prefs?.setFavoriteBrushes(favoriteBrushes)
    }

    private fun rememberRecent(brush: Brush) {
        val list = PenStripRule.remembered(brush, recentBrushes)
        if (list === recentBrushes) return
        recentBrushes = list
        prefs?.setRecentBrushes(list)
    }

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

    // Selection (lasso)

    private val selectionState = mutableStateOf<InkSelection?>(null)

    /** The strokes the lasso picked; observable (the selection bar shows while there is one). The
     *  canvas frames it, so a change asks for a frame. */
    var selection: InkSelection?
        get() = selectionState.value
        private set(value) {
            if (selectionState.value == value) return
            selectionState.value = value
            onInkChange?.invoke()
        }

    /** The selection while it is dragged, resized or turned. Kept out of Compose until the drag ends,
     *  so the chrome is not recomposed on every move. */
    var liveSelection: InkSelection? = null
        private set

    /** What the canvas frames: the live selection during a drag, else the selection. */
    val displayedSelection: InkSelection? get() = liveSelection ?: selection

    /** The selection's page as it was when a drag began, and the ids that were selected then. */
    private var selectionSnapshot: Pair<List<Stroke>, Set<Int>>? = null

    // Shapes

    /** The shape tool's shape, its dashes and a regular polygon's sides (for this session, as on iPad). */
    var shapeKind by mutableStateOf(ShapeKind.LINE)
    var shapeDashed by mutableStateOf(false)
    var polygonSides by mutableStateOf(6)

    /** A shape the held pen just drew, with handles on its corners until the next touch elsewhere.
     *  The canvas draws the handles, so a change asks for a frame. */
    var shapeEdit: ShapeEditState? = null
        private set(value) {
            if (field == value) return
            field = value
            onInkChange?.invoke()
        }

    /** The page's strokes when a handle drag began: the drag is one undo step. */
    private var shapeEditSnapshot: List<Stroke>? = null

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
        if (!readOnly && pageSizes == null && list.last().strokes.isNotEmpty()) list = list + PageInk(emptyList(), 1)
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

    // MARK: Selection (lasso)

    /** Selects the strokes of `page` that lie mostly inside the lasso (a page-local loop). True when
     *  it took something. */
    fun selectStrokes(page: Int, lasso: List<Vec2>): Boolean {
        if (page !in pages.indices || lasso.size < 3) {
            clearSelection()
            return false
        }
        updateSelection(page, Lasso.select(pages[page].strokes, lasso))
        return selection != null
    }

    /** Selects the one stroke under a lasso tap. False when nothing is there. */
    fun selectItem(page: Int, at: Vec2, tolerance: Float): Boolean {
        val s = Lasso.strokeAt(strokes(page), at, tolerance) ?: return false
        updateSelection(page, setOf(s.id))
        return true
    }

    fun clearSelection() {
        liveSelection = null
        selectionSnapshot = null
        if (selection != null) selection = null
    }

    private fun updateSelection(page: Int, ids: Set<Int>) {
        val s = makeSelection(page, ids)
        if (s == null) clearSelection() else selection = s
    }

    private fun makeSelection(page: Int, ids: Set<Int>): InkSelection? {
        if (ids.isEmpty() || page !in pages.indices) return null
        val box = Lasso.bounds(pages[page].strokes, ids) ?: return null
        return InkSelection(page, ids, box)
    }

    /** A drag on the selection begins: its moves become one undo step when it ends. */
    fun beginSelectionEdit() {
        val sel = selection ?: return
        if (readOnly || sel.page !in pages.indices) return
        selectionSnapshot = Pair(pages[sel.page].strokes, sel.ids)
    }

    /** Moves the selection by `offset`, scales it around `anchor` and turns it by `rotation` radians
     *  around `anchor`, relative to where the drag began. */
    fun transformSelection(offset: Vec2, scale: Float, anchor: Vec2, rotation: Float = 0f) {
        val sel = selection ?: return
        val (strokes, ids) = selectionSnapshot ?: return
        if (sel.page !in pages.indices) return
        val moved = Lasso.transform(strokes, ids, offset, scale, anchor, rotation)
        // The moved strokes are the ones that were not on the page when the drag began.
        val before = strokes.mapTo(HashSet()) { it.id }
        setPage(sel.page, moved)
        liveSelection = makeSelection(sel.page, moved.filter { it.id !in before }.mapTo(HashSet()) { it.id })
        onInkChange?.invoke()
    }

    /** The drag ended: one undo step, or, when the selection's middle is now over another page, the
     *  strokes move to that page (one step for both pages). */
    fun endSelectionEdit() {
        liveSelection?.let {
            liveSelection = null
            selection = it
        }
        val sel = selection ?: return
        val (strokes, _) = selectionSnapshot ?: return
        selectionSnapshot = null
        if (sel.page !in pages.indices) return
        val target = dropPage(sel)
        if (target != null) {
            carrySelection(sel, strokes, target)
            return
        }
        val after = pages[sel.page].strokes
        if (after.map { it.id } == strokes.map { it.id }) return
        pushUndo(InkEdit(sel.page, strokes, after))
        markDirty()
    }

    /** The page a selection belongs to once dropped with its middle over another page. */
    private fun dropPage(sel: InkSelection): Int? {
        val layout = layout()
        val c = layout.toDoc(sel.page, (sel.bounds.minX + sel.bounds.maxX) / 2f, (sel.bounds.minY + sel.bounds.maxY) / 2f)
        val target = layout.pageAt(c.x, c.y) ?: return null
        return if (target != sel.page && target in pages.indices) target else null
    }

    /** Carries the selected strokes from their page to `target`, where they stay at the same place on
     *  the document. One undo step puts both pages back. */
    private fun carrySelection(sel: InkSelection, before: List<Stroke>, target: Int) {
        val layout = layout()
        val dx = layout.left(sel.page) - layout.left(target)
        val dy = layout.top(sel.page) - layout.top(target)
        val carried = Lasso.shifted(pages[sel.page].strokes.filter { it.id in sel.ids }, dx, dy)
        val after = pages[sel.page].strokes.filter { it.id !in sel.ids }
        val targetBefore = pages[target].strokes
        val targetAfter = targetBefore + carried
        setPage(sel.page, after)
        setPage(target, targetAfter)
        pushUndo(InkEdit(sel.page, before, after, linked = listOf(InkEdit(target, targetBefore, targetAfter))))
        markDirty()
        onInkChange?.invoke()
        keepBlankPageAtEnd()
        updateSelection(target, carried.mapTo(HashSet()) { it.id })
    }

    fun deleteSelection() {
        val sel = selection ?: return
        replaceStrokes(sel.page, removing = sel.ids, adding = emptyList())
        clearSelection()
    }

    /** A copy of the selection a little lower and to the right; the copy is selected. */
    fun duplicateSelection() {
        val sel = selection ?: return
        if (readOnly) return
        val copies = Lasso.shifted(strokes(sel.page).filter { it.id in sel.ids }, 18f, 18f)
        replaceStrokes(sel.page, removing = emptySet(), adding = copies)
        updateSelection(sel.page, copies.mapTo(HashSet()) { it.id })
    }

    /** Gives the selected strokes the current pen and its color (3D inks included); they are drawn
     *  anew, so wet ink dries and lava cools again. */
    fun restyleSelection() {
        val sel = selection ?: return
        if (readOnly) return
        val brush = activeBrush
        val c = color(brush)
        val now = referenceNow()
        val restyled = strokes(sel.page).filter { it.id in sel.ids }.map { s ->
            val seed = if (brush == Brush.GRASS) Random.nextFloat() else s.seed
            Stroke(brush, c, s.width, now, seed, s.points)
        }
        replaceStrokes(sel.page, removing = sel.ids, adding = restyled)
        updateSelection(sel.page, restyled.mapTo(HashSet()) { it.id })
    }

    // MARK: Adjusting a recognized shape

    /** Shows the handles of a shape the held pen just drew. */
    fun startShapeEdit(page: Int, strokeId: Int, shape: EditableShape) {
        if (page !in pages.indices || pages[page].strokes.none { it.id == strokeId }) return
        shapeEdit = ShapeEditState(page, strokeId, shape)
    }

    /** Hides the handles; the shape stays as it is. */
    fun finishShapeEdit() {
        if (shapeEditSnapshot != null) endShapeHandleDrag()
        shapeEdit = null
    }

    fun beginShapeHandleDrag() {
        val e = shapeEdit ?: return
        if (readOnly || e.page !in pages.indices) return
        shapeEditSnapshot = pages[e.page].strokes
    }

    /** Moves a handle (page points) and redraws the shape's stroke in place. */
    fun moveShapeHandle(index: Int, to: Pt, snap: Double): ShapeHandleFeedback? {
        val e = shapeEdit ?: return null
        if (readOnly || e.page !in pages.indices) return null
        val strokes = pages[e.page].strokes
        val i = strokes.indexOfFirst { it.id == e.strokeId }
        if (i < 0) return null
        val move = e.shape.move(index, to, snap)
        val redrawn = restroke(strokes[i], move.shape.path())
        setPage(e.page, strokes.toMutableList().also { it[i] = redrawn })
        shapeEdit = ShapeEditState(e.page, redrawn.id, move.shape)
        onInkChange?.invoke()
        return move.feedback
    }

    /** One undo step for the whole drag. */
    fun endShapeHandleDrag() {
        val before = shapeEditSnapshot ?: return
        shapeEditSnapshot = null
        val e = shapeEdit ?: return
        if (e.page !in pages.indices) return
        val after = pages[e.page].strokes
        if (after.map { it.id } == before.map { it.id }) return
        pushUndo(InkEdit(e.page, before, after))
        markDirty()
    }

    // MARK: The shape tool

    /** Pen paths of the current shape between two page-local points. */
    fun shapePaths(from: Pt, to: Pt): List<List<Vec2>> {
        val paths = ShapeBuilder.paths(shapeKind, from, to, polygonSides)
        return if (shapeDashed) ShapeBuilder.dashed(paths) else paths
    }

    /** Draws the current shape with the last pen picked, its color and width (one undo step). */
    fun addShape(page: Int, from: Pt, to: Pt) {
        if (hypot(to.x - from.x, to.y - from.y) <= 2) return
        val brush = activeBrush
        replaceStrokes(page, removing = emptySet(), adding = PenPaths.strokes(shapePaths(from, to), brush, color(brush), width(brush), referenceNow()))
    }

    // MARK: Undo

    fun undo() {
        val edit = undoStack.removeLastOrNull() ?: return
        restore(edit, before = true)
        redoStack.addLast(edit)
        updateUndoFlags()
        markDirty()
        onInkChange?.invoke()
    }

    fun redo() {
        val edit = redoStack.removeLastOrNull() ?: return
        restore(edit, before = false)
        undoStack.addLast(edit)
        updateUndoFlags()
        markDirty()
        onInkChange?.invoke()
    }

    /** Sets the edit's page, and the pages linked to it, as they were before or after the edit. The
     *  selection goes: the strokes it names were replaced (the iPad keeps a frame round nothing). */
    private fun restore(edit: InkEdit, before: Boolean) {
        clearSelection()
        shapeEditSnapshot = null
        shapeEdit = null
        for (e in listOf(edit) + edit.linked) {
            if (e.page in pages.indices) setPage(e.page, if (before) e.before else e.after)
        }
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
        if (readOnly || isPdf) return
        appendBlankPage()
    }

    /** A notebook always ends in a blank page: the moment ink lands on the last page, a blank one
     *  joins after it, so the next page is there before the pen gets to it (no pulling at the end).
     *  Pages only come this way, they never go: an undo leaves the blank page in place. */
    private fun keepBlankPageAtEnd() {
        if (readOnly || isPdf) return
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

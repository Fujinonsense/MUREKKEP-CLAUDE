package com.murekkep.notebook.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collapse
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.expand
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.murekkep.notebook.R
import com.murekkep.notebook.data.OutlineEntry
import com.murekkep.notebook.data.PdfOutline
import com.murekkep.notebook.render.PageSize
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

// What the page badge opens (Murekkep.swiftpm/PageNavigator.swift): a popover above the badge, 400
// by 580 dp where there is room. The page in view's number is the field: a number typed offers Git
// (the keyboard's Go too), which goes there, and a number past the end goes to the last page. The
// ribbon beside it bookmarks the page in view. Under them three lists: the pages as pictures
// (PageThumbnails.kt, drawn off the main thread; the current page framed in the accent, a
// bookmarked one wearing a red ribbon), the bookmarked pages, and an imported PDF's contents
// (data/PdfOutline.kt). A tap on a page or a heading goes there (EditorState.requestScroll; the
// canvas scrolls) and closes the navigator. The iPad's switch at its foot, Tek sayfa görünümü, is
// left out: the Android canvas has no page-at-a-time view.

/** The navigator's rules, apart from its screen. */
internal object PageNavigation {
    private val NUMBER = Regex("[+-]?[0-9]+")

    /**
     * The page (0-based) for a typed page number (PageNavigator.pageIndex): the number as Swift's Int
     * reads it once spaces and tabs are trimmed; a number past the end is the last page, one before
     * the first the first. Null for no number, or a note without pages.
     */
    fun pageIndex(text: String, count: Int): Int? {
        if (count <= 0) return null
        val trimmed = text.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
        if (!NUMBER.matches(trimmed)) return null
        val n = trimmed.toLongOrNull() ?: return null
        return (n.coerceIn(1L, count.toLong()) - 1).toInt()
    }

    /** A heading of the contents as a row of the list: how deep it lies, and its place in the tree. */
    class OutlineRow(val entry: OutlineEntry, val depth: Int, val path: List<Int>)

    /**
     * The page grid's columns across [width] pixels (the iPad's GridItem(.adaptive(minimum:))): as
     * many at least [min] wide and [gap] apart as fit, one at least; and a column's width, rounded up.
     */
    fun gridColumns(width: Int, min: Int, gap: Int): Pair<Int, Int> {
        val count = max(1, (width + gap) / (min + gap))
        val room = max(0, width - gap * (count - 1))
        return count to (room + count - 1) / count
    }

    /** The rows the contents show (the iPad's List(children:)): the top headings, and under each
     *  heading whose path is in [open] its own, as deep as they are open. */
    fun outlineRows(entries: List<OutlineEntry>, open: Set<List<Int>>): List<OutlineRow> {
        val rows = ArrayList<OutlineRow>()
        fun add(list: List<OutlineEntry>, depth: Int, parent: List<Int>) {
            list.forEachIndexed { i, entry ->
                val path = parent + i
                rows.add(OutlineRow(entry, depth, path))
                val children = entry.children
                if (children != null && path in open) add(children, depth + 1, path)
            }
        }
        add(entries, 0, emptyList())
        return rows
    }
}

/** The navigator's lists; Contents only for an imported PDF. */
private enum class NavigatorTab(val title: Int) {
    PAGES(R.string.pages_tab_pages),
    BOOKMARKS(R.string.pages_tab_bookmarks),
    CONTENTS(R.string.pages_tab_contents),
}

/** The iPad's popover: 400 by 580 points. */
private val NavigatorWidth = 400.dp
private val NavigatorHeight = 580.dp

/** The transparent margin round the navigator, where its shadow is drawn (the popup window is cut at its edge). */
private val NavigatorShadowPad = 44.dp

/** The page grid: its margin, a column's least width and the gaps between columns (the iPad's). */
private val GridPad = 18.dp
private val TileMinWidth = 100.dp
private val TileGap = 14.dp

/** How far a heading of the contents stands in from the one it is under. */
private val OutlineIndent = 20.dp

/**
 * The navigator above the page badge (the composable it is called in), [maxWidth] by [maxHeight]
 * at most; closed by a jump, a tap outside it or Back. TalkBack names it after the badge.
 */
@Composable
internal fun PageNavigator(state: EditorState, maxWidth: Dp, maxHeight: Dp, onDismiss: () -> Unit) {
    val density = LocalDensity.current
    // What stands at the window's sides: a navigation bar in landscape, a cutout.
    val direction = LocalLayoutDirection.current
    val leftInset = WindowInsets.safeDrawing.getLeft(density, direction)
    val rightInset = WindowInsets.safeDrawing.getRight(density, direction)
    val provider = remember(density, leftInset, rightInset) {
        with(density) { AboveAnchor(NavigatorShadowPad.roundToPx(), PopoverGap.roundToPx(), PopoverMargin.roundToPx(), leftInset, rightInset) }
    }
    // Not clipped to the screen: the shadow's margin may run past its edge while the card stays inside.
    Popup(popupPositionProvider = provider, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true, clippingEnabled = false)) {
        Box(Modifier.dismissInMargin(NavigatorShadowPad, onDismiss).padding(NavigatorShadowPad)) {
            NavigatorCard(state, onDismiss, Modifier.width(min(NavigatorWidth, maxWidth)).height(min(NavigatorHeight, maxHeight)))
        }
    }
}

@Composable
private fun NavigatorCard(state: EditorState, close: () -> Unit, modifier: Modifier) {
    val z = Zen.colors
    val context = LocalContext.current
    val title = stringResource(R.string.pages_go_to)
    var number by rememberSaveable { mutableStateOf("") }
    var tab by rememberSaveable { mutableStateOf(NavigatorTab.PAGES) }
    val thumbnails = remember(state) { PageThumbnails(state.pdfFile, state.paper) }
    DisposableEffect(thumbnails) { onDispose { thumbnails.close() } }
    // A PDF's contents, read off the main thread the first time İçindekiler is chosen and kept with
    // the note for the navigator's next openings (the iPad reads them from the PDFKit document its
    // model keeps open); null until they are.
    var outline by remember(state) { mutableStateOf(state.outline) }
    if (state.isPdf && outline == null) {
        LaunchedEffect(state) {
            snapshotFlow { tab }.first { it == NavigatorTab.CONTENTS }
            val read = withContext(Dispatchers.IO) {
                state.pdfFile?.let { file ->
                    PDFBoxResourceLoader.init(context.applicationContext)
                    PdfOutline.read(file)
                } ?: emptyList()
            }
            state.outline = read
            outline = read
        }
    }
    val go = { page: Int ->
        state.requestScroll(page)
        close()
    }
    val tabs = if (state.isPdf) NavigatorTab.entries else listOf(NavigatorTab.PAGES, NavigatorTab.BOOKMARKS)
    Column(
        modifier
            .semantics { paneTitle = title }
            .floating(Zen.popover)
            .clip(RoundedCornerShape(Zen.popover)),
    ) {
        NavigatorHeader(state, number, { number = it }, go, Modifier.padding(start = 18.dp, top = 14.dp, end = 18.dp, bottom = 12.dp))
        ZenSegments(
            options = tabs.map { stringResource(it.title) },
            selected = tabs.indexOf(tab),
            onSelect = { tab = tabs[it] },
            modifier = Modifier.padding(start = 18.dp, end = 18.dp, bottom = 10.dp).fillMaxWidth(),
        )
        HorizontalDivider(color = z.rule)
        Box(Modifier.fillMaxWidth().weight(1f)) {
            when (tab) {
                NavigatorTab.PAGES -> PageGrid(state, List(state.pageCount) { it }, thumbnails, go)
                NavigatorTab.BOOKMARKS -> {
                    val marked = state.bookmarks
                    if (marked.isEmpty()) Hint(stringResource(R.string.pages_no_bookmarks)) else PageGrid(state, marked, thumbnails, go)
                }
                NavigatorTab.CONTENTS -> when (val entries = outline) {
                    null -> Loading()
                    else -> if (entries.isEmpty()) Hint(stringResource(R.string.pages_no_contents)) else OutlineList(entries, go)
                }
            }
        }
    }
}

/** The page in view's number as the field with "/ 12" after it and the hint under them; Git while a
 *  page number is typed; the ribbon. */
@Composable
private fun NavigatorHeader(state: EditorState, number: String, onNumber: (String) -> Unit, go: (Int) -> Unit, modifier: Modifier) {
    val z = Zen.colors
    val typed = PageNavigation.pageIndex(number, state.pageCount)
    val goTyped: () -> Unit = { typed?.let(go) }
    val numberStyle = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum")
    val fieldLabel = stringResource(R.string.pages_go_to)
    // The iPad's spring (response 0.25, damping 0.85) as Git comes and goes.
    val pop = spring<Float>(dampingRatio = 0.85f, stiffness = springStiffness(0.25f))
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        // Git and the ribbon keep their size; the field and its hint take the rest (on a narrow
        // window the hint wraps and the field gives way, "/ 12" staying whole).
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                BasicTextField(
                    value = number,
                    onValueChange = onNumber,
                    textStyle = numberStyle.copy(color = z.ink),
                    singleLine = true,
                    cursorBrush = SolidColor(z.accent),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { goTyped() }),
                    modifier = Modifier.weight(1f, fill = false).width(104.dp).alignByBaseline().semantics { contentDescription = fieldLabel },
                    decorationBox = { field ->
                        Box {
                            // The page in view until a number is typed (the iPad's placeholder).
                            if (number.isEmpty()) Text("${state.currentPage + 1}", style = numberStyle, color = z.muted.copy(alpha = 0.5f))
                            field()
                        }
                    },
                )
                Text(
                    "/ ${state.pageCount}",
                    style = TextStyle(fontSize = 20.sp, fontFeatureSettings = "tnum"),
                    color = z.muted,
                    modifier = Modifier.alignByBaseline(),
                )
            }
            Text(stringResource(R.string.pages_type_number), style = Caption, color = z.muted)
        }
        AnimatedVisibility(typed != null, enter = scaleIn(pop) + fadeIn(pop), exit = scaleOut(pop) + fadeOut(pop)) {
            GoButton(goTyped)
        }
        RibbonButton(state)
    }
}

/** "Git": filled with the accent (the iPad's borderedProminent in its ink blue), a 44 dp target. */
@Composable
private fun GoButton(onClick: () -> Unit) {
    val shape = RoundedCornerShape(Zen.control)
    Box(
        Modifier
            .height(Zen.target)
            .clip(shape)
            .background(Zen.colors.accent)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(stringResource(R.string.pages_go), style = MaterialTheme.typography.labelLarge, color = Color.White, maxLines = 1)
    }
}

/** The ribbon: bookmarks the page in view or takes its bookmark off, red while it has one. */
@Composable
private fun RibbonButton(state: EditorState) {
    val z = Zen.colors
    val view = LocalView.current
    val page = state.currentPage
    val marked = state.isBookmarked(page)
    val label = stringResource(if (marked) R.string.pages_remove_bookmark else R.string.pages_bookmark)
    Box(
        Modifier
            .size(Zen.target)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(role = Role.Button) {
                state.toggleBookmark(page)
                view.bookmarkTick()
            }
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (marked) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
            contentDescription = null,
            tint = if (marked) systemRed(z.dark) else z.muted,
            modifier = Modifier.size(28.dp),
        )
    }
}

/** [pages] as pictures in as many columns of at least 100 dp as fit, the page in view in the middle
 *  as the list opens (the iPad's scrollTo with the centre anchor). Each picture is drawn as wide as
 *  its tile (120 dp at least, as the iPad's), so a wide tile never shows a stretched picture. */
@Composable
private fun PageGrid(state: EditorState, pages: List<Int>, thumbnails: PageThumbnails, go: (Int) -> Unit) {
    val current = state.currentPage
    val grid = rememberLazyGridState(initialFirstVisibleItemIndex = max(0, pages.indexOf(current)))
    LaunchedEffect(grid) {
        val at = pages.indexOf(current)
        if (at < 0) return@LaunchedEffect
        val info = snapshotFlow { grid.layoutInfo }.first { layout -> layout.visibleItemsInfo.any { it.index == at } }
        val item = info.visibleItemsInfo.first { it.index == at }
        val middle = (info.viewportStartOffset + info.viewportEndOffset) / 2
        grid.scrollBy((item.offset.y + item.size.height / 2 - middle).toFloat())
    }
    val layout = state.layout()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val (columns, tileWidth) = with(density) {
            PageNavigation.gridColumns(constraints.maxWidth - 2 * GridPad.roundToPx(), TileMinWidth.roundToPx(), TileGap.roundToPx())
        }
        val pictureWidth = max(tileWidth, with(density) { PageThumbnails.WIDTH.roundToPx() })
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            modifier = Modifier.fillMaxSize(),
            state = grid,
            contentPadding = PaddingValues(GridPad),
            horizontalArrangement = Arrangement.spacedBy(TileGap),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            items(pages, key = { it }) { page ->
                val image = thumbnails.image(page)
                // Drawn as the tile comes into view, and again should its picture have gone or the
                // tile have grown past it.
                val wanted = image == null || image.width < pictureWidth
                LaunchedEffect(page, wanted, pictureWidth) {
                    if (wanted) thumbnails.load(page, state.strokes(page), PageSize(layout.width(page), layout.height(page)), pictureWidth)
                }
                val aspect = max(layout.width(page), 1f) / max(layout.height(page), 1f)
                PageTile(page, image, aspect, page == current, state.isBookmarked(page)) { go(page) }
            }
        }
    }
}

/** A page of the grid: its picture (white until drawn) and its number under it; the current page
 *  framed in the accent with its number bold, a bookmarked one wearing the ribbon. */
@Composable
private fun PageTile(index: Int, image: ImageBitmap?, aspect: Float, current: Boolean, bookmarked: Boolean, onClick: () -> Unit) {
    val z = Zen.colors
    val label = stringResource(R.string.pages_page, index + 1)
    val shape = RoundedCornerShape(3.dp)
    Column(
        Modifier
            .clickable(role = Role.Button, onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = label
                selected = current
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(aspect).tileShadow(current)) {
            if (image != null) {
                Image(image, contentDescription = null, contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize().clip(shape))
            } else {
                Box(Modifier.fillMaxSize().background(Color.White, shape))
            }
            Box(Modifier.fillMaxSize().border(if (current) 2.5.dp else 0.5.dp, if (current) z.accent else Color.Black.copy(alpha = 0.12f), shape))
            if (bookmarked) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(end = 8.dp)
                        .offset(y = (-2).dp)
                        .size(10.dp, 18.dp)
                        .background(systemRed(z.dark), RibbonShape),
                )
            }
        }
        Text(
            "${index + 1}",
            style = Caption.merge(TextStyle(fontFeatureSettings = "tnum")),
            fontWeight = if (current) FontWeight.Bold else FontWeight.Normal,
            color = if (current) z.accent else z.muted,
        )
    }
}

/** The PDF's headings, the ones under a heading behind its disclosure arrow (the iPad's
 *  List(children:)); a heading that points at a page goes there, one that points nowhere is grey. */
@Composable
private fun OutlineList(entries: List<OutlineEntry>, go: (Int) -> Unit) {
    val z = Zen.colors
    var open by remember { mutableStateOf(emptySet<List<Int>>()) }
    val rows = remember(entries, open) { PageNavigation.outlineRows(entries, open) }
    LazyColumn(Modifier.fillMaxSize()) {
        itemsIndexed(rows, key = { _, row -> row.path.joinToString(".") }) { i, row ->
            if (i > 0) HorizontalDivider(Modifier.padding(start = 18.dp), color = z.rule)
            val expanded = row.path in open
            OutlineRowView(row, expanded, onToggle = { open = if (expanded) open.minusElement(row.path) else open.plusElement(row.path) }, go = go)
        }
    }
}

@Composable
private fun OutlineRowView(row: PageNavigation.OutlineRow, expanded: Boolean, onToggle: () -> Unit, go: (Int) -> Unit) {
    val z = Zen.colors
    val entry = row.entry
    val page = entry.page
    val turn = if (LocalLayoutDirection.current == LayoutDirection.Ltr) 90f else -90f
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier
                .weight(1f)
                .heightIn(min = Zen.target)
                .clickable(enabled = page != null, role = Role.Button) { if (page != null) go(page) }
                .padding(start = 18.dp + OutlineIndent * row.depth, end = if (entry.children == null) 18.dp else 4.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                entry.title,
                style = MaterialTheme.typography.bodyLarge,
                color = if (page != null) z.ink else z.muted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (page != null) {
                Text(
                    "${page + 1}",
                    style = MaterialTheme.typography.bodyLarge.merge(TextStyle(fontFeatureSettings = "tnum")),
                    color = z.muted,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }
        if (entry.children != null) {
            // The disclosure arrow: it turns down while the headings under it show.
            Box(
                Modifier
                    .size(Zen.target)
                    .clickable(onClick = onToggle)
                    .semantics {
                        contentDescription = entry.title
                        if (expanded) {
                            collapse {
                                onToggle()
                                true
                            }
                        } else {
                            expand {
                                onToggle()
                                true
                            }
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = z.accent,
                    modifier = Modifier.rotate(if (expanded) turn else 0f),
                )
            }
        }
    }
}

/** A small spinner in the middle of a list still being read (a long PDF's contents). */
@Composable
private fun Loading() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(Modifier.size(28.dp), color = Zen.colors.muted, strokeWidth = 2.5.dp)
    }
}

/** A word in the middle of an empty list (the iPad's hint: callout, secondary, centred). */
@Composable
private fun Hint(text: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodyLarge, color = Zen.colors.muted, textAlign = TextAlign.Center)
    }
}

/** A bookmark ribbon hanging over a page's top edge: a strip with a notch up into its foot. */
private val RibbonShape = GenericShape { size, _ ->
    moveTo(0f, 0f)
    lineTo(size.width, 0f)
    lineTo(size.width, size.height)
    lineTo(size.width / 2f, size.height - size.width * 0.45f)
    lineTo(0f, size.height)
    close()
}

/** The system's red (the iPad's Color.red), the bookmark's. */
private fun systemRed(dark: Boolean): Color = if (dark) Color(0xFFFF453A) else Color(0xFFFF3B30)

/** A page's soft shadow, a point down, deeper under the current page (the iPad's black at 18 %
 *  blurred 6 points against 8 % blurred 2). Android 9 and up draw it as a blurred copy of the page;
 *  older systems get Compose's elevation shadow. */
private fun Modifier.tileShadow(current: Boolean): Modifier {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return shadow(if (current) 3.dp else 1.dp, RoundedCornerShape(3.dp))
    return drawBehind {
        // A blur of b points is a Gaussian of sigma b / 2, which Android's radius reaches as 0.57735 r + 0.5.
        val sigma = (if (current) 6.dp else 2.dp).toPx() / 2f
        val r = 3.dp.toPx()
        drawIntoCanvas { canvas ->
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            paint.color = android.graphics.Color.WHITE
            paint.setShadowLayer(max(sigma - 0.5f, 0.1f) / 0.57735f, 0f, 1.dp.toPx(), Color.Black.copy(alpha = if (current) 0.18f else 0.08f).toArgb())
            canvas.nativeCanvas.drawRoundRect(0f, 0f, size.width, size.height, r, r, paint)
        }
    }
}

/** The light tick of a pick (the iPad's selection haptic as a bookmark is set or taken off). */
private fun View.bookmarkTick() {
    performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK)
}

/** Puts the navigator [gap] above its anchor, centred on it and kept inside the window by [margin]
 *  (the iPad's popover, its arrow on the badge); [pad] is its shadow's margin. The popup's window
 *  runs under the system bars (as ZenMenu found of the navigation bar below a menu), so the card
 *  also stays clear of [leftInset] and [rightInset], a navigation bar or a cutout at a side. */
internal class AboveAnchor(
    private val pad: Int,
    private val gap: Int,
    private val margin: Int,
    private val leftInset: Int,
    private val rightInset: Int,
) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val w = popupContentSize.width - 2 * pad
        val h = popupContentSize.height - 2 * pad
        val left = leftInset + margin
        val x = (anchorBounds.center.x - w / 2).coerceIn(left, max(left, windowSize.width - rightInset - w - margin))
        val y = (anchorBounds.top - gap - h).coerceIn(margin, max(margin, windowSize.height - h - margin))
        return IntOffset(x - pad, y - pad)
    }
}

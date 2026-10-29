package com.murekkep.notebook.ui

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.HeartBroken
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush as Gradient
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.ink.Brush
import com.murekkep.notebook.ink.GrassGenerator
import kotlin.math.min

// Every pen, one shelf at a time (PenPanel on iPad, Murekkep.swiftpm/PenPanel.swift; the shelves in
// PenShelf.kt), like a brush library: each pen in its own row with its whole name and a sample of the
// ink it lays down in the colour it will draw, two rows side by side, five deep before it scrolls. A
// tap picks the pen and closes the panel; the heart beside it makes it a favourite, and favourites
// always stand in the pen bar. The footer tells what the pen in hand does.

private val RowHeight = 76.dp
private val RowSpacing = 10.dp
private const val MaxRows = 5

/** The system's pink (heart.fill on iPad), by day and at night. */
private val SystemPink = Color(0xFFFF2D55)
private val SystemPinkDark = Color(0xFFFF375F)

@Composable
internal fun PenPanel(state: EditorState, onPicked: () -> Unit) {
    val z = Zen.colors
    val favorites = state.favoriteBrushes
    // The shelf picked in this opening; until then the one the panel opens on.
    var picked by remember { mutableStateOf<PenShelf?>(null) }
    val shelf = picked ?: PenShelf.opening(state.penPanelShelf, favorites, state.activeBrush)
    val brushes = shelf.brushes(favorites)
    val tick = rememberSelectionTick()
    Column(Modifier.padding(start = 20.dp, top = 18.dp, end = 20.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(stringResource(R.string.pen_panel_title), style = MaterialTheme.typography.headlineSmall, color = z.ink)
        Text(stringResource(R.string.pen_panel_hint), style = MaterialTheme.typography.bodySmall, color = z.muted)
    }
    val shelfLabel = stringResource(R.string.pen_panel_shelf)
    ZenSegments(
        options = PenShelf.entries.map { stringResource(it.titleRes) },
        selected = shelf.ordinal,
        onSelect = { i ->
            picked = PenShelf.entries[i]
            state.penPanelShelf = PenShelf.entries[i].raw
        },
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 20.dp, end = 20.dp, bottom = 14.dp)
            .semantics { contentDescription = shelfLabel },
    )
    PanelDivider()
    if (brushes.isEmpty()) {
        NoFavorites { picked = PenShelf.WRITING }
    } else {
        val rows = brushes.chunked(2)
        val shown = min(MaxRows, rows.size)
        Column(
            Modifier
                .fillMaxWidth()
                .height(RowHeight * shown + RowSpacing * (shown - 1) + 32.dp)
                .verticalScroll(rememberScrollState(), enabled = rows.size > MaxRows)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(RowSpacing),
        ) {
            for (row in rows) {
                Row(horizontalArrangement = Arrangement.spacedBy(RowSpacing)) {
                    for (brush in row) {
                        PanelPen(state, brush, Modifier.weight(1f)) {
                            val tool = state.tool
                            if (tool !is Tool.Brush || tool.brush != brush) tick()
                            state.tool = Tool.Brush(brush)
                            onPicked()
                        }
                    }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
    PanelDivider()
    val active = state.activeBrush
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 14.dp)
            .heightIn(min = 46.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
    ) {
        Text(active.localizedTitle(), style = MaterialTheme.typography.titleSmall, color = z.ink)
        Text(
            stringResource(active.descriptionRes),
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 16.sp),
            color = z.muted,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun PanelDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Zen.colors.rule.copy(alpha = 0.6f)))
}

/**
 * One pen's row: the pen standing at the left (its lower end sinking into the row), its name and its
 * ink's sample; the picked one on a faint accent with an accent edge. The heart at the top right
 * makes it a favourite; a long press offers the same in a menu.
 */
@Composable
private fun PanelPen(state: EditorState, brush: Brush, modifier: Modifier, onPick: () -> Unit) {
    val z = Zen.colors
    val tool = state.tool
    val selected = tool is Tool.Brush && tool.brush == brush
    val starred = state.isFavorite(brush)
    val ink = state.color(brush)
    val name = brush.localizedTitle()
    val shape = RoundedCornerShape(16.dp)
    // The picked row's faint accent lies on the panel's paper.
    val paper = if (selected) z.accent.copy(alpha = 0.10f).compositeOver(z.paper) else z.paper2
    var menu by remember { mutableStateOf(false) }
    val favoriteLabel = stringResource(if (starred) R.string.remove_favorite else R.string.add_favorite)
    Box(modifier.height(RowHeight)) {
        Row(
            Modifier
                .fillMaxSize()
                .clip(shape)
                .background(paper)
                .border(if (selected) 1.5.dp else 1.dp, if (selected) z.accent else z.rule, shape)
                .combinedClickable(onClick = onPick, onLongClick = { menu = true }, onLongClickLabel = favoriteLabel)
                .semantics {
                    contentDescription = name
                    this.selected = selected
                }
                .padding(start = 10.dp, end = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(34.dp, 60.dp)
                    .clipToBounds()
                    .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                    .drawWithContent {
                        drawContent()
                        // The pen's lower end sinks into the row.
                        drawRect(Gradient.verticalGradient(0.72f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                    },
            ) {
                PenStand(brush, ink.toColor(), selected, Modifier.align(Alignment.TopCenter).wrapContentHeight(Alignment.Top, unbounded = true))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // Room is left on the right for the heart.
                Text(
                    name,
                    style = MaterialTheme.typography.titleSmall,
                    color = z.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(end = 30.dp),
                )
                InkSample(brush, ink, min(state.width(brush), 9f), GrassGenerator.strokeSeed(brush, state.flowerLevel, 0.37f), 28.dp, paper = samplePaper(paper))
            }
        }
        Heart(name, starred, Modifier.align(Alignment.TopEnd)) { state.toggleFavorite(brush) }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(favoriteLabel) },
                trailingIcon = { Icon(if (starred) Icons.Outlined.HeartBroken else Icons.Outlined.FavoriteBorder, contentDescription = null) },
                onClick = {
                    menu = false
                    state.toggleFavorite(brush)
                },
            )
        }
    }
}

/**
 * What a row's ink sample is drawn on. From Android 10 a clear bitmap: the sample lies straight on
 * the row, as the iPad's, and the highlighter's multiply leaves its ink as it is there (the iPad's
 * sample does not multiply; on the row's colour it would sink into a dark row at night). Before,
 * Porter-Duff's multiply wipes ink off a clear bitmap, so the row's colour is painted in.
 */
private fun samplePaper(row: Color): Color = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Color.Transparent else row

/** The heart beside a pen: one tap makes it a favourite or takes it away, without picking it. */
@Composable
private fun Heart(name: String, starred: Boolean, modifier: Modifier, onToggle: () -> Unit) {
    val z = Zen.colors
    val tick = rememberSelectionTick()
    val label = stringResource(if (starred) R.string.pen_remove_favorite else R.string.pen_add_favorite, name)
    Box(
        modifier
            .size(40.dp)
            .clickable {
                onToggle()
                tick()
            }
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (starred) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
            contentDescription = null,
            tint = if (starred) (if (z.dark) SystemPinkDark else SystemPink) else z.muted.copy(alpha = 0.55f),
            modifier = Modifier.size(18.dp),
        )
    }
}

/** The favourites' shelf with none yet: a heart, what a heart does, and the way to the writing pens. */
@Composable
private fun NoFavorites(onBrowse: () -> Unit) {
    val z = Zen.colors
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Outlined.FavoriteBorder, contentDescription = null, tint = z.muted, modifier = Modifier.size(28.dp))
        Text(stringResource(R.string.no_favorite_pens), style = MaterialTheme.typography.titleMedium, color = z.ink)
        Text(
            stringResource(R.string.no_favorite_pens_hint),
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp),
            color = z.muted,
            textAlign = TextAlign.Center,
        )
        Text(
            stringResource(R.string.browse_pens),
            style = MaterialTheme.typography.titleSmall,
            color = z.accent,
            modifier = Modifier
                .padding(top = 2.dp)
                .clip(RoundedCornerShape(Zen.control))
                .clickable(onClick = onBrowse)
                .padding(horizontal = 8.dp, vertical = 6.dp),
        )
    }
}

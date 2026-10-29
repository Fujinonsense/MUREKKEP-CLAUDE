@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.GridOn
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R
import com.murekkep.notebook.data.PaperStyle
import com.murekkep.notebook.export.PaperDrawer

// "Yeni defter" (TemplateGallery on iPad, opened by "Yeni not"): the page templates the Android
// canvas draws, Temel's first four (Düz, Çizgili, Kareli, Noktalı), each an A4 page drawn by the
// same code as the real pages, with its glyph and name; a tap starts a notebook on it.

/** The templates a new notebook can start on: the four the paper shader draws. */
val NewNotebookTemplates = listOf(PaperStyle.PLAIN, PaperStyle.LINED, PaperStyle.GRID, PaperStyle.DOTTED)

/** The paper shader's style for a template (PaperStyle.shaderIndex on iPad): 0 plain, 1 lined,
 *  2 grid, 3 dotted. Every other template is drawn lined, as the export draws it. */
val PaperStyle.shaderIndex: Int
    get() = when (PaperDrawer.exported(this)) {
        PaperStyle.PLAIN -> 0
        PaperStyle.GRID -> 2
        PaperStyle.DOTTED -> 3
        else -> 1
    }

@Composable
fun TemplateSheet(onDismiss: () -> Unit, onPick: (PaperStyle) -> Unit) {
    val z = Zen.colors
    ZenSheet(
        title = stringResource(R.string.new_notebook_title),
        onDismiss = onDismiss,
        leading = { SheetButton(stringResource(R.string.cancel), onClick = onDismiss) },
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.template_basic), style = MaterialTheme.typography.headlineSmall.copy(fontSize = 20.sp), color = z.ink)
            // Columns of 118 to 168 dp, 18 apart (the gallery's adaptive grid).
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val cell = LibraryRules.adaptiveColumns(maxWidth.value, 118f, 168f, 18f).second
                FlowRow(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    for (style in NewNotebookTemplates) {
                        TemplateTile(style, (cell - 0.5f).dp) { onPick(style) }
                    }
                }
            }
        }
    }
}

/** A template: its page in a hairline with a soft shadow, its glyph and name under it. */
@Composable
private fun TemplateTile(style: PaperStyle, width: Dp, onClick: () -> Unit) {
    val z = Zen.colors
    val title = stringResource(style.titleRes)
    val shape = RoundedCornerShape(Zen.control)
    Column(
        Modifier
            .width(width)
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = title },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        PaperPage(
            style,
            Modifier
                .fillMaxWidth()
                .aspectRatio(EditorState.A4_WIDTH / EditorState.A4_HEIGHT)
                .shadow(4.dp, shape)
                .clip(shape)
                .border(1.dp, z.rule, shape),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(style.glyph, contentDescription = null, tint = z.ink, modifier = Modifier.size(14.dp))
            Text(
                title,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = z.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * A page of [style] as the real pages are drawn (PaperDrawer): white with its lines, grid or dots,
 * as wide as the space and centred in its height (a cover's 3:4 cuts the A4 page as the cover
 * picture is cut).
 */
@Composable
internal fun PaperPage(style: PaperStyle, modifier: Modifier) {
    Canvas(modifier.background(Color.White)) {
        drawIntoCanvas { canvas ->
            val native = canvas.nativeCanvas
            val k = size.width / EditorState.A4_WIDTH
            native.save()
            native.clipRect(0f, 0f, size.width, size.height)
            native.translate(0f, (size.height - EditorState.A4_HEIGHT * k) / 2f)
            native.scale(k, k)
            PaperDrawer.draw(style, EditorState.A4_WIDTH, EditorState.A4_HEIGHT, native)
            native.restore()
        }
    }
}

private val PaperStyle.titleRes: Int
    get() = when (PaperDrawer.exported(this)) {
        PaperStyle.PLAIN -> R.string.template_plain
        PaperStyle.GRID -> R.string.template_grid
        PaperStyle.DOTTED -> R.string.template_dotted
        else -> R.string.template_lined
    }

/** The iPad's symbols: doc, line.3.horizontal, squareshape.split.3x3, circle.grid.3x3. */
private val PaperStyle.glyph: ImageVector
    get() = when (PaperDrawer.exported(this)) {
        PaperStyle.PLAIN -> Icons.AutoMirrored.Outlined.InsertDriveFile
        PaperStyle.GRID -> Icons.Outlined.GridOn
        PaperStyle.DOTTED -> Icons.Outlined.Apps
        else -> Icons.Outlined.Menu
    }

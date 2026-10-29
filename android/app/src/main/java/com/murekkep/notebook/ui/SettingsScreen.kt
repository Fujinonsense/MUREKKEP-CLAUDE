@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.murekkep.notebook.R

// Ayarlar (the spec's "Ayarlar. Gruplu liste; Görünüm › Tema seçici", SettingsView on iPad): a
// sheet over the library with "Bitti", holding a grouped list on paper-3. Görünüm is a card with a
// "Tema" row naming the theme in force, then the themes' tiles, black and white first; its footer
// explains them. While Pro is locked (the Play build, until Play Billing) a Pro tile wears the Pro
// badge and a tap on it says Pro is coming.

@Composable
fun SettingsScreen(theme: AppTheme, onTheme: (AppTheme) -> Unit, onDone: () -> Unit) {
    var proSoon by remember { mutableStateOf(false) }
    ZenSheet(
        title = stringResource(R.string.settings),
        ground = Zen.colors.paper3,
        onDismiss = onDone,
        trailing = { SheetButton(stringResource(R.string.done), bold = true, onClick = onDone) },
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                .padding(horizontal = 20.dp, vertical = 24.dp),
        ) {
            val shown = theme.shown
            Group(
                header = stringResource(R.string.settings_appearance),
                footer = stringResource(if (Pro.UNLOCKED) R.string.settings_theme_footer else R.string.settings_theme_footer_store),
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.settings_theme), style = MaterialTheme.typography.bodyLarge, color = Zen.colors.ink, modifier = Modifier.weight(1f))
                        Text(stringResource(shown.titleRes), style = MaterialTheme.typography.bodyLarge, color = Zen.colors.muted)
                    }
                    ThemeTiles(shown) { option -> if (option.locked) proSoon = true else onTheme(option) }
                }
            }
        }
    }
    if (proSoon) {
        AlertDialog(
            onDismissRequest = { proSoon = false },
            title = { Text(stringResource(R.string.pro_soon_title)) },
            text = { Text(stringResource(R.string.pro_soon_message)) },
            confirmButton = { TextButton(onClick = { proSoon = false }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/** A group of the list: its header in muted text, its card of paper in a hairline, its footer under the card. */
@Composable
private fun Group(header: String, footer: String?, content: @Composable () -> Unit) {
    val z = Zen.colors
    val shape = RoundedCornerShape(12.dp)
    Text(
        header,
        style = MaterialTheme.typography.bodySmall,
        color = z.muted,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
    )
    Box(Modifier.fillMaxWidth().clip(shape).background(z.paper).border(1.dp, z.rule, shape)) {
        content()
    }
    if (footer != null) {
        Text(
            footer,
            style = MaterialTheme.typography.bodySmall,
            color = z.muted,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
        )
    }
}

/** The themes' tiles in the picker's adaptive columns: 112 to 150 dp wide, 14 apart, rows 16 apart. */
@Composable
private fun ThemeTiles(shown: AppTheme, onPick: (AppTheme) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val cell = LibraryRules.adaptiveColumns(maxWidth.value, 112f, 150f, 14f).second
        FlowRow(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            for (option in AppTheme.entries) {
                ThemeTile(option, chosen = option == shown, width = (cell - 0.5f).dp, onClick = { onPick(option) })
            }
        }
    }
}

/** A theme's preview, 84 dp tall, its name under it: the chosen one in a ring of the accent with a
 *  check, a locked one with the Pro badge. */
@Composable
private fun ThemeTile(option: AppTheme, chosen: Boolean, width: Dp, onClick: () -> Unit) {
    val z = Zen.colors
    val title = stringResource(option.titleRes)
    val pro = stringResource(R.string.in_pro)
    val shape = RoundedCornerShape(Zen.control)
    Column(
        Modifier
            .width(width)
            .clip(shape)
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = if (option.locked) "$title, $pro" else title
                this.selected = chosen
            },
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(84.dp)
                .clip(shape)
                .border(if (chosen) 2.dp else 1.dp, if (chosen) z.accent else z.rule, shape),
        ) {
            ThemePreview(option, Modifier.fillMaxSize())
            when {
                option.locked -> ProBadge(Modifier.align(Alignment.TopEnd).padding(7.dp))
                chosen -> Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(18.dp)
                        .background(z.accent, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(13.dp))
                }
            }
        }
        Text(
            title,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = if (chosen) FontWeight.SemiBold else FontWeight.Normal,
            color = if (chosen) z.ink else z.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** The small mark on Pro-only themes: "Pro" in white on the accent. */
@Composable
private fun ProBadge(modifier: Modifier) {
    Box(modifier.background(Zen.colors.accent, CircleShape).padding(horizontal = 6.dp, vertical = 2.5.dp)) {
        Text(stringResource(R.string.pro), style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp), fontWeight = FontWeight.Bold, color = Color.White)
    }
}

/** A tile's picture: plain paper for black and white, the ruled lines close together, a picture
 *  theme's thumbnail (without its wash). */
@Composable
private fun ThemePreview(option: AppTheme, modifier: Modifier) {
    when {
        option.thumb != null -> Image(painterResource(option.thumb), contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier)
        option == AppTheme.RULED -> ThemeRuledPaper(spacing = 11.dp, top = 9.dp, modifier = modifier)
        else -> Box(modifier.background(Zen.colors.paper))
    }
}

/** The Defter theme's paper (RuledPaper in Theme.swift): paper with faint lines [spacing] apart from
 *  [top] down, black at 8 % (white at 7 % at night), 0.7 dp wide. */
@Composable
fun ThemeRuledPaper(spacing: Dp, top: Dp, modifier: Modifier) {
    val z = Zen.colors
    val line = if (z.dark) Color.White.copy(alpha = 0.07f) else Color.Black.copy(alpha = 0.08f)
    Canvas(modifier.background(z.paper)) {
        val step = spacing.toPx()
        val width = 0.7.dp.toPx()
        var y = top.toPx()
        while (y < size.height) {
            drawLine(line, Offset(0f, y), Offset(size.width, y), strokeWidth = width)
            y += step
        }
    }
}

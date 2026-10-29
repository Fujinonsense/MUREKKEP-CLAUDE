@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.murekkep.notebook.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.murekkep.notebook.R

// Ayarlar (the spec's "Ayarlar. Gruplu liste; Görünüm › Tema seçici"): Görünüm › Tema, "Siyah
// beyaz" first (free, the default), then the Pro themes as preview tiles. There is no Play
// Billing yet, so a Pro tile wears "Pro" and a tap on it says Pro is coming.

@Composable
fun SettingsScreen(theme: AppTheme, onTheme: (AppTheme) -> Unit, onBack: () -> Unit) {
    val z = Zen.colors
    var proSoon by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(z.paper)) {
        SettingsTopBar(onBack)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                .padding(horizontal = 40.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Text(stringResource(R.string.settings_appearance), style = MaterialTheme.typography.titleLarge, color = z.ink)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.settings_theme), style = MaterialTheme.typography.bodySmall, color = z.muted)
                Text(stringResource(R.string.settings_theme_hint), style = MaterialTheme.typography.bodyMedium, color = z.ink2, modifier = Modifier.widthIn(max = 560.dp))
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                for (option in AppTheme.entries) {
                    ThemeTile(
                        option = option,
                        selected = option == theme,
                        onClick = { if (option.isPro && !Pro.UNLOCKED) proSoon = true else onTheme(option) },
                    )
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

/** "‹ Notlar" and the title, on paper-2 over a hairline, as the editor's bar. */
@Composable
private fun SettingsTopBar(onBack: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .fillMaxWidth()
            .background(z.paper2)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .height(52.dp),
    ) {
        Row(
            Modifier
                .align(Alignment.CenterStart)
                .padding(start = 8.dp)
                .height(Zen.target)
                .clip(RoundedCornerShape(Zen.control))
                .clickable(onClick = onBack)
                .padding(start = 6.dp, end = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = null, tint = z.ink2, modifier = Modifier.size(24.dp))
            Text(stringResource(R.string.notes), style = MaterialTheme.typography.bodyLarge, color = z.ink2)
        }
        Text(stringResource(R.string.settings), style = MaterialTheme.typography.titleSmall, color = z.ink, modifier = Modifier.align(Alignment.Center))
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(1.dp).background(z.rule))
    }
}

/** A theme's preview, 148 dp wide: its picture (or a drawing of black and white, or ruled paper),
 *  its name, and "Pro" or "Ücretsiz" under it; the chosen one in a ring of the accent. */
@Composable
private fun ThemeTile(option: AppTheme, selected: Boolean, onClick: () -> Unit) {
    val z = Zen.colors
    val title = stringResource(option.titleRes)
    val badge = stringResource(if (option.isPro) R.string.pro else R.string.theme_free)
    Column(
        Modifier
            .width(148.dp)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = "$title, $badge"
                this.selected = selected
            },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(4f / 3f)
                .clip(RoundedCornerShape(Zen.control))
                .border(if (selected) 2.dp else 1.dp, if (selected) z.accent else z.rule, RoundedCornerShape(Zen.control)),
        ) {
            when {
                option.thumb != null -> Image(
                    painterResource(option.thumb), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
                )
                option == AppTheme.RULED -> RuledPaper(Modifier.fillMaxSize())
                option == AppTheme.BLACK_WHITE -> BlackAndWhitePreview(Modifier.fillMaxSize())
                else -> Box(Modifier.fillMaxSize().background(z.paper2))
            }
        }
        Column(Modifier.padding(horizontal = 4.dp)) {
            Text(title, style = MaterialTheme.typography.labelMedium, color = z.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(badge, style = MaterialTheme.typography.labelSmall, color = z.muted)
        }
        Spacer(Modifier.height(0.dp))
    }
}

/** Black and white: a white page on paper-3 with one stroke of ink. */
@Composable
private fun BlackAndWhitePreview(modifier: Modifier) {
    val z = Zen.colors
    Canvas(modifier.background(z.paper3)) {
        val w = size.width
        val h = size.height
        val page = Size(w * 0.56f, h * 0.84f)
        val left = (w - page.width) / 2f
        val top = h * 0.16f
        drawRect(Color.White, Offset(left, top), page)
        drawRect(z.rule, Offset(left, top), page, style = Stroke(width = 1.dp.toPx()))
        val stroke = Path().apply {
            moveTo(left + page.width * 0.18f, top + page.height * 0.42f)
            cubicTo(left + page.width * 0.35f, top + page.height * 0.2f, left + page.width * 0.5f, top + page.height * 0.6f, left + page.width * 0.82f, top + page.height * 0.36f)
        }
        drawPath(stroke, Color(0xFF141414), style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
    }
}

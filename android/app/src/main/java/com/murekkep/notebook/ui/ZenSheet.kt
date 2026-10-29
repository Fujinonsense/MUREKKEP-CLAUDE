package com.murekkep.notebook.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

// A sheet over the screen, as the iPad presents Ayarlar and "Yeni defter" (.sheet), in a window of
// its own, so touches, the keyboard's focus and TalkBack stay in it: from 600 dp a card with the
// pop-up's corners, up to 700 dp wide and 94 % of the height, over the dimmed screen, so the
// library stays in view behind it; narrower, the whole screen, drawn under the bars. Its bar
// carries the title in the middle and the sheet's buttons ("Vazgeç", "Bitti") at its ends; Back
// closes it.

/** From this window width a sheet is a card over the screen. */
private const val SHEET_CARD_WIDTH_DP = 600

/** A sheet titled [title] on [ground] (Ayarlar's grouped list on paper-3, the templates on paper). */
@Composable
fun ZenSheet(
    title: String,
    ground: Color,
    onDismiss: () -> Unit,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    if (LocalConfiguration.current.screenWidthDp >= SHEET_CARD_WIDTH_DP) {
        Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Column(
                Modifier
                    .widthIn(max = 700.dp)
                    .fillMaxWidth()
                    .fillMaxHeight(0.94f)
                    .clip(RoundedCornerShape(Zen.popover))
                    .background(ground),
            ) {
                SheetBar(title, leading, trailing, Modifier)
                content()
            }
        }
    } else {
        Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            DialogBars(Zen.colors.dark)
            Column(Modifier.fillMaxSize().background(ground)) {
                SheetBar(title, leading, trailing, Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)))
                content()
            }
        }
    }
}

/** The sheet's bar: the title in the middle, its buttons at the ends, on paper-2 over a hairline. */
@Composable
private fun SheetBar(title: String, leading: (@Composable () -> Unit)?, trailing: (@Composable () -> Unit)?, insets: Modifier) {
    val z = Zen.colors
    Box(Modifier.fillMaxWidth().background(z.paper2).then(insets).height(52.dp)) {
        if (leading != null) Box(Modifier.align(Alignment.CenterStart).padding(start = 8.dp)) { leading() }
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = z.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.Center).fillMaxWidth(0.5f),
            textAlign = TextAlign.Center,
        )
        if (trailing != null) Box(Modifier.align(Alignment.CenterEnd).padding(end = 8.dp)) { trailing() }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(1.dp).background(z.rule))
    }
}

/** A sheet's text button in the accent: "Bitti" in semibold (the confirming one), "Vazgeç" plain. */
@Composable
fun SheetButton(label: String, bold: Boolean = false, onClick: () -> Unit) {
    val z = Zen.colors
    Box(
        Modifier
            .height(Zen.target)
            .clip(RoundedCornerShape(Zen.control))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal,
            color = z.accent,
            maxLines = 1,
        )
    }
}

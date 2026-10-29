package com.murekkep.notebook.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlin.math.max

// The spec's menus: a floating surface like the bar's popovers (paper, a hairline of rule, the
// float shadow, the pop-up's 16 dp corners), its items in body text as the iPad's system menus set
// them. It takes the place of Material's DropdownMenu with the same parameters, and holds the
// same DropdownMenuItems.

/** The transparent margin round a menu, where its shadow is drawn (the popup window is cut at its edge). */
private val MenuShadowPad = 44.dp

/**
 * A menu under its anchor (the composable it is called in), starting at the anchor's start, or
 * ending at its end where there is no room; above the anchor where there is no room below.
 * Closed by a tap outside or Back.
 */
@Composable
fun ZenMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    if (!expanded) return
    val density = LocalDensity.current
    val provider = remember(density) {
        with(density) { BelowAnchor(MenuShadowPad.roundToPx(), 4.dp.roundToPx(), 8.dp.roundToPx()) }
    }
    // Not clipped to the screen, so the shadow's margin may run past its edge while the menu stays inside.
    Popup(popupPositionProvider = provider, onDismissRequest = onDismissRequest, properties = PopupProperties(focusable = true, clippingEnabled = false)) {
        Box(Modifier.padding(MenuShadowPad)) {
            val type = MaterialTheme.typography
            // The items' labels in body text, not Material's semibold label style.
            MaterialTheme(typography = type.copy(labelLarge = type.bodyLarge)) {
                Column(
                    modifier
                        .width(IntrinsicSize.Max)
                        .floating(Zen.popover)
                        .clip(RoundedCornerShape(Zen.popover))
                        .padding(vertical = 6.dp)
                        .verticalScroll(rememberScrollState()),
                    content = content,
                )
            }
        }
    }
}

/** Places a menu [gap] under its anchor, kept inside the window by [margin]; [pad] is its shadow's margin. */
private class BelowAnchor(private val pad: Int, private val gap: Int, private val margin: Int) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val w = popupContentSize.width - 2 * pad
        val h = popupContentSize.height - 2 * pad
        val ltr = layoutDirection == LayoutDirection.Ltr
        val start = if (ltr) anchorBounds.left else anchorBounds.right - w
        val end = if (ltr) anchorBounds.right - w else anchorBounds.left
        val fitsAtStart = start >= margin && start + w <= windowSize.width - margin
        val x = (if (fitsAtStart) start else end).coerceIn(margin, max(margin, windowSize.width - w - margin))
        val below = anchorBounds.bottom + gap
        val y = if (below + h <= windowSize.height - margin) below else max(margin, anchorBounds.top - gap - h)
        return IntOffset(x - pad, y - pad)
    }
}

package com.murekkep.notebook.ui

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
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
 * ending at its end where there is no room ([alignEnd] ends it at the anchor's end, as an iOS menu
 * picker opens under its value); above the anchor where there is no room below, and always inside
 * the window, clear of the navigation bar. Closed by a tap outside it (its shadow's margin
 * included) or Back.
 */
@Composable
fun ZenMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    alignEnd: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    if (!expanded) return
    val density = LocalDensity.current
    val bottomInset = WindowInsets.safeDrawing.getBottom(density)
    val provider = remember(density, bottomInset, alignEnd) {
        with(density) { BelowAnchor(MenuShadowPad.roundToPx(), 4.dp.roundToPx(), 8.dp.roundToPx(), bottomInset, alignEnd) }
    }
    // Not clipped to the screen, so the shadow's margin may run past its edge while the menu stays inside.
    Popup(popupPositionProvider = provider, onDismissRequest = onDismissRequest, properties = PopupProperties(focusable = true, clippingEnabled = false)) {
        Box(Modifier.dismissInMargin(MenuShadowPad, onDismissRequest).padding(MenuShadowPad)) {
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

/**
 * Closes a popup on a touch in the [margin] round its content: the popup's window holds that
 * margin for the shadow, so the system does not count a touch there as outside, and nothing under
 * the popup would take it either. Touches on the content go on to it.
 */
fun Modifier.dismissInMargin(margin: Dp, onDismiss: () -> Unit): Modifier = pointerInput(margin, onDismiss) {
    awaitEachGesture {
        val down = awaitFirstDown(pass = PointerEventPass.Initial)
        val m = margin.toPx()
        val p = down.position
        if (p.x < m || p.y < m || p.x >= size.width - m || p.y >= size.height - m) {
            down.consume()
            onDismiss()
        }
    }
}

/** Places a menu [gap] under its anchor, kept inside the window by [margin]; [pad] is its shadow's margin. */
private class BelowAnchor(
    private val pad: Int,
    private val gap: Int,
    private val margin: Int,
    /** The navigation bar's height: the menu never lies under it. */
    private val bottomInset: Int,
    private val alignEnd: Boolean,
) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val w = popupContentSize.width - 2 * pad
        val h = popupContentSize.height - 2 * pad
        val ltr = layoutDirection == LayoutDirection.Ltr
        val start = if (ltr) anchorBounds.left else anchorBounds.right - w
        val end = if (ltr) anchorBounds.right - w else anchorBounds.left
        val fitsAtStart = start >= margin && start + w <= windowSize.width - margin
        val fitsAtEnd = end >= margin && end + w <= windowSize.width - margin
        val x = (if (alignEnd && fitsAtEnd || !fitsAtStart) end else start).coerceIn(margin, max(margin, windowSize.width - w - margin))
        // Under the anchor, else over it; either way inside the window and above the navigation bar
        // (an anchor near or past the bottom edge would otherwise put the menu's last items under it).
        val bottom = windowSize.height - bottomInset - margin
        val below = anchorBounds.bottom + gap
        val y = (if (below + h <= bottom) below else anchorBounds.top - gap - h).coerceIn(margin, max(margin, bottom - h))
        return IntOffset(x - pad, y - pad)
    }
}

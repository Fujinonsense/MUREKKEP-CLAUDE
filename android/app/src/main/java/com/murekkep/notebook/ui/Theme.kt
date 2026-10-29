package com.murekkep.notebook.ui

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The zen look (docs/superpowers/specs/2026-10-29-zen-arayuz-design.md): paper and ink, the greys
// at zero chroma, the brand's ink blue only where something is selected or focused. The page is
// always paper, the chrome around it goes to graphite at night. Shadows only under what floats
// (the pen bar, popovers, menus); resting surfaces have none and no glass. The system font
// everywhere, headings bold and tight, labels in sentence case.

/** The tokens of the spec's table, one set for the light look and one for the dark. */
@Immutable
class ZenColors(
    /** Surfaces: the pen bar, popovers, cards. */
    val paper: Color,
    /** Bars and the sidebar. */
    val paper2: Color,
    /** The ground under the page and a selected row. */
    val paper3: Color,
    /** Headings and text. */
    val ink: Color,
    /** Body text and icons. */
    val ink2: Color,
    /** Secondary text. */
    val muted: Color,
    /** Thin edges. */
    val rule: Color,
    /** Selection, focus, the primary state. */
    val accent: Color,
    /** Text written over the page itself, which stays white at night. */
    val onPage: Color,
    val dark: Boolean,
    /** A Pro theme is on: the pens get the iPad's realistic bodies (ToolArt). */
    val proTheme: Boolean = false,
) {
    /** The ground's colour for the GL canvas, as rgb in 0..1. */
    val groundRgb: FloatArray get() = floatArrayOf(paper3.red, paper3.green, paper3.blue)
}

val ZenLight = ZenColors(
    paper = Color(0xFFFDFDFC),
    paper2 = Color(0xFFF6F6F4),
    paper3 = Color(0xFFEDEDEA),
    ink = Color(0xFF141414),
    ink2 = Color(0xFF2E2E2E),
    muted = Color(0xFF565656),
    rule = Color(0xFFDFDFDC),
    accent = Color(0xFF2457D6),
    onPage = Color(0xFF565656),
    dark = false,
)

val ZenDark = ZenColors(
    paper = Color(0xFF2A2B2E),
    paper2 = Color(0xFF202124),
    paper3 = Color(0xFF151618),
    ink = Color(0xFFF2F3F5),
    ink2 = Color(0xFFD7D9DC),
    muted = Color(0xFFA9ACB1),
    rule = Color(0xFF43454A),
    accent = Color(0xFF4D7BEA),
    onPage = Color(0xFF565656),
    dark = true,
)

val LocalZen = staticCompositionLocalOf { ZenLight }

/** The tokens of the theme in force. */
object Zen {
    val colors: ZenColors
        @Composable @ReadOnlyComposable get() = LocalZen.current

    /** Corners: controls 10, popovers 16, the floating bar 18. */
    val control = 10.dp
    val popover = 16.dp
    val bar = 18.dp

    /** Buttons and tap targets are 44 dp (the spec's size), 8 dp apart. */
    val target = 44.dp
}

/** Material's roles filled from the tokens, so the Material components in the app wear the same look. */
private fun materialScheme(z: ZenColors): ColorScheme {
    val accentSoft = if (z.dark) Color(0xFF27375E) else Color(0xFFE4EAF9)
    val onAccentSoft = if (z.dark) Color(0xFFC9D6F7) else Color(0xFF1B3C8F)
    val base = if (z.dark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = z.accent,
        onPrimary = Color.White,
        primaryContainer = accentSoft,
        onPrimaryContainer = onAccentSoft,
        secondary = z.ink2,
        onSecondary = z.paper,
        secondaryContainer = z.paper3,
        onSecondaryContainer = z.ink,
        tertiary = z.muted,
        onTertiary = z.paper,
        tertiaryContainer = z.paper2,
        onTertiaryContainer = z.ink,
        background = z.paper3,
        onBackground = z.ink,
        surface = z.paper,
        onSurface = z.ink,
        surfaceVariant = z.paper3,
        onSurfaceVariant = z.ink2,
        surfaceTint = Color.Transparent,
        surfaceBright = z.paper,
        surfaceDim = z.paper3,
        surfaceContainerLowest = z.paper,
        surfaceContainerLow = z.paper2,
        // Menus and dialogs float, so they are paper (the spec's surfaces).
        surfaceContainer = z.paper,
        surfaceContainerHigh = z.paper,
        surfaceContainerHighest = z.paper3,
        inverseSurface = z.ink,
        inverseOnSurface = z.paper,
        inversePrimary = if (z.dark) z.accent else Color(0xFFB3C4F2),
        outline = z.rule,
        outlineVariant = z.rule,
        scrim = Color.Black,
    )
}

/** The system font at Material's roles: headings bold and tight, everything else plain. */
private val ZenTypography = Typography(
    headlineLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 34.sp, lineHeight = 38.sp, letterSpacing = (-0.9).sp),
    headlineMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 32.sp, letterSpacing = (-0.6).sp),
    headlineSmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 22.sp, lineHeight = 26.sp, letterSpacing = (-0.4).sp),
    titleLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, lineHeight = 28.sp, letterSpacing = (-0.3).sp),
    titleMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp, letterSpacing = 0.sp),
    titleSmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, lineHeight = 20.sp, letterSpacing = 0.sp),
    bodyLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 22.sp, letterSpacing = 0.sp),
    bodyMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp, letterSpacing = 0.sp),
    bodySmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp, letterSpacing = 0.sp),
    labelLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, lineHeight = 20.sp, letterSpacing = 0.sp),
    labelMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 18.sp, letterSpacing = 0.sp),
    labelSmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp, letterSpacing = 0.sp),
)

private val ZenShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(Zen.control),
    medium = RoundedCornerShape(Zen.popover),
    large = RoundedCornerShape(Zen.bar),
    // Dialogs, which take a pop-up's 16 dp corners.
    extraLarge = RoundedCornerShape(Zen.popover),
)

/**
 * The app's theme, from the choice in Ayarlar › Görünüm: the system's light or dark look in every
 * theme, the pens' realistic bodies in a Pro theme. Only the library takes a picture's own look
 * ([LibraryLook]). The accent stays the brand's ink blue in every theme, as on the iPad.
 */
@Composable
fun MurekkepTheme(theme: AppTheme = AppTheme.BLACK_WHITE, darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppTheme provides theme) {
        ZenLook(zenColors(theme, darkTheme), content)
    }
}

/**
 * The library's sidebar and notes in their picture's look ([AppTheme.libraryDark]), so their text
 * reads on it. The editor, Ayarlar, the sheets and the dialogs stay outside and keep the system's
 * look, as the iPad sets the picture's look on the library's content only.
 */
@Composable
fun LibraryLook(content: @Composable () -> Unit) {
    val theme = LocalAppTheme.current
    val zen = zenColors(theme, theme.libraryDark(Zen.colors.dark))
    ZenLook(zen) {
        // Text and icons in ink, as the screen's surface gives the rest of the app.
        CompositionLocalProvider(LocalContentColor provides zen.ink, content = content)
    }
}

/** The tokens of [theme] in the light or the dark look: in a Pro theme the pens get their realistic bodies. */
private fun zenColors(theme: AppTheme, dark: Boolean): ZenColors {
    val base = if (dark) ZenDark else ZenLight
    return if (theme.shown == AppTheme.BLACK_WHITE) base else ZenColors(
        base.paper, base.paper2, base.paper3, base.ink, base.ink2, base.muted, base.rule,
        base.accent, base.onPage, base.dark, proTheme = true,
    )
}

/** The tokens and Material's roles filled from them. */
@Composable
private fun ZenLook(zen: ZenColors, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalZen provides zen) {
        MaterialTheme(
            colorScheme = materialScheme(zen),
            typography = ZenTypography,
            shapes = ZenShapes,
            content = content,
        )
    }
}

/**
 * The shadow of something that floats (the spec's `0 12 32 black 12% + 0 1 2 black 8%`, deeper at
 * night). Android 9 and up draw it as a blurred copy of the rounded box under the content; older
 * systems get Compose's elevation shadow.
 */
fun Modifier.floatShadow(corner: Dp, surface: Color, dark: Boolean): Modifier {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return shadow(12.dp, RoundedCornerShape(corner))
    val farAlpha = if (dark) 0.45f else 0.12f
    val nearAlpha = if (dark) 0.30f else 0.08f
    return drawBehind {
        val r = corner.toPx()
        drawIntoCanvas { canvas ->
            // The box is drawn in its own surface colour (the shadow is cast from what is drawn), once per shadow.
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            paint.color = surface.toArgb()
            paint.setShadowLayer(blurRadius(16.dp.toPx()), 0f, 12.dp.toPx(), Color.Black.copy(alpha = farAlpha).toArgb())
            canvas.nativeCanvas.drawRoundRect(0f, 0f, size.width, size.height, r, r, paint)
            paint.setShadowLayer(blurRadius(1.dp.toPx()), 0f, 1.dp.toPx(), Color.Black.copy(alpha = nearAlpha).toArgb())
            canvas.nativeCanvas.drawRoundRect(0f, 0f, size.width, size.height, r, r, paint)
        }
    }
}

/** Android's blur takes a radius it turns into sigma = 0.57735 radius + 0.5; this is the way back from a CSS blur's sigma. */
private fun blurRadius(sigma: Float): Float = if (sigma > 0.5f) (sigma - 0.5f) / 0.57735f else 0f

/** A floating surface: paper, a hairline of rule, the float shadow, with [corner] corners. */
@Composable
fun Modifier.floating(corner: Dp): Modifier {
    val z = Zen.colors
    val shape = RoundedCornerShape(corner)
    return floatShadow(corner, z.paper, z.dark).background(z.paper, shape).border(1.dp, z.rule, shape)
}

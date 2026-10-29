package com.murekkep.notebook.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The look of the chrome: paper and ink. Warm off-white surfaces, the icon's navy ink as the accent,
// a soft gold for the Pro pens. The dark theme is a desk lamp at night, not pure black.

/** The star on the Pro pens. */
val PremiumGold = Color(0xFFC9A43C)

private val Ink = Color(0xFF1E2A5A)

private val LightColors = lightColorScheme(
    primary = Ink,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFDFE5F8),
    onPrimaryContainer = Color(0xFF0F1A42),
    secondary = Color(0xFF6E5A2E),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFF4E8CC),
    onSecondaryContainer = Color(0xFF3A2E12),
    tertiary = Color(0xFF2E6B6A),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFCFEDEA),
    onTertiaryContainer = Color(0xFF0E3332),
    background = Color(0xFFF4F1EA),
    onBackground = Color(0xFF1C1B18),
    surface = Color(0xFFFCFAF5),
    onSurface = Color(0xFF1C1B18),
    surfaceVariant = Color(0xFFECE7DC),
    onSurfaceVariant = Color(0xFF585650),
    outline = Color(0xFF8A8780),
    outlineVariant = Color(0xFFD8D3C7),
    error = Color(0xFFB3261E),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFF9DEDC),
    onErrorContainer = Color(0xFF410E0B),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFB9C4F3),
    onPrimary = Color(0xFF0E1A46),
    primaryContainer = Color(0xFF2B3A74),
    onPrimaryContainer = Color(0xFFDFE5F8),
    secondary = Color(0xFFDCC48F),
    onSecondary = Color(0xFF3A2E12),
    secondaryContainer = Color(0xFF524222),
    onSecondaryContainer = Color(0xFFF4E8CC),
    tertiary = Color(0xFF9ED6D3),
    onTertiary = Color(0xFF0E3332),
    tertiaryContainer = Color(0xFF214E4D),
    onTertiaryContainer = Color(0xFFCFEDEA),
    background = Color(0xFF151518),
    onBackground = Color(0xFFE8E4DC),
    surface = Color(0xFF1D1D21),
    onSurface = Color(0xFFE8E4DC),
    surfaceVariant = Color(0xFF2B2B31),
    onSurfaceVariant = Color(0xFFC3BFB5),
    outline = Color(0xFF8C8980),
    outlineVariant = Color(0xFF3E3E45),
    error = Color(0xFFF2B8B5),
    onError = Color(0xFF601410),
    errorContainer = Color(0xFF8C1D18),
    onErrorContainer = Color(0xFFF9DEDC),
)

private val MurekkepTypography = Typography(
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 22.sp, lineHeight = 28.sp, letterSpacing = (-0.2).sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp, letterSpacing = 0.sp),
    bodyMedium = TextStyle(fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp, letterSpacing = 0.1.sp),
    bodySmall = TextStyle(fontWeight = FontWeight.Normal, fontSize = 12.sp, lineHeight = 16.sp, letterSpacing = 0.2.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp, letterSpacing = 0.sp),
    labelSmall = TextStyle(fontWeight = FontWeight.Medium, fontSize = 11.sp, lineHeight = 16.sp, letterSpacing = 0.6.sp),
)

private val MurekkepShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

@Composable
fun MurekkepTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = MurekkepTypography,
        shapes = MurekkepShapes,
        content = content,
    )
}

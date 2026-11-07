package com.stillmusic.player

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Resolve the accent from the current palette so controls remain legible in either appearance.
val StillBlue: Color
    @Composable get() = MaterialTheme.colorScheme.primary

@Composable fun StillTheme(dark: Boolean, content: @Composable () -> Unit) {
    val colors = if (dark) darkColorScheme(
        primary = Color(0xFF9AB9FF), onPrimary = Color(0xFF112B55),
        primaryContainer = Color(0xFF253B60), onPrimaryContainer = Color(0xFFD8E5FF),
        secondaryContainer = Color(0xFF253B60), onSecondaryContainer = Color(0xFFD8E5FF),
        background = Color(0xFF000000), onBackground = Color(0xFFF4F4F6),
        surface = Color(0xFF1C1C1E), onSurface = Color(0xFFF4F4F6),
        surfaceVariant = Color(0xFF282B30), onSurfaceVariant = Color(0xFFAAADB5),
        outlineVariant = Color(0xFF34373D))
    else lightColorScheme(
        primary = Color(0xFF315DA8), onPrimary = Color.White,
        primaryContainer = Color(0xFFE3ECFC), onPrimaryContainer = Color(0xFF18365E),
        secondaryContainer = Color(0xFFE3ECFC), onSecondaryContainer = Color(0xFF18365E),
        background = Color(0xFFFFFFFF), onBackground = Color(0xFF191B20),
        surface = Color(0xFFF2F2F7), onSurface = Color(0xFF191B20),
        surfaceVariant = Color(0xFFE7E9EE), onSurfaceVariant = Color(0xFF626670),
        outlineVariant = Color(0xFFDFE1E6))
    MaterialTheme(colorScheme = colors, typography = Typography(
        headlineLarge = androidx.compose.ui.text.TextStyle(fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold, letterSpacing = (-.7).sp),
        headlineSmall = androidx.compose.ui.text.TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.Bold),
        titleMedium = androidx.compose.ui.text.TextStyle(fontSize = 17.sp, lineHeight = 24.sp, fontWeight = FontWeight.Medium),
        bodyLarge = androidx.compose.ui.text.TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
        bodyMedium = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
        bodySmall = androidx.compose.ui.text.TextStyle(fontSize = 12.sp, lineHeight = 18.sp)
    ), shapes = Shapes(small = RoundedCornerShape(10.dp), medium = RoundedCornerShape(16.dp), large = RoundedCornerShape(24.dp)), content = content)
}

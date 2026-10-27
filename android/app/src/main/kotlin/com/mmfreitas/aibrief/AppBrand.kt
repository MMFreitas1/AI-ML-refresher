package com.mmfreitas.aibrief

import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily
import com.mmfreitas.aibrief.brand.BrandKit

/**
 * The app's look: colors, fonts and launch intro. The name and icon are Android resources
 * (app_name, ic_launcher).
 *
 * Official releases are built with a private brand kit (not part of this repository; see BRAND.md),
 * which provides its own `BrandKit`. Without it, `src/neutral` supplies a neutral one, so the
 * project builds and runs as-is.
 */
interface Brand {
    val isBranded: Boolean

    /** Replaces the default (dynamic or baseline) color scheme, or null to keep it. */
    fun colorScheme(dark: Boolean): ColorScheme? = null

    /** Font for the whole app, or null for the system font. */
    val fontFamily: FontFamily? get() = null

    /** Whether there is a launch intro to play. */
    val hasIntro: Boolean get() = false

    /** The launch intro. Loops while [isReady] returns false, then calls [onFinish]. */
    @Composable
    fun Intro(isReady: () -> Boolean, onFinish: () -> Unit) = onFinish()
}

val AppBrand: Brand = BrandKit

import 'package:flutter/material.dart';

import '../../domain/models/schedule_models.dart';

/// "Celestial Observatory" design system for SeiReminds:
/// - Light: Imperial Vellum (#F7F3EA) + Midnight Indigo (#152447) + Antique Gold (#9A6E1B)
/// - Dark: Obsidian Sapphire (#090E1A) + Midnight Lapis (#10182A) + Burnished Gold (#E8BE65)
class AppTheme {
  static const Color imperialObsidian = Color(0xFF090E1A);
  static const Color imperialSapphire = Color(0xFF152447);
  static const Color imperialSapphireDeep = Color(0xFF0D1730);
  static const Color imperialSapphireBright = Color(0xFF1F3466);
  static const Color burnishedGold = Color(0xFFE8BE65);
  static const Color antiqueGold = Color(0xFF9A6E1B);
  static const Color warmVellum = Color(0xFFF7F3EA);
  static const Color parchmentIvory = Color(0xFFFFFDF8);

  static Color goldAccent(Brightness brightness) =>
      brightness == Brightness.dark ? burnishedGold : antiqueGold;

  static Color goldHairline(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF5A4722)
          : const Color(0xFFD6BE8A);

  static LinearGradient royalBannerGradient(Brightness brightness) {
    return brightness == Brightness.dark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF0B1328),
              Color(0xFF152447),
              Color(0xFF0E172E),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF101C3B),
              Color(0xFF1C3060),
              Color(0xFF152447),
            ],
          );
  }

  /// Tabular numeric style for aligned clock times, durations, and badges.
  static TextStyle tabularStyle(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF152447),
      onPrimary: Color(0xFFFAF4E4),
      primaryContainer: Color(0xFFEAE0C6),
      onPrimaryContainer: Color(0xFF182545),
      secondary: Color(0xFF9A6E1B),
      onSecondary: Color(0xFFFFFDF8),
      secondaryContainer: Color(0xFFF4E8CB),
      onSecondaryContainer: Color(0xFF473007),
      tertiary: Color(0xFF0F6963),
      onTertiary: Color(0xFFF4FFFD),
      tertiaryContainer: Color(0xFFD7EFEA),
      onTertiaryContainer: Color(0xFF093B38),
      error: Color(0xFF9E222B),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFCE4E6),
      onErrorContainer: Color(0xFF681118),
      surface: Color(0xFFFFFDF8),
      onSurface: Color(0xFF141B2D),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF5EFE2),
      surfaceContainer: Color(0xFFEEE6D5),
      surfaceContainerHigh: Color(0xFFE5DAC4),
      surfaceContainerHighest: Color(0xFFDCCEB3),
      onSurfaceVariant: Color(0xFF4E566A),
      outline: Color(0xFFB5A486),
      outlineVariant: Color(0xFFDFD3BC),
      shadow: Color(0xFF0D1426),
      scrim: Color(0xFF090E1A),
      inverseSurface: Color(0xFF152447),
      onInverseSurface: Color(0xFFF6F1E4),
      inversePrimary: Color(0xFFE8BE65),
    );
    return _base(colorScheme, scaffoldBg: warmVellum);
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFE8BE65),
      onPrimary: Color(0xFF141007),
      primaryContainer: Color(0xFF2B2415),
      onPrimaryContainer: Color(0xFFF7DEA3),
      secondary: Color(0xFF83C5FA),
      onSecondary: Color(0xFF07192B),
      secondaryContainer: Color(0xFF192B4D),
      onSecondaryContainer: Color(0xFFD6E9FF),
      tertiary: Color(0xFF56D4C8),
      onTertiary: Color(0xFF042523),
      tertiaryContainer: Color(0xFF123635),
      onTertiaryContainer: Color(0xFFB8F2EC),
      error: Color(0xFFF47C84),
      onError: Color(0xFF2B080B),
      errorContainer: Color(0xFF3C141B),
      onErrorContainer: Color(0xFFFFD6D9),
      surface: Color(0xFF10182B),
      onSurface: Color(0xFFF4EFE2),
      surfaceContainerLowest: Color(0xFF080C17),
      surfaceContainerLow: Color(0xFF0D1424),
      surfaceContainer: Color(0xFF141F35),
      surfaceContainerHigh: Color(0xFF1C2944),
      surfaceContainerHighest: Color(0xFF243354),
      onSurfaceVariant: Color(0xFFA8B3CA),
      outline: Color(0xFF6B5D42),
      outlineVariant: Color(0xFF273552),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFF4EFE2),
      onInverseSurface: Color(0xFF10182B),
      inversePrimary: Color(0xFF152447),
    );
    return _base(colorScheme, scaffoldBg: imperialObsidian);
  }

  static TextTheme _buildTextTheme(ColorScheme cs) {
    final base = cs.brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;

    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontFamily: 'serif',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: cs.onSurface,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontFamily: 'serif',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: cs.onSurface,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontFamily: 'serif',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: cs.onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontFamily: 'serif',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: cs.onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontFamily: 'serif',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: cs.onSurface,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: cs.onSurface,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: cs.onSurface,
        height: 1.4,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: cs.onSurface,
        height: 1.4,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: cs.onSurfaceVariant,
        height: 1.35,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.25,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.25,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }

  static ThemeData _base(
    ColorScheme colorScheme, {
    required Color scaffoldBg,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final textTheme = _buildTextTheme(colorScheme);
    final focusGold = goldAccent(colorScheme.brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerLow
            : colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusGold, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: goldHairline(colorScheme.brightness)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? burnishedGold : imperialSapphire,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? burnishedGold : imperialSapphire,
        foregroundColor: isDark ? const Color(0xFF141007) : parchmentIvory,
        elevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark
                ? const Color(0xFFF6DF9E)
                : const Color(0xFFD6B15E),
            width: 1,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: goldHairline(colorScheme.brightness),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          side: BorderSide(color: goldHairline(colorScheme.brightness)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: goldHairline(colorScheme.brightness)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1F2E50) : imperialSapphire,
        contentTextStyle: const TextStyle(
          color: Color(0xFFF7F2E4),
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF8C6B28), width: 1),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? const Color(0xFF141007) : parchmentIvory;
          }
          return colorScheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? burnishedGold : imperialSapphire;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    );
  }

  static Color sessionColor(SessionType type, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (type) {
      SessionType.onlineTime =>
        isDark ? const Color(0xFF56D4C8) : const Color(0xFF0F6963),
      SessionType.lecture =>
        isDark ? burnishedGold : imperialSapphire,
      SessionType.laboratory =>
        isDark ? const Color(0xFFC79BFF) : const Color(0xFF6B2B7E),
    };
  }

  static IconData sessionIcon(SessionType type) {
    return switch (type) {
      SessionType.onlineTime => Icons.videocam_outlined,
      SessionType.lecture => Icons.menu_book_outlined,
      SessionType.laboratory => Icons.science_outlined,
    };
  }
}

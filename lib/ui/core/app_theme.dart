import 'package:flutter/material.dart';

import '../../domain/models/schedule_models.dart';

class AppTheme {
  static const Color seedColor = Color(0xFF2B4C9B);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return _base(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _base(colorScheme);
  }

  static ThemeData _base(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
    );
  }

  static Color sessionColor(SessionType type, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (type) {
      SessionType.onlineTime =>
        isDark ? const Color(0xFF4DD0C8) : const Color(0xFF0E7A75),
      SessionType.lecture =>
        isDark ? const Color(0xFF9BB2FF) : const Color(0xFF2B4C9B),
      SessionType.laboratory =>
        isDark ? const Color(0xFFFFB74D) : const Color(0xFFB85D00),
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

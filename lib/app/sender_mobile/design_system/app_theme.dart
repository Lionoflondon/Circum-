import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Canonical Sender visual tokens. Product modules may add an accent colour,
/// but shared layout, surface, type and motion values belong here.
abstract final class AppTokens {
  static const background = Color(0xFF07090F);
  static const midnight = Color(0xFF0B1020);
  static const panel = Color(0xFF0D111C);
  static const raisedPanel = Color(0xFF121729);
  static const primary = Color(0xFF3B82F6);
  static const primaryLight = Color(0xFF60A5FA);
  static const text = Color(0xFFF5F7FB);
  static const mutedText = Color(0xFF9CA3AF);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFEF4444);
  static const glass = Color(0x0DF5F7FB);
  static const glassBorder = Color(0x29FFFFFF);
  static const strongGlass = Color(0xFA0C121C);
  static const strongGlassBorder = Color(0x2EFFFFFF);

  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;

  static const radius12 = 12.0;
  static const radius16 = 16.0;
  static const radius22 = 22.0;
  static const radius24 = 24.0;
  static const radius30 = 30.0;

  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);

  static const cardShadow = BoxShadow(
    color: Color(0x52000000),
    blurRadius: 28,
    offset: Offset(0, 12),
  );
}

abstract final class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final text = GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppTokens.text, displayColor: AppTokens.text);
    return base.copyWith(
      scaffoldBackgroundColor: AppTokens.background,
      colorScheme: const ColorScheme.dark(
        primary: AppTokens.primary,
        secondary: AppTokens.primaryLight,
        surface: AppTokens.panel,
        onSurface: AppTokens.text,
        error: AppTokens.danger,
      ),
      textTheme: text,
      cardTheme: CardThemeData(
        color: AppTokens.glass,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius24),
          side: const BorderSide(color: AppTokens.glassBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppTokens.glassBorder,
        thickness: 1,
      ),
    );
  }
}

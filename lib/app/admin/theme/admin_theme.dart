import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_tokens.dart';

abstract final class AdminTheme {
  static ThemeData get data {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AdminTokens.bg0,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AdminTokens.accent,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AdminTokens.text,
        displayColor: AdminTokens.text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminTokens.glass,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminTokens.controlRadius),
          borderSide: const BorderSide(color: AdminTokens.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminTokens.controlRadius),
          borderSide: const BorderSide(color: AdminTokens.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminTokens.controlRadius),
          borderSide: const BorderSide(color: AdminTokens.accent),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

abstract final class AdminTokens {
  static const bg0 = Color(0xFF05070C);
  static const bg1 = Color(0xFF0A0F1A);
  static const bg2 = Color(0xFF0D1524);

  static const glass = Color(0x0EFFFFFF);
  static const glassStrong = Color(0x17FFFFFF);
  static const glassBorder = Color(0x1CFFFFFF);
  static const glassBorderStrong = Color(0x2EFFFFFF);
  static const hairline = Color(0x2EFFFFFF);
  static const blueGlow = Color(0x59628DFF);
  static const cyanGlow = Color(0x3522D3EE);

  static const text = Colors.white;
  static const muted = Color(0xA3FFFFFF);
  static const subtle = Color(0x7AFFFFFF);
  static const accent = Color(0xFF7DD3FC);
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFFB7185);

  static const panelRadius = 18.0;
  static const controlRadius = 12.0;
  static const pagePadding = 24.0;
  static const panelPadding = 18.0;
  static const blurSigma = 22.0;
  static const hoverDuration = Duration(milliseconds: 100);
  static const motionDuration = Duration(milliseconds: 200);

  static const displayFont = 'DM Serif Display';
  static const bodyFont = 'Inter';
  static const monoFont = 'JetBrains Mono';

  static const pageGradient = LinearGradient(
    colors: [bg0, bg1, bg2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

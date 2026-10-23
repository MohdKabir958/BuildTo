import 'package:flutter/material.dart';

class BuildtoColors {
  BuildtoColors._();

  // Primary palette matching the 16 reference screens
  static const Color primaryNavy = Color(0xFF002B5B);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color bgWhite = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color cardBorderLight = Color(0xFFEEF2F6);

  // Typography & ink
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textLight = Color(0xFF94A3B8);

  // Status & action colors
  static const Color successGreen = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color errorRed = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEE2E2);
  static const Color infoBlue = Color(0xFF0284C7);
  static const Color infoBg = Color(0xFFE0F2FE);
  static const Color warningAmber = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFEF3C7);
}

class BuildtoRadius {
  BuildtoRadius._();

  static const double sm = 6.0;
  static const double md = 10.0;
  static const double lg = 14.0;
  static const double xl = 18.0;
  static const double pill = 999.0;
}

class BuildtoShadows {
  BuildtoShadows._();

  static final List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static final List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

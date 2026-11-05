import 'package:flutter/material.dart';

/// BuildTo supplier design tokens, grounded in the 16-screen approved PDF.
/// Primary and accent exactly match branding/brand.json; supporting tokens
/// are centralized pending stakeholder visual sign-off on raster mock fidelity.
abstract final class BuildToPalette {
  static const navy = Color(0xFF002B5B);
  static const navyDeep = Color(0xFF031A40);
  static const blue = Color(0xFF1076C5);
  static const sky = Color(0xFFEAF6FF);
  static const orange = Color(0xFFF59E0B);
  static const canvas = Color(0xFFF7FAFE);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF082448);
  static const muted = Color(0xFF516580);
  static const outline = Color(0xFFD9E6F2);
  static const success = Color(0xFF087945);
  static const successTint = Color(0xFFE7F7EE);
  static const warning = Color(0xFF9A5800);
  static const warningTint = Color(0xFFFFF3D9);
  static const danger = Color(0xFFB52633);
  static const dangerTint = Color(0xFFFFEDF0);
}

abstract final class BuildToSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const cardRadius = 18.0;
  static const fieldRadius = 14.0;
  static const maxContentWidth = 720.0;
  static const minTapTarget = 48.0;
}

abstract final class BuildToTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BuildToPalette.navy,
      brightness: Brightness.light,
      primary: BuildToPalette.navy,
      onPrimary: BuildToPalette.white,
      secondary: BuildToPalette.orange,
      onSecondary: BuildToPalette.navyDeep,
      surface: BuildToPalette.white,
      onSurface: BuildToPalette.ink,
      error: BuildToPalette.danger,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: BuildToPalette.canvas,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: BuildToPalette.canvas,
        foregroundColor: BuildToPalette.navy,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            color: BuildToPalette.navyDeep),
        headlineSmall: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: BuildToPalette.navyDeep),
        titleLarge: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: BuildToPalette.navyDeep),
        titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: BuildToPalette.navyDeep),
        bodyMedium: const TextStyle(
            fontSize: 14, height: 1.4, color: BuildToPalette.ink),
        bodySmall: const TextStyle(
            fontSize: 12, height: 1.4, color: BuildToPalette.muted),
      ),
      cardTheme: CardThemeData(
        color: BuildToPalette.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BuildToSpace.cardRadius),
          side: const BorderSide(color: BuildToPalette.outline),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize:
              const Size(BuildToSpace.minTapTarget, BuildToSpace.minTapTarget),
          backgroundColor: BuildToPalette.navy,
          foregroundColor: BuildToPalette.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BuildToSpace.fieldRadius)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize:
              const Size(BuildToSpace.minTapTarget, BuildToSpace.minTapTarget),
          foregroundColor: BuildToPalette.navy,
          side: const BorderSide(color: BuildToPalette.navy),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BuildToSpace.fieldRadius)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BuildToPalette.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BuildToSpace.fieldRadius),
          borderSide: const BorderSide(color: BuildToPalette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BuildToSpace.fieldRadius),
          borderSide: const BorderSide(color: BuildToPalette.blue, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BuildToPalette.white,
        indicatorColor: BuildToPalette.sky,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? BuildToPalette.navy
                  : BuildToPalette.muted,
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? BuildToPalette.orange
                  : BuildToPalette.navy,
              size: 22,
            )),
      ),
      dividerTheme:
          const DividerThemeData(color: BuildToPalette.outline, space: 1),
    );
  }
}

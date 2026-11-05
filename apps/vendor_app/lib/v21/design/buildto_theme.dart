import 'package:flutter/material.dart';
import 'buildto_tokens.dart';

/// Independent V2.1 supplier theme. Does not alter the live legacy app's
/// KraveoTheme or the existing customer application.
abstract final class BuildtoSupplierTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: BuildtoPalette.navy,
      onPrimary: BuildtoPalette.white,
      secondary: BuildtoPalette.amber,
      onSecondary: BuildtoPalette.navyDeep,
      surface: BuildtoPalette.white,
      onSurface: BuildtoPalette.ink,
      error: BuildtoPalette.danger,
      onError: BuildtoPalette.white,
      outline: BuildtoPalette.border,
    );

    const headings = TextTheme(
      displaySmall: TextStyle(
        fontSize: 32, height: 1.13, fontWeight: FontWeight.w800,
        color: BuildtoPalette.navyDeep, letterSpacing: -0.8),
      headlineSmall: TextStyle(
        fontSize: 25, height: 1.19, fontWeight: FontWeight.w800,
        color: BuildtoPalette.navyDeep, letterSpacing: -0.6),
      titleLarge: TextStyle(
        fontSize: 20, height: 1.26, fontWeight: FontWeight.w800,
        color: BuildtoPalette.navyDeep, letterSpacing: -0.3),
      titleMedium: TextStyle(
        fontSize: 16, height: 1.3, fontWeight: FontWeight.w700,
        color: BuildtoPalette.navyDeep),
      bodyLarge: TextStyle(
        fontSize: 16, height: 1.47, fontWeight: FontWeight.w400,
        color: BuildtoPalette.ink),
      bodyMedium: TextStyle(
        fontSize: 14, height: 1.43, color: BuildtoPalette.ink),
      bodySmall: TextStyle(
        fontSize: 12, height: 1.45, color: BuildtoPalette.muted),
      labelLarge: TextStyle(
        fontSize: 15, height: 1.22, fontWeight: FontWeight.w800),
      labelMedium: TextStyle(
        fontSize: 12, height: 1.2, fontWeight: FontWeight.w700),
    );

    final fieldShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: BuildtoPalette.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      textTheme: headings,
      scaffoldBackgroundColor: BuildtoPalette.canvas,
      canvasColor: BuildtoPalette.canvas,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        centerTitle: false, elevation: 0, scrolledUnderElevation: 0,
        backgroundColor: BuildtoPalette.white,
        foregroundColor: BuildtoPalette.navyDeep,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: BuildtoPalette.border,
      iconTheme: const IconThemeData(color: BuildtoPalette.navy, size: 22),
      cardTheme: CardThemeData(
        elevation: 0,
        color: BuildtoPalette.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: BuildtoPalette.border),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, BuildtoSpace.buttonHeight),
          backgroundColor: BuildtoPalette.navy,
          foregroundColor: BuildtoPalette.white,
          disabledBackgroundColor: BuildtoPalette.border,
          disabledForegroundColor: BuildtoPalette.muted,
          elevation: 0,
          textStyle: headings.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, BuildtoSpace.buttonHeight),
          foregroundColor: BuildtoPalette.navy,
          side: const BorderSide(color: BuildtoPalette.navy, width: 1.15),
          textStyle: headings.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BuildtoPalette.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: headings.bodyMedium?.copyWith(color: BuildtoPalette.muted),
        enabledBorder: fieldShape,
        border: fieldShape,
        focusedBorder: fieldShape.copyWith(
          borderSide: const BorderSide(color: BuildtoPalette.navyBright, width: 2),
        ),
        errorBorder: fieldShape.copyWith(
          borderSide: const BorderSide(color: BuildtoPalette.danger),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BuildtoPalette.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BuildtoPalette.navyDeep,
        contentTextStyle: headings.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BuildtoPalette.navy,
        linearTrackColor: BuildtoPalette.border,
      ),
    );
  }
}

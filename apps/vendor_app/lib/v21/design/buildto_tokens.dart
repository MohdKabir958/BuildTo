import 'package:flutter/material.dart';

/// BuildTo V2.1 supplier colors, aligned to branding/brand.json and the
/// customer-app's BuildtoColors. Do not import the legacy Grozo palette.
abstract final class BuildtoPalette {
  static const navy = Color(0xFF002B5B);
  static const navyDeep = Color(0xFF001C3B);
  static const navyBright = Color(0xFF07559A);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFFF4D9);
  static const canvas = Color(0xFFF8FAFC);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const borderLight = Color(0xFFEEF2F6);
  static const paleBlue = Color(0xFFEAF5FF);
  static const success = Color(0xFF167A42);
  static const successTint = Color(0xFFE7F7EC);
  static const caution = Color(0xFF955900);
  static const cautionTint = Color(0xFFFFF3D7);
  static const danger = Color(0xFFC52B33);
  static const dangerTint = Color(0xFFFFEBEC);
  static const info = Color(0xFF07559A);
  static const infoTint = Color(0xFFE8F3FE);
}

/// Consistent dimensions across feature PRs. For supplier/mobile touch targets
/// 48dp is the minimum; controls use 52dp by default.
abstract final class BuildtoSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 28.0;
  static const pageGutter = 20.0;
  static const minTouch = 48.0;
  static const buttonHeight = 52.0;
  static const contentMaxWidth = 720.0;
}

abstract final class BuildtoCorners {
  static const sm = Radius.circular(10);
  static const md = Radius.circular(14);
  static const lg = Radius.circular(18);
  static const xl = Radius.circular(24);
  static const pill = Radius.circular(999);
}

enum BuildtoTone { neutral, information, success, warning, danger }

extension BuildtoToneColors on BuildtoTone {
  Color get foreground => switch (this) {
    BuildtoTone.neutral => BuildtoPalette.navy,
    BuildtoTone.information => BuildtoPalette.info,
    BuildtoTone.success => BuildtoPalette.success,
    BuildtoTone.warning => BuildtoPalette.caution,
    BuildtoTone.danger => BuildtoPalette.danger,
  };

  Color get background => switch (this) {
    BuildtoTone.neutral => BuildtoPalette.canvas,
    BuildtoTone.information => BuildtoPalette.infoTint,
    BuildtoTone.success => BuildtoPalette.successTint,
    BuildtoTone.warning => BuildtoPalette.cautionTint,
    BuildtoTone.danger => BuildtoPalette.dangerTint,
  };
}
